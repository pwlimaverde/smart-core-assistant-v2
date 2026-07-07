# Fase N4 — Endurecimento de Produção (billing, quotas, retenção, segurança)

> **Status:** Plano de execução — criado em **2026-07-06**. Quarta fase do backlog
> pós-MVP (N1–N5) — ver [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Corresponde à Fase 9 (F9)** do mapa de fases.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** prontidão para **operação comercial** — **role Postgres não-superuser**
> (que fecha o buraco de RLS de dev), **billing/quotas** com enforcement no caminho
> quente, **retenção de mídia** e **segurança/carga**.
> **Regra inegociável:** observabilidade transversal; nenhuma regra de negócio nova
> sem auditoria e sem span.

---

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Role do Postgres | memória `db-remoto-role-bootstrap-superuser` | `smartcore_app` é **bootstrap superuser** no Postgres remoto de dev → **RLS não é exercitado de verdade**; teste de isolamento de `audit_log` falha sempre (ambiente, não bug). | N4.1 cria role dedicada **não-superuser** e revalida a suíte. |
| Plans/Subscription | `tenants/plans.rs`, `tenants/settings.rs` + telas admin | Persistência e CRUD prontos; **sem enforcement** no caminho quente. | N4.2 aplica limites em ingestão/envio. |
| Quota de atendentes | `operacional/atendentes.rs:148` | Já há subquery de **limite de atendimentos ativos** por atendente. | N4.2 estende o padrão a quotas de tenant (instâncias/storage). |
| Purga de mídia | `data_storage` (`processar_purga_midia`) + scheduler (N1.2) | Consumidor de purga pronto; disparo por idade vem da N1.2. | N4.3 adiciona a política **por plano/retenção configurável**. |
| Rate limiting | `data_redis` (rate_limiter de login) | Existe só para **login**. | N4.4 amplia para webhook/bus/rotas quentes. |
| Testes de isolamento | `infrastructure_postgres/tests/` | Suíte existe; parcialmente cega em dev pela role superuser. | N4.1 destrava; N4.4 amplia vazamento/carga. |

> **Conclusão:** N4.1 é **pré-condição de credibilidade** — sem role não-superuser, os
> testes de RLS não provam isolamento. Deve entrar **cedo** (pode ser antecipado para
> logo após N1).

---

## 1. Escopo

### Dentro do escopo
- **N4.1** Role Postgres dedicada **não-superuser** (dev e prod) + revalidação da suíte de isolamento.
- **N4.2** Billing/usage: medição de uso, enforcement de `plan`/`subscription`, bloqueio por inadimplência, quotas (instâncias/storage) por tenant.
- **N4.3** Retenção de mídia: TTL/lifecycle (R2 ou purga via scheduler N1.2) **por política**; o resumo permanece.
- **N4.4** Segurança e carga: auditoria RLS, testes de vazamento, rate limiting amplo, testes de rajada.

### Fora do escopo
- Dashboards (curados na N1.4) — aqui só as **métricas novas** de uso/quota.
- Local engine/offline → N5.

---

## 2. Contrato de observabilidade (DoD transversal)

- **Telemetria:** spans em enforcement (`quota.verificada`, `billing.bloqueado`) com
  `tenant_id`; métricas de uso (mensagens/mídia/instâncias por tenant) exportadas ao Prometheus.
- **Auditoria:** `tenant.bloqueado_inadimplencia` (WARN), `quota.excedida` (WARN),
  `midia.retida`/`midia.purgada` (INFO). Eventos críticos com `user_agent`/`ip`.
- **Sanitização:** métricas de uso são agregados/contadores — sem PII; nunca logar
  conteúdo ou telefone.

---

## 3. N4.1 — Role Postgres não-superuser (destrava o RLS)

**Motivação:** um superuser do Postgres **ignora RLS** — logo, em dev, as policies
fail-closed nunca são testadas de verdade e o teste de isolamento de `audit_log`
falha por ambiente (memória documentada).

**Tarefas**
1. Criar role de aplicação **`smartcore_app` não-superuser** (sem `BYPASSRLS`), com
   apenas os privilégios necessários (DML nas tabelas de domínio; sem DDL). Migrar o
   `admin_pool` (usado para audit global/operações que precisam de mais privilégio)
   para uma role separada e mínima, documentando a fronteira.
2. Ajustar provisionamento (`infra/server-setup.sh` / scripts de bootstrap do banco) e
   os `.env` por ambiente para a role nova.
3. **Revalidar** a suíte de isolamento (`infrastructure_postgres/tests/`) — o teste de
   `audit_log` que hoje falha deve **passar** com a role correta.

**DoD:** app roda com role não-superuser; suíte de isolamento **verde** (incl. o teste
antes cego); documentação da fronteira `pool` × `admin_pool` atualizada.

---

## 4. N4.2 — Billing/usage e quotas

**Tarefas**
1. **Medição de uso:** contadores por tenant (mensagens recebidas/enviadas, mídia
   armazenada, instâncias ativas) — atualizados no caminho de ingestão/envio e expostos
   como métricas.
2. **Enforcement:** no `webhook_ingress`/`worker`/`data_whatsapp`, verificar
   `plan`/`subscription` antes de ações que consomem quota; barrar/limitar quando
   excedido, com evento `quota.excedida`.
3. **Bloqueio por inadimplência:** tenant com assinatura vencida entra em estado
   bloqueado (ingestão rejeitada de forma auditada `tenant.bloqueado_inadimplencia`);
   reflete no painel admin (rotas já existem).
4. **Quotas de instância/storage:** guard de quota ao provisionar instância Evolution e
   ao gravar mídia (reusar o padrão de subquery de limite já em `atendentes.rs`).

**DoD:** tenant que excede plano é barrado/limitado com auditoria; inadimplente
bloqueado ponta-a-ponta; métricas de uso visíveis; `clippy -D warnings` +
`.\infra\test-local.ps1` verde.

---

## 5. N4.3 — Retenção de mídia por política

**Tarefas**
1. Política de retenção configurável (por plano/tenant, default ≤ 30 dias) — o
   **scheduler (N1.2)** consulta a política e dispara purga dos `MediaPointer`s
   vencidos; o `data_storage` já remove do R2.
2. Alternativa/complemento: **R2 lifecycle** no bucket (expiração server-side) para
   defesa em profundidade. O **resumo/análise permanece** (só o binário some).
3. Documentar em [08-infraestrutura-storage.md §8](./08-infraestrutura-storage.md).

**DoD:** mídia além da retenção do plano é removida do R2; resumo persiste;
`midia.purgada` auditado; nenhum binário órfão.

---

## 6. N4.4 — Segurança e carga

**Tarefas**
1. **Auditoria RLS:** revisão das policies por tabela (fail-closed) + testes de
   vazamento cross-tenant ampliados (agora com a role não-superuser da N4.1).
2. **Rate limiting amplo:** estender o `rate_limiter` do `data_redis` (hoje só login)
   ao **webhook** (por instância/tenant) e a rotas quentes do `runtime_api`.
3. **Testes de rajada:** carga no webhook/bus (picos de `messages.upsert`), medir
   backlog de outbox e lag de consumer group; validar backpressure.
4. Revisão de segredos: garantir `SecretString` em todas as structs com credencial;
   varredura de logs por vazamento (token/JWT/api key/telefone).

**DoD:** testes de vazamento verdes com role não-superuser; rate limiting barra
rajada de webhook; teste de carga documentado com números de referência; nenhum
segredo/PII em log.

---

## 7. SOLID / Ports & Adapters

- **Quota/billing:** port `QuotaGuard { verificar(tenant, recurso) }` + adapter que lê
  `plan`/`subscription` via RPC; enforcement como **decorator** nos caminhos de
  ingestão/envio (OCP — não reescreve os handlers).
- **Retenção:** política é um value object; o scheduler depende do port de leitura de
  `MediaPointer` (N1.2) e publica no bus (adapter Redis).

---

## 8. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Migração de role quebra permissões em prod | Serviço fora do ar | Aplicar primeiro em **dev**; grants mínimos revisados; rollback documentado |
| Enforcement de quota barra tenant legítimo | Perda de mensagem | Limites conservadores + modo "log-only" antes de "enforce"; auditoria de toda negação |
| Purga remove mídia ainda em uso | Perda de dado | Só purgar com resumo/análise já gravados; retenção conservadora |
| Teste de carga instável no ambiente remoto | Falso negativo | Rodar via `test_support` (túnel); isolar janela; medir tendência, não pico único |

---

## 9. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N4** | Role não-superuser + modelo de quota | Aprovar grants mínimos + `QuotaGuard` + política de retenção | Role; enforcement; retenção; rate limiting/carga | `test-local.ps1`: isolamento verde (role real) + quota/bloqueio + carga | Métricas de uso; eventos auditados; sem vazamento |

*Plano aterrado na memória de role bootstrap, nos repos de plans/subscription, no
consumidor de purga do `data_storage` e no rate_limiter do `data_redis`. Pronto para `/plan-restructuring`.*
