# Fase N1 — Fechamento do MVP + Scheduler do Worker

> **Status:** Plano de execução — criado em **2026-07-06**. Primeira fase do
> backlog pós-MVP (N1–N5) definido em
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md) §"Próximos passos".
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** consolidar o MVP operacional em `dev`/produção e **fechar a única
> lacuna estrutural da F4** — o **scheduler temporal do `worker`** (timeout de
> feedback + disparo de purga de mídia), substituindo o Celery beat da v1.
> **Regra inegociável (herdada):** tudo que cria/altera comportamento passa pela
> **observabilidade** (logs/spans com `tenant_id`/`traceparent` + auditoria quando
> toca estado sensível; nunca vaza segredo/PII). Ver
> [05-observabilidade.md](./05-observabilidade.md) e
> [15-plano-finalizacao-em-andamento.md §1](./15-plano-finalizacao-em-andamento.md).

---

## 0. Estado real (aterramento)

| Área | Arquivo | Estado confirmado | Impacto |
|---|---|---|---|
| Loop do `worker` | `worker/src/main.rs:41` | Só **consome o bus** (`processar_mensagem_recebida`/`processar_status_mensagem`). **Não há tarefa temporal** (tick/scheduler). | N1.2 adiciona um loop temporal em `tokio::spawn`. |
| Consumidor de purga | `data_storage/src/main.rs:50` (`processar_purga_midia`) | **JÁ consome** eventos de purga do bus e remove do R2. | N1.2 só precisa **publicar** o evento de purga; o consumo já existe. |
| Outbox relay | `data_postgres/src/outbox_relay.rs:157` (`OutboxRelay::run`) | Drena a tabela `outbox` (0011) e publica no bus (`fetch_pending`/`mark_published`). | N1.3 confirma que a mensagem do atendente percorre o relay até o envio. |
| Envio outbound | `worker/src/main.rs:389` (`SendWhatsappMessage`) | Worker **já chama** `data_whatsapp::SendWhatsappMessage` para a resposta do bot. | N1.3 estende o mesmo caminho para a mensagem **do atendente** (via outbox). |
| Estado do atendimento | `0006_atendimentos.sql` | Campos `status` (`fila`/…), `feedback TEXT`, `historico_status JSONB`, `data_ultima_mensagem`. | N1.2 varre atendimentos aguardando feedback vencido. |
| Stack Grafana | `docker/observability/compose.yml` | LGTM no ar (OTel/Loki/Tempo/Prometheus/Grafana/Promtail). **Sem dashboards curados.** | N1.4 cura dashboards/alertas. |

> **Conclusão:** N1 é **cirúrgico**. O peso está em N1.2 (scheduler novo) e na
> validação ponta-a-ponta; N1.1/N1.3/N1.4 são consolidação/curadoria.

---

## 1. Escopo

### Dentro do escopo
- **N1.1** — Merge de `feature/mvp-telas-e-endurecimento` → `dev` + validação no ambiente dev.
- **N1.2** — Scheduler temporal do `worker` (F4.3b): timeout de feedback + disparo de purga de mídia.
- **N1.3** — Fechar o elo **outbox → outbound do atendente** (`SendOutboundMessage` → relay → `data_whatsapp`).
- **N1.4** — Dashboards Grafana com dados reais + alertas básicos (devops-4 / F9.1).

### Fora do escopo (fases seguintes)
- Retenção **por política de billing/plano** → N4 (aqui só o mecanismo de purga por TTL/idade).
- `ia_engine` → N2.

---

## 2. Contrato de observabilidade (DoD transversal)

Cada tarefa que cria/altera comportamento:
- **Telemetria:** span com `tenant_id`/`trace_id` (`#[tracing::instrument]` ou `tenant_span!`); propaga `traceparent` W3C ao próximo salto (bus/RPC); log estruturado, sem string solta.
- **Auditoria:** evento `<dominio>.<acao>` (snake) por ação sensível; `AuditLogger` via Redis (`security:stream`), consumido pelo `data_postgres`. Metadados: `user_id`/`ip`/`user_agent` quando houver ator.
- **Sanitização:** proibido logar token de instância, JWT, api key, payload bruto, telefone completo (mascarar `+55 11 9****-1234`).

---

## 3. N1.1 — Merge e validação do MVP em dev

**Tarefas**
1. Abrir PR `feature/mvp-telas-e-endurecimento` → `dev`; a branch já passou pelo gate `prevc-final-review`.
2. Deploy automático de `dev` (self-hosted runner). Smoke: login no admin web (`/v2/admin`), fila carrega, mover card no Kanban persiste, chat recebe evento em tempo real, mensagem do atendente sai.
3. Rodar `.\infra\test-local.ps1` e `.\infra\test-flutter.ps1` no ambiente dev.

**DoD:** merge feito; smoke ponta-a-ponta verde em dev; suítes canônicas verdes.

---

## 4. N1.2 — Scheduler temporal do `worker` (F4.3b)

**Motivação:** hoje nenhuma regra depende do tempo. A v1 usava Celery beat para
(a) **encerrar/marcar atendimentos** cujo prazo de feedback venceu e (b) **purgar
mídias** antigas. Ambos passam a ser um **loop temporal** no `worker`.

### 4.1 Tarefas
1. **Loop de scheduler** em `tokio::spawn` no boot do `worker` (paralelo ao consumidor do bus), com intervalo configurável (`SCHEDULER_TICK_SECS`, default 60s). Cada tick roda as varreduras abaixo com log estruturado (`scheduler.tick`, contadores por ação).
2. **Timeout de feedback** — novo RPC de leitura no `data_postgres`
   (`ListarAtendimentosFeedbackVencido { limite }`) que seleciona atendimentos em
   estado de espera de feedback com `data_ultima_mensagem` além do TTL do tenant
   (config via `TenantConfigCache`; default global). Para cada um: RPC de
   transição de estado (encerrar/registrar), auditado `atendimento.feedback_expirado` (INFO).
3. **Disparo de purga de mídia** — novo RPC de leitura
   (`ListarMidiasExpiradas { limite, idade_max }`) que lista `MediaPointer`s além
   da idade máxima (default 30 dias, alinhado ao R2 lifecycle). Para cada um: o
   worker **publica o evento de purga no bus** — o `data_storage` **já o consome**
   (`processar_purga_midia`). Evento `midia.purgada` (INFO) auditado no consumidor.
4. **Idempotência e concorrência** — varredura em lotes com `LIMIT`; marcação
   (`purge_requested_at`/estado) para não reprocessar; lock Redis por tarefa
   (`tenant:{id}:lock:scheduler:<tarefa>`) reusando o padrão de debounce já no worker.

### 4.2 SOLID / Ports & Adapters
- **Port novo** `SchedulerClock` (fonte de tempo, injetável para teste) e os RPCs
  de leitura no `data_postgres` como novos handlers sobre repositórios existentes
  (`atendimentos/`, `treinamento/`+`MediaPointer`). O loop depende de `Arc<dyn ...>`
  dos clientes RPC já no estado — **sem** `conectar_cliente` por tick.

### 4.3 Observabilidade & auditoria
- Span `scheduler.tick` por ciclo (contagem de vencidos/purgados, `trace_id` novo por tick).
- Auditoria: `atendimento.feedback_expirado`, `midia.purgada` (o consumidor de purga do `data_storage` grava o evento). Caminho feliz de varredura vazia **não** audita (evita inundar a trilha).
- Sanitização: nunca logar conteúdo/telefone; só ids e contadores.

### 4.4 DoD
- Atendimento com feedback vencido é transicionado no próximo tick e auditado;
  mídia além da idade máxima é removida do R2 (via evento → `data_storage`);
  varredura idempotente (rodar 2 ticks não duplica efeito); `clippy -D warnings` +
  `.\infra\test-local.ps1` verde.

---

## 5. N1.3 — Elo outbox → outbound do atendente

**Estado:** `SendOutboundMessage` (WS-6.3) **persiste** a mensagem do atendente via
`persistir_mensagem` (padrão outbox). O `OutboxRelay` drena a `outbox`. Falta
**confirmar/fechar** que o evento drenado dispara o envio real ao WhatsApp.

### 5.1 Tarefas
1. Auditar o fluxo: `SendOutboundMessage` → linha em `outbox` (event_type de envio)
   → `OutboxRelay` publica no bus → **consumidor** que chama
   `data_whatsapp::SendWhatsappMessage`. Se o consumidor do evento de envio do
   atendente **não existir**, criá-lo no `worker` (mesmo caminho da resposta do bot
   em `main.rs:389`), com **retry/backoff** e atualização de `status_envio`
   (`pending`→`sent`/`failed`) da `oraculo_mensagem`.
2. Confirmação de entrega: `processar_status_mensagem` (já existe) atualiza o
   `status_envio` a partir dos webhooks de status do Evolution.

### 5.2 DoD
- Mensagem enviada pelo atendente na tela chega ao WhatsApp do contato; `status_envio`
  reflete `sent`/`failed`; falha de envio faz retry com backoff e é auditada
  (`mensagem.envio_falhou` WARN, sem conteúdo). Sem PII em log.

---

## 6. N1.4 — Dashboards e alertas Grafana

### 6.1 Tarefas
1. Dashboards no Grafana (provisionados como código em `docker/observability/`):
   - **Saúde de serviços** (`GetServiceHealth`/uptime por binário).
   - **Latência gRPC** (histogramas por RPC) e **taxa de erro** (`error_code`).
   - **Backlog de outbox** (`smartcore_outbox_backlog`) e **lag de consumer groups**.
   - **Cadeia de trace** (Tempo) — buscar um `trace_id` do webhook à resposta.
2. Alertas básicos: backlog de outbox acima de limiar, taxa de erro gRPC, serviço down.

### 6.2 DoD
- Um tráfego real em dev aparece nos dashboards; um `trace_id` é seguível do
  webhook ao `audit_log` no Tempo; ≥1 alerta dispara em cenário simulado.

---

## 7. Sequenciamento e riscos

**Ordem:** N1.1 → (N1.2 ‖ N1.3) → N1.4.

| Risco | Mitigação |
|---|---|
| Scheduler dispara em múltiplas réplicas do worker | Lock Redis por tarefa/tenant (padrão de debounce já existente) |
| Purga remove mídia ainda referenciada | Idade máxima conservadora + só purgar `MediaPointer` com resumo/análise já gravados; o **resumo permanece** |
| TTL de feedback sem config do tenant | Default global no `TenantConfigCache`; documentar a chave |
| Envio outbound duplicado no retry | Idempotência por `message_id`/`stanzaId` (checklist F) |

---

## 8. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N1** | Aterrar scheduler + elo outbox | Aprovar ports RPC de varredura + `SchedulerClock` | Merge; scheduler; outbound atendente; dashboards | `test-local.ps1`: timeout+purga idempotentes; outbound entregue | Dashboards com dados reais; eventos auditados |

*Plano aterrado no código real (worker, outbox_relay, data_storage, schema 0006/0011)
e no doc de fases 02. Pronto para canonização via `/plan-restructuring` em `.context/plans/`.*
