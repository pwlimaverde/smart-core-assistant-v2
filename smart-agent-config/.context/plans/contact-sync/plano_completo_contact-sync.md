# Plano Completo — Sincronização de Contatos (WhatsApp ↔ Sistema)

> Reestruturado em 2026-10-01 a partir do plano base de 5 fases, conferido contra o
> **código atual** do repositório (`server/`, `mcp_server/`, `clients/`) e contra
> `doc_dev/libs/**`. Doc auxiliar: `info_aux_contact-sync.md` (ver §"Correções
> aplicadas" — vários pontos dela estão desatualizados ou não batem com o código).
> Branch de trabalho: `feature/contact-sync` a partir de `dev` (gitflow).

---

## 0. Ponto de partida real (o que JÁ existe)

O plano base supunha começar do zero (`contacts`, `contact_changes`, API REST).
O código mostra outra coisa:

| Peça | Onde | Estado |
|---|---|---|
| Tabela de contatos | `oraculo_contato` (`migrations/0004`, `0039`, `0045`) | Existe, RLS + FORCE, `UNIQUE` parcial `(tenant_id, telefone)` vivo, `excluido_em`, `nome_contato` (humano) **separado** de `nome_perfil_whatsapp` (provedor) |
| Vínculo contato ↔ cliente | `oraculo_cliente_contatos` (`0004`) | Existe (M2M) — é o que distingue "contato de cliente" |
| Vínculo contato ↔ conexão | `whatsapp_contact` (`0008`) + função `conexao_do_contato` (`0050`) | Existe |
| Ingestão do evento | `webhook_ingress` → `canonical_event` mapeia `CONTACTS`/`Contacts`/`CONTACTS_UPDATE` → tópico `whatsapp.contact.updated` | Existe |
| Consumidor | `worker::processar_contato_atualizado` → RPC `AtualizarPerfilDoContato` | Existe (P8) — **só atualiza quem já existe** (decisão LGPD explícita), 1 RPC por contato |
| Repositório | `infrastructure_postgres::clientes::contatos::atualizar_perfil_whatsapp` | Existe, `#[instrument(skip_all)]` via `run_in_tenant_transaction` |
| Cliente Evolution | `infrastructure_evolution/src/provider.rs` (header `apikey`, `SecretString`, `json_do_provedor`) | Existe; **não há rota de listagem de contatos** |
| Auditoria | `AuditPort` (`data_postgres/src/ports/audit.rs`) → `transport::bus::publicar_evento_seguranca` → stream de segurança → `audit_log` | Existe |
| Scheduler | `worker/src/scheduler.rs` (tick `tokio::time::interval` + lock Redis `SET NX PX`) | Existe |
| Métricas | `observability::usage_metrics` (OTel 0.24 → otel-collector → Prometheus); Grafana provisionado em `docker/observability/provisioning/` | Existe |
| Contratos de UI | `admin.proto` (`ListMyContatos`, `UpdateMyContato`, …) + `AdminService` gRPC-Web | Existe |
| MCP | `mcp_server/` (Python ≥3.13, SDK `mcp` 2.1.1, `grpc.aio` → `runtime_api`) com `list_contatos`/`update_contato` | Existe |
| Tela | `clients/modulos/tenant_module/lib/src/features/contatos/` (`ContatosPage`) | Existe |

**Consequência:** o trabalho é **estender** o que existe, não criar um subsistema
paralelo. As fases abaixo refletem isso.

### Regra de negócio consolidada

- **Contato de cliente** = contato com ≥1 vínculo em `oraculo_cliente_contatos`
  **ou** cujo `nome_contato` foi digitado por humano (`nome_contato_origem = 'manual'`
  ou `NULL` legado). → **Sistema ganha**: o provedor nunca sobrescreve
  `nome_contato`; diferença vira **divergência** pendente para um humano resolver.
- **Contato pessoal** = demais. → **Sincronização automática**: `nome_contato`
  acompanha o nome da agenda/perfil enquanto `nome_contato_origem = 'whatsapp'`.
- Campos de posse do provedor (`nome_perfil_whatsapp`, `nome_agenda_whatsapp`,
  `foto_perfil_url_origem`) são sempre atualizados — nunca geram divergência.
- **Criar** contato a partir da agenda do aparelho só com opt-in explícito por
  conexão (`whatsapp_instance.sincronizar_agenda = true`, default `false`) —
  preserva a decisão LGPD do P8 (ver Decisão D1).
- **Não há escrita de volta no celular.** "Sistema ganha" significa que o
  registro do sistema prevalece no sistema; a evolution-go não expõe edição da
  agenda do aparelho (a confirmar na Fase 0; o `PUT /contacts/{remoteJid}` da
  doc auxiliar é da Evolution API v2 Node, não da evolution-go).

### Decisões abertas (precisam de "sim" do usuário antes da Fase 2)

- **D1 — Importar agenda?** Opt-in por conexão (proposto) × nunca criar contato a
  partir da agenda (mantém P8 à risca). O plano assume opt-in, desligado por padrão.
- **D2 — `ip_address` no audit_log.** O `Envelope` não carrega IP hoje
  (`publicar_auditoria` grava `ip_address: None`). Propagar IP do `runtime_api`
  até o `data_postgres` é mudança transversal de contrato; o plano **não** a faz e
  registra `ip_address = NULL` com `user_agent` preenchido (já propagado). Se for
  exigido, abrir item próprio.
- **D3 — Sobreposição com N11/E6** ("perfil do contato sob demanda",
  `.context/plans/n11-operacao-cadastros.md`). Este plano absorve a parte de
  **nome**; foto continua no E6 (que já tem `foto_verificada_em`, `0039`).

---

## Fase 0 — Verificação do contrato real da evolution-go (gate)

- **Objetivo:** substituir suposições da doc auxiliar por payloads reais, antes de
  escrever código. A memória do projeto registra três bugs causados por confundir
  evolution-go com a Evolution v2 (Node).
- **Duração / complexidade:** 1 dia · BAIXA (mas bloqueante).
- **Atividades:**
  1. Ler o Swagger da instância de dev: `http://<host>:8082/swagger/doc.json`
     (fonte do contrato real). Confirmar:
     - rota de listagem de contatos da instância (candidata: `GET /user/contacts`,
       header `apikey: <token da instância>`, resposta no envelope
       `{"data": …, "message": "success"}`);
     - se existe paginação/limite; formato do JID (`@s.whatsapp.net` × `@lid`);
     - **se existe** qualquer rota de escrita de contato (esperado: não).
  2. Capturar no log do `webhook_ingress` (dev) os nomes de evento reais ao
     renomear um contato no aparelho e ao trocar o nome de perfil. Hipótese (por
     ser whatsmeow): `Contact`, `PushName`, `Picture`. **Hoje `canonical_event`
     descarta `Contact` e `PushName`** (`"CONTACT"` não casa com `"CONTACTS"` nem
     na regra do singular) — se confirmado, é bug a corrigir na Fase 2.
  3. Salvar fixtures anonimizadas (telefone trocado por `5500000000000`) em
     `server/apps/webhook_ingress/tests/fixtures/contato_*.json` e
     `server/crates/infrastructure_evolution/tests/fixtures/contatos_lista.json`.
- **Arquivos:** só fixtures + anotação do contrato em
  `.context/plans/contact-sync/info_aux_contact-sync.md` (seção Evolution reescrita).
- **Dependências:** nenhuma. Bloqueia Fases 1–5.
- **Observabilidade & Auditoria:**
  - a) Sem código novo → sem span novo. A captura usa o `tracing::info!` já
    existente em `handle_webhook` (`provider`, `instance_id`, `event_type`).
  - b) **Sem evento de auditoria** (intencional: atividade de investigação).
  - c) Fixtures **anonimizadas** antes do commit; nunca colar `apikey` do Swagger
    ou de `docker inspect` em doc/issue.
- **Riscos:** rota de listagem inexistente → polling cai fora do escopo e a
  reconciliação passa a depender só de webhook (documentar e seguir).
- **Testes:** nenhum automatizado; o entregável é o contrato confirmado.

---

## Fase 1 — Banco de dados (migration aditiva)

- **Objetivo:** dar ao `oraculo_contato` os campos que a regra exige, criar a
  fila de divergências e a idempotência de eventos, e o opt-in por conexão.
- **Duração / complexidade:** 2–3 dias · BAIXA-MÉDIA (era 5–7: as tabelas-base já existem).
- **Arquivos:**
  - `server/crates/infrastructure_postgres/migrations/0051_sincronizacao_de_contatos.sql` (novo)
  - `server/crates/infrastructure_postgres/src/clientes/contatos.rs` (structs `Contato` + novos campos)
  - `server/crates/infrastructure_postgres/src/clientes/divergencias.rs` (novo)
  - `server/.sqlx/` (regenerado por `cargo sqlx prepare --workspace`)
- **Dependências:** Fase 0. Bloqueia Fase 2.

### Migration (esboço)

```sql
-- 0051 — Sincronização de contatos com o WhatsApp.
-- Aditiva e nullable onde possível: nenhuma linha existente muda de significado.

-- Origem do nome digitado no sistema. NULL (legado) é tratado como 'manual':
-- na dúvida, o sistema ganha.
ALTER TABLE oraculo_contato
    ADD COLUMN IF NOT EXISTS nome_contato_origem VARCHAR(10)
        CHECK (nome_contato_origem IN ('manual', 'whatsapp', 'ia')),
    ADD COLUMN IF NOT EXISTS nome_agenda_whatsapp VARCHAR(100),
    ADD COLUMN IF NOT EXISTS perfil_sincronizado_em TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS origem VARCHAR(10) NOT NULL DEFAULT 'conversa'
        CHECK (origem IN ('conversa', 'manual', 'agenda'));

ALTER TABLE whatsapp_instance
    ADD COLUMN IF NOT EXISTS sincronizar_agenda BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS agenda_sincronizada_em TIMESTAMPTZ;

-- Divergência: o WhatsApp diz uma coisa, o cadastro (de cliente) diz outra.
CREATE TABLE contato_divergencia (
    id             SERIAL PRIMARY KEY,
    tenant_id      UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contato_id     INT  NOT NULL REFERENCES oraculo_contato(id) ON DELETE CASCADE,
    instance_id    INT  REFERENCES whatsapp_instance(id) ON DELETE SET NULL,
    campo          VARCHAR(30) NOT NULL CHECK (campo IN ('nome_contato')),
    valor_sistema  VARCHAR(100),
    valor_whatsapp VARCHAR(100),
    detectada_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolvida_em   TIMESTAMPTZ,
    resolvida_por  INT REFERENCES auth_user(id) ON DELETE SET NULL,
    resolucao      VARCHAR(20) CHECK (resolucao IN ('manter_sistema', 'aceitar_whatsapp', 'ignorar'))
);
ALTER TABLE contato_divergencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE contato_divergencia FORCE  ROW LEVEL SECURITY;
CREATE POLICY contato_divergencia_tenant_isolation ON contato_divergencia
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
-- No máximo uma pendente por contato/campo: reentrega do webhook não duplica.
CREATE UNIQUE INDEX contato_divergencia_pendente
    ON contato_divergencia (tenant_id, contato_id, campo) WHERE resolvida_em IS NULL;
CREATE INDEX contato_divergencia_tenant_aberta
    ON contato_divergencia (tenant_id, detectada_em DESC) WHERE resolvida_em IS NULL;

-- Idempotência: o webhook é reentregue até 5x e pode chegar fora de ordem.
-- chave = sha256(instance_id || jid || campos normalizados) — sem PII em claro.
CREATE TABLE contato_evento_aplicado (
    tenant_id   UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    chave       CHAR(64) NOT NULL,
    aplicado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, chave)
);
ALTER TABLE contato_evento_aplicado ENABLE ROW LEVEL SECURITY;
ALTER TABLE contato_evento_aplicado FORCE  ROW LEVEL SECURITY;
CREATE POLICY contato_evento_aplicado_tenant_isolation ON contato_evento_aplicado
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX contato_evento_aplicado_expurgo ON contato_evento_aplicado (aplicado_em);
```

Notas:
- **Sem `contact_changes`**: o histórico de mudanças relevantes vai para o
  `audit_log` (que já tem `context JSONB` + índice GIN). Uma tabela de histórico
  paralela duplicaria a trilha.
- **Grants**: cobertos pelos `ALTER DEFAULT PRIVILEGES` da `0018` para
  `smartcore_app_rt` — não repetir `GRANT`.
- **Imutabilidade**: depois de aplicada em dev, a `0051` não pode ser editada nem
  em comentário (`migrations/README.md`). Correção = `0052`.
- **Ordenação fora de ordem**: resolvida por `perfil_sincronizado_em` — evento com
  timestamp anterior ao gravado é ignorado (não exige `SERIALIZABLE`).

### Repositório (padrão atual: tenant tx + `skip_all`, sem `err`)

```rust
/// Aplica um perfil vindo do WhatsApp a um contato, sob a regra pessoal × cliente.
/// Trava a linha (`FOR UPDATE`) — dois eventos do mesmo contato em paralelo
/// serializam aqui, sem precisar de isolamento SERIALIZABLE na transação toda.
#[tracing::instrument(skip_all, fields(instance_id = instance_id))]
pub async fn aplicar_perfil_do_whatsapp(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    instance_id: i32,
    perfil: &PerfilWhatsapp,          // telefone normalizado, nomes, visto_em
) -> Result<DesfechoSincronizacao, DbError> {
    ctx.exigir_qualquer(&["clientes:write", "sistema"])?;
    let atual = sqlx::query_as::<_, ContatoParaSync>(
        r#"SELECT c.id, c.nome_contato, c.nome_contato_origem, c.perfil_sincronizado_em,
                  EXISTS (SELECT 1 FROM oraculo_cliente_contatos cc
                           WHERE cc.contato_id = c.id) AS de_cliente
             FROM oraculo_contato c
            WHERE c.tenant_id = $1 AND c.telefone = $2 AND c.excluido_em IS NULL
            FOR UPDATE OF c"#,
    )
    .bind(ctx.tenant_id)
    .bind(&perfil.telefone)
    .fetch_optional(&mut **tx)
    .await?;
    // … regra pura em `decidir_sincronizacao(atual, perfil)` (testável sem banco)
    //   → Atualizado | DivergenciaAberta | Ignorado(Motivo) | Criado (só com opt-in)
}
```

A regra de decisão fica numa função **pura** (`decidir_sincronizacao`), no
mesmo estilo de `valores_para_o_contato` (P15) — o grosso dos testes não precisa
de banco.

### Observabilidade & Auditoria

- **a) Logs/traces:** span `aplicar_perfil_do_whatsapp` (nível do span INFO,
  `skip_all`, campo `instance_id`) aninhado no span de `run_in_tenant_transaction`,
  que já carrega `tenant_id`. **Sem `err`** no `#[instrument]`: `DbError` aqui
  inclui erros de domínio esperados (permissão, unicidade). Evento `debug!` com
  `desfecho` (`atualizado|divergencia|ignorado|criado`) e `motivo`. A migration
  em si é instrumentada pelo `inicializar_banco_dados` existente (falha = infra
  real → já `err`).
- **b) Auditoria:** a camada de repositório **não audita** (regra do projeto: quem
  audita é o handler do `data_postgres`). A migration não gera evento.
- **c) Sanitização:** nenhum campo de log recebe telefone/nome; `chave` de
  idempotência é hash (sem PII). `valor_sistema`/`valor_whatsapp` ficam só no
  banco (protegidos por RLS), nunca em span.
- **Riscos:** (1) migration aplicada por máquina local antes da imagem → crash
  loop (incidente 08–11/09) → aplicar só via deploy; (2) `CHECK` em
  `nome_contato_origem` quebrar caminhos que já gravam `nome_contato` (C4 manual,
  P15 IA) → atualizar esses UPDATEs na mesma PR para gravar `'manual'`/`'ia'`.
- **Testes:** `infrastructure_postgres/tests/integration_tests.rs` (rodam **só na
  CI**, sob `smartcore_app_rt`): isolamento RLS de `contato_divergencia` e
  `contato_evento_aplicado` (tenant A não vê B); índice parcial impede 2
  divergências abertas; unit da `decidir_sincronizacao` (tabela-verdade
  pessoal/cliente × origem do nome × evento antigo/novo). `cargo sqlx prepare
  --workspace --check` verde.

---

## Fase 2 — Backend Rust (ingestão, regra, polling, RPCs)

- **Objetivo:** aplicar a regra a todo evento de contato, reconciliar por polling
  quando o webhook falha, e expor os RPCs que a UI e o MCP usam.
- **Duração / complexidade:** 7–9 dias · ALTA.
- **Dependências:** Fase 1. Bloqueia Fases 3 e 4.

### 2.1 `webhook_ingress` — aceitar os eventos reais

- `server/apps/webhook_ingress/src/main.rs`: `canonical_event` passa a mapear os
  nomes confirmados na Fase 0 (provavelmente `Contact`, `PushName`) para
  `CONTACTS`; função `translate_go_contact` normaliza o payload Go
  (`JID`/`Action.FullName`/`NewPushName`) para `{ jid, nome_agenda, nome_perfil, visto_em }`.
- Continua devolvendo `202` e publicando `whatsapp.contact.updated` via
  `transport::bus::publicar_evento` (sem mudança de tópico).

### 2.2 `worker` — consumidor tipado e em lote

`server/apps/worker/src/main.rs::processar_contato_atualizado` troca o
`serde_json::Value` solto por struct tipada e **um RPC por lote** (hoje é um RPC
por contato — a sincronia da agenda inteira gera milhares de chamadas):

```rust
/// Contato como chega normalizado do `webhook_ingress`. `alias` cobre as duas
/// grafias do provedor sem `if let` em cascata.
#[derive(Debug, serde::Deserialize)]
struct ContatoDoProvedor {
    #[serde(alias = "remoteJid", alias = "id", alias = "JID")]
    jid: String,
    #[serde(default, alias = "pushName", alias = "NewPushName")]
    nome_perfil: Option<String>,
    #[serde(default, alias = "fullName", alias = "FullName")]
    nome_agenda: Option<String>,
}

/// Debug manual: nunca imprime JID nem nome (PII).
impl std::fmt::Debug for ContatoMascarado<'_> { /* …"***{últimos 4}" */ }
```

Lote de até 200 contatos → RPC `SincronizarContatosDoWhatsapp` no
`data_postgres` (timeout 10 s). Erro do RPC = `warn!` e `Ok(())` (o evento é
informativo; reentregar em loop não ajuda — mesmo raciocínio do
`processar_estado_conexao`).

### 2.3 `data_postgres` — handlers novos

`server/apps/data_postgres/src/main.rs` (+ `ports/cliente.rs`, `adapters/cliente.rs`):

| Rota (envelope) | Quem chama | Efeito |
|---|---|---|
| `SincronizarContatosDoWhatsapp` | worker (escopo sistema) | aplica lote; devolve `{atualizados, divergencias, ignorados, criados}` |
| `ListarDivergenciasDeContato` | runtime_api | lista pendentes do tenant |
| `ResolverDivergenciaDeContato` | runtime_api | `manter_sistema` / `aceitar_whatsapp` / `ignorar` |
| `DefinirSincronizacaoDaAgenda` | runtime_api | liga/desliga opt-in por conexão |
| `SolicitarSincronizacaoDaAgenda` | runtime_api | dispara reconciliação imediata (publica evento no bus) |
| `ListarInstanciasParaSincronizar` | worker/scheduler | conexões `connected` com opt-in ou com reconciliação vencida |

`AtualizarPerfilDoContato` (P8) vira *wrapper* de `SincronizarContatosDoWhatsapp`
com lote de 1, para não quebrar chamadores durante o deploy.

Erros: tudo parte de `error_core` — `DbError` já implementa `code()` e
`From<DbError> for AppError`; divergência já resolvida → `AppError::Conflict`;
contato inexistente → `ErrorCode::NotFound`. Nada de enum de erro novo sem
`From<…> for AppError` coerente com `code()`.

### 2.4 `infrastructure_messaging` + `infrastructure_evolution` — listagem (polling)

Porta nova (só se a Fase 0 confirmar a rota):

```rust
// infrastructure_messaging/src/lib.rs
#[async_trait]
pub trait ContactDirectory: Send + Sync {
    async fn listar_contatos(
        &self,
        instance_name: &str,
        token: &SecretString,          // secrecy 0.10: SecretBox<str>, Debug = [REDACTED]
    ) -> Result<Vec<ContatoDoDiretorio>, MessagingProviderError>;
}
```

```rust
// infrastructure_evolution/src/provider.rs — mesmo molde de get_profile_picture
#[tracing::instrument(skip_all, fields(instance = %instance_name), err)]
async fn listar_contatos(&self, instance_name: &str, token: &SecretString)
    -> Result<Vec<ContatoDoDiretorio>, MessagingProviderError>
{
    let resp = self.http
        .get(format!("{}/user/contacts", self.base_url))   // rota confirmada na Fase 0
        .header("apikey", token.expose_secret())            // evolution-go: apikey, não Bearer
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
    // 429 → ProviderApi{status:429} — o scheduler recua; corpo NUNCA vai ao log.
    self.json_do_provedor(resp).await                       // desembrulha {data: …}
}
```

`err` no `#[instrument]` é aceitável **aqui** porque todo erro desta função é
falha de infraestrutura (rede/HTTP/desserialização) — mas o `Display` de
`ProviderApi { body }` inclui o corpo da resposta, que pode ter JIDs: o
`json_do_provedor` deve truncar/omitir `body` em status ≠ 2xx antes de montar o
erro (ajuste pequeno, mesma PR).

`server/apps/data_whatsapp/src/main.rs`: rota `ListarContatosDaInstancia`
(decifra o token com `CipherManager` → `SecretString`, chama a porta, devolve
lista). Endpoint em Windows: `SMARTCORE_DATA_WHATSAPP_ENDPOINT=tcp://127.0.0.1:<porta>`
(UDS não roda em Windows).

### 2.5 `worker/scheduler.rs` — reconciliação

Tarefa nova `sincronizacao_agenda` no tick existente, sob
`tentar_lock(&mut conn, "scheduler:lock:sincronizacao_agenda", 300_000)`:
pede `ListarInstanciasParaSincronizar`, e para cada conexão (sequencial, 1 req/s
por instância — bem abaixo de qualquer limite do provedor) chama
`ListarContatosDaInstancia` e envia lotes de 200 ao `SincronizarContatosDoWhatsapp`.
Intervalo por env `SMARTCORE_SYNC_AGENDA_INTERVALO_S` (default 21600 = 6 h).
Também expurga `contato_evento_aplicado` com mais de 7 dias.
Polling é **reconciliação**, não fonte primária: o webhook continua sendo o caminho normal.

### Observabilidade & Auditoria

- **a) Logs/traces** (todos com `service`, `tenant_id`; `trace_id` vem do
  `traceparent` propagado pelo `TenantEnvelope`/`Envelope`; `env` é atributo de
  recurso do `observability::init_telemetry`):

  | Span / evento | Onde | Nível | Campos | `err`? |
  |---|---|---|---|---|
  | `contact.sync.webhook` | webhook_ingress (normalização) | INFO (1 por request, já existente) | `provider`, `instance_id`, `event_type` | não |
  | `contact.sync.consumir` | worker `processar_contato_atualizado` | INFO | `tenant_id`, `instance_id`, `qtd_contatos`, `causation_id` | não (best-effort) |
  | `warn!` falha de RPC | worker | WARN | `error_code` (de `AppError::code()`), `qtd_contatos` | — |
  | `contact.sync.aplicar` | data_postgres handler `SincronizarContatosDoWhatsapp` | INFO | `rpc`, `tenant_id`, `atualizados`, `divergencias`, `ignorados`, `criados` | não |
  | `contact.sync.listar_provedor` | evolution `listar_contatos` | INFO | `instance` | **sim** (só infra) |
  | `contact.sync.polling` | scheduler | INFO; WARN em 429/timeout | `instance_id`, `duracao_ms`, `qtd`, `error_code` | não |
  | `contact.divergencia.resolver` | handler `ResolverDivergenciaDeContato` | INFO | `tenant_id`, `divergencia_id`, `resolucao` | não |

  Erros de domínio sobem ao handler, que registra com severidade via
  `error_core::registrar` (política do projeto). Infra crates usam `tracing`
  direto — **nenhuma** dependência nova de `observability` em
  `infrastructure_*` (evita o ciclo com `infrastructure_postgres`).
- **b) Auditoria** (handler do `data_postgres`, via `AuditPort` →
  `publicar_evento_seguranca` → stream de segurança → `audit_log`; publicação
  assíncrona, falha de publicação = `error!` sem derrubar a operação):

  | `event` | Quando | `level` | `user_id` | Contexto mínimo |
  |---|---|---|---|---|
  | `contato.sincronizacao_aplicada` | 1 por lote **com mudança** (não por contato) | INFO | NULL (sistema) | `instance_id`, contagens, `origem: webhook|polling` |
  | `contato.divergencia_detectada` | divergência nova aberta | INFO | NULL | `contato_id`, `divergencia_id`, `campo` (sem valores) |
  | `contato.criado_da_agenda` | 1 por lote com criações (opt-in) | WARN | NULL | `instance_id`, `qtd`, ids |
  | `contato.divergencia_resolvida` | resolução humana | INFO | do `RequestContext` | `divergencia_id`, `contato_id`, `resolucao` |
  | `whatsapp_instance.sincronizacao_agenda_alterada` | opt-in ligado/desligado | WARN | do `RequestContext` | `instance_id`, `ativo` |
  | `contato.sincronizacao_solicitada` | disparo manual | INFO | do `RequestContext` | `instance_id` |

  `timestamp` = `NOW()` UTC no `audit_log`; `user_agent` vem do `Envelope`
  (`publicar_auditoria` já o usa; MCP é reconhecido pelo prefixo
  `SmartCoreAssistant-MCP`); `ip_address` = NULL (D2). Eventos de sistema usam
  `publish_security` com `level` explícito; ações de usuário, `publish`.
  Mudança de nome de contato **pessoal** não gera auditoria individual
  (intencional — mesma política do `webhook_ingress`: chegada de evento do
  provedor não é estado crítico; o resumo por lote cobre a trilha).
- **c) Sanitização:**
  - token da instância e `global_api_key`: `SecretString` do começo ao fim; só
    `expose_secret()` na montagem do header.
  - telefone/JID em log: **só** via `mascarar_telefone` (últimos 4 dígitos) — mover
    a função do `webhook_ingress` para `error_core` ou `contracts` (crate sem
    dependência de observability) para worker/data_postgres reutilizarem.
  - nomes de contato nunca em span/evento; no audit_log só ids.
  - `MessagingProviderError::ProviderApi.body` truncado (pode conter JIDs).
  - structs com PII implementam `Debug` manual mascarado (nada de `#[derive(Debug)]` cru).
- **Riscos + mitigação:**
  - Tempestade de eventos na 1ª sincronia (agenda de milhares) → lote de 200,
    idempotência por hash, resumo de auditoria por lote.
  - Evento fora de ordem → `perfil_sincronizado_em` + `FOR UPDATE`.
  - Instância desconectada no polling → filtrar `connection_state='connected'`; 401
    marca instância para reconexão (fluxo existente), não repete.
  - Deploy com worker novo e data_postgres antigo → `AtualizarPerfilDoContato`
    mantido como wrapper; worker novo cai para ele se a rota nova responder
    "método desconhecido".
- **Testes (CI):** unit `canonical_event` com fixtures da Fase 0 (incl. `Contact`
  e `PushName`); unit `translate_go_contact`; desserialização de
  `ContatoDoProvedor` com as grafias; teste de que `Debug` não vaza JID; handler
  com `MockAuditPort` (mockall) conferindo `event`/contexto **sem** PII;
  integração `SincronizarContatosDoWhatsapp` (pessoal atualiza, cliente diverge,
  reentrega idempotente, evento antigo ignorado, sem opt-in não cria);
  `listar_contatos` contra servidor HTTP fake (200/401/429/envelope).

---

## Fase 3 — Contratos gRPC (runtime_api / gRPC-Web) e MCP

- **Objetivo:** tornar divergências, opt-in e sincronização manual acessíveis ao
  Flutter (gRPC-Web) e a agentes (MCP).
- **Duração / complexidade:** 3–4 dias · MÉDIA.
- **Dependências:** Fase 2 (rotas no data_postgres). Pode correr em paralelo com a Fase 4
  depois que o `.proto` estiver mergeado.

### 3.1 `admin.proto` + `AdminService`

`server/crates/contracts/schemas/queries/admin.proto`:

```proto
rpc ListMyDivergenciasDeContato(ListMyDivergenciasRequest) returns (ListMyDivergenciasResponse);
rpc ResolverMyDivergenciaDeContato(ResolverMyDivergenciaRequest) returns (SimpleOkResponse);
rpc DefinirMySincronizacaoDaAgenda(DefinirMySincronizacaoRequest) returns (SimpleOkResponse);
rpc SolicitarMySincronizacaoDaAgenda(MyInstanciaIdRequest) returns (SimpleOkResponse);

message DivergenciaDeContato {
  int32 id = 1;
  int32 contato_id = 2;
  string campo = 3;
  string valor_sistema = 4;
  string valor_whatsapp = 5;
  int64 detectada_em = 6;
  // Últimos 4 dígitos — a tela não precisa do número inteiro para decidir.
  string telefone_final = 7;
}
// Sem map<>: o build.rs converte proto→flatbuffers e não aceita map.
```

`MyContato` ganha `nome_agenda_whatsapp = 9`, `origem = 10` (aditivo, números novos).

`server/apps/runtime_api/src/grpc_web.rs`: **um método tonic concreto por RPC** em
`impl AdminService for AdminFacade` (sem isso o Flutter Web não alcança a rota —
registrar só no roteador de envelope não basta). Guard
`exigir_autenticado_do_metadata`; `tenant_id` sempre das claims, nunca do request;
RBAC fino (`clientes:write` para resolver/opt-in) dentro do `data_postgres`.
Tonic 0.14 / prost 0.14 (versões do workspace).

Regenerar stubs: Dart (`clients/packages/api_client/lib/src/generated/queries/admin.pb*.dart`,
`protoc --dart_out=grpc:…`) e Python (`mcp_server/src/mcp_server/grpc/contracts/admin_pb2*.py`,
`uv run python -m grpc_tools.protoc …`).

### 3.2 `mcp_server` (Python ≥3.13, SDK `mcp` 2.1.1, `grpc.aio`)

`mcp_server/src/mcp_server/tools/cadastros.py` — mesmo molde de `update_contato`
(registro de escopo, `dry_run`, `executor.executar`, mensagem sem PII):

```python
registro.registrar(
    "resolver_divergencia_contato", Categoria.CONFIGURACAO, ("clientes:write",)
)

@mcp.tool(
    name="resolver_divergencia_contato",
    annotations=registro.exigir("resolver_divergencia_contato").anotacoes,
)
async def resolver_divergencia_contato(
    divergencia_id: Annotated[int, Field(gt=0, description="Id, de `list_divergencias_contato`.")],
    resolucao: Annotated[
        Literal["manter_sistema", "aceitar_whatsapp", "ignorar"],
        Field(description="manter_sistema = o cadastro fica como está."),
    ],
    dry_run: Annotated[bool, DRY_RUN] = False,
) -> str:
    """Decide uma divergência entre o nome do cadastro e o nome do WhatsApp."""
    tool = registro.exigir("resolver_divergencia_contato")
    if dry_run:
        executor.registrar_simulacao(tool)
        return resultado_dry_run(tool, "resolver a divergência do contato")
    await executor.executar(
        "resolver_divergencia_contato",
        "ResolverMyDivergenciaDeContato",
        pb.ResolverMyDivergenciaRequest(id=divergencia_id, resolucao=resolucao),
    )
    return f"Divergência {divergencia_id} resolvida ({resolucao})."
```

Tools: `list_divergencias_contato` (LEITURA, `clientes:read`),
`resolver_divergencia_contato`, `definir_sincronizacao_agenda` (CONFIGURACAO).
**Não** expor `SolicitarSincronizacao` ao MCP (custo no provedor; ação de tela).
O `RuntimeApiClient` já injeta `traceparent` (`opentelemetry.propagate.inject`) e o
header `x-smartcore-agente` — não criar interceptor novo.
Padrão RSOE: **não se aplica** aqui — RSOE é a arquitetura do `ia_engine`; o
`mcp_server` tem padrão próprio (`ErroDoBackend` traduz `grpc.StatusCode`; mensagem
sem nome/telefone). Nenhuma feature de `ia_engine` é necessária neste plano.

### Observabilidade & Auditoria

- **a) Logs/traces:** `runtime_api` — span por método `grpc_web.<Rpc>` (padrão
  existente, `skip_all`, `tenant_id` das claims), WARN quando o guard nega.
  `mcp_server` — span OTel da tool (`opentelemetry-instrumentation-grpc` já
  instrumenta o canal), log `loguru` INFO com nome da tool e `grant_id`, ERROR com
  `codigo` gRPC em falha; `traceparent` propagado ponta a ponta.
- **b) Auditoria:** gerada **no `data_postgres`** (Fase 2) — `contato.divergencia_resolvida`,
  `whatsapp_instance.sincronizacao_agenda_alterada`, `contato.sincronizacao_solicitada`.
  Chamadas via MCP saem com `user_agent = "SmartCoreAssistant-MCP/<tool> (grant <id>)"`,
  o que distingue agente de humano na trilha. A borda (`runtime_api`/MCP) **não**
  audita de novo (evita duplicidade).
- **c) Sanitização:** `DivergenciaDeContato.telefone_final` só com 4 dígitos; o
  access token do cliente MCP nunca cruza para o metadata (invariante já testado);
  `ErroDoBackend` não carrega nome/telefone; `valor_sistema`/`valor_whatsapp`
  trafegam na resposta (necessários à decisão) mas nunca em log.
- **Riscos:** esquecer o método em `grpc_web.rs` (bug recorrente — N3) → teste que
  lista os RPCs do `.proto` e confere implementação; `map<>` quebrando o build → usar
  `repeated`; stubs Dart/Python dessincronizados → regenerar na mesma PR.
- **Testes (CI):** unit do guard (tenant das claims); testes `pytest` das tools com
  `dry_run` e com stub fake (padrão `tests/` do `mcp_server`), incluindo
  "mensagem de erro não contém telefone"; `ruff` + `mypy` limpos.

---

## Fase 4 — UI Flutter (tenant_module)

- **Objetivo:** abas **Pessoais / Clientes / Divergências** na tela de contatos;
  opt-in por conexão na tela de conexões; botão "Sincronizar agora".
- **Duração / complexidade:** 6–7 dias · MÉDIA.
- **Dependências:** Fase 3.1 (stubs Dart). Paralela a 3.2.
- **Arquivos:**
  - `clients/modulos/tenant_module/lib/src/features/contatos/presentation/pages/contatos_page.dart` (abas)
  - `…/features/contatos/presentation/widgets/divergencia_tile.dart` (novo)
  - `…/features/contatos/presentation/cubit/divergencias_cubit.dart` (novo, `flutter_bloc` — ver `doc_dev/libs/flutter/flutter_bloc.md`)
  - `…/features/contatos/data/` (datasource via `api_client`, gRPC-Web)
  - tela de conexões do mesmo módulo: switch "Sincronizar agenda deste número" com
    diálogo explicando LGPD (só aparece quando D1 = opt-in)
- **Comportamento:** aba Divergências mostra "Sistema: X · WhatsApp: Y" e três
  ações; contador na aba; após resolver, recarrega a lista. "Pessoais"/"Clientes"
  filtram `ListMyContatos` pelo vínculo (filtro no servidor — campo novo opcional
  no request, não filtrar no cliente).

### Observabilidade & Auditoria

- **a) Logs/traces:** o cliente não emite spans próprios; erros de RPC são
  registrados pelo logger do app em WARN com o `código` gRPC — sem payload. A
  correlação acontece no servidor (span do `runtime_api`).
- **b) Auditoria:** **sem evento de auditoria no cliente** (intencional) — toda
  ação auditável é registrada no `data_postgres` quando o RPC chega.
- **c) Sanitização:** nenhuma impressão de contato em `debugPrint`/log; telefone
  exibido completo só onde a tela já exibe hoje (ficha), na aba de divergências só
  os 4 finais; nada de contato em cache persistente novo (o sync offline existente
  não é estendido nesta fase).
- **Riscos:** tela travar com milhares de contatos importados → paginação no servidor
  (`limite` já existe, teto 200); usuário ligar opt-in sem entender → diálogo explícito.
- **Testes (CI, nunca na máquina local):** widget tests das abas e do tile
  (estados vazio/erro/carregando), teste do cubit com datasource fake; `flutter analyze`.

---

## Fase 5 — Monitoramento (métricas, alertas, dashboard)

- **Objetivo:** tornar a sincronização visível sem ler log.
- **Duração / complexidade:** 3–4 dias · MÉDIA (era 5–7: logs/spans já entram em
  cada fase; aqui só métricas + dashboard + alertas).
- **Dependências:** Fase 2 (pontos de emissão). Pode começar junto com 3/4.
- **Arquivos:**
  - `server/crates/observability/src/usage_metrics.rs` — contadores no padrão
    `OnceLock` existente (OTel **0.24**: builder termina em `.init()`; não usar
    `.build()` das versões ≥0.27 até o bump do workspace):
    - `smartcore_contato_sync_total{tenant_id, desfecho}` (`atualizado|divergencia|ignorado|criado`)
    - `smartcore_contato_sync_divergencias_abertas{tenant_id}` (gauge observável, lido no tick do scheduler)
    - `smartcore_contato_sync_polling_duracao_ms` (histograma, sem `tenant_id` — cardinalidade)
    - `smartcore_contato_sync_provedor_erro_total{status}` (`401|429|5xx|rede`)
  - `server/crates/observability/src/usage_metrics.rs` é chamado do worker e do
    `data_postgres` (apps), **nunca** de `infrastructure_*`.
  - `docker/observability/provisioning/dashboards/json/contatos_sync.json` (novo)
  - `docker/observability/provisioning/alerting/rules.yml` (+ regras)
- **Alertas:** (1) `rate(provedor_erro_total{status="429"}[15m]) > 0` por 15 min;
  (2) polling sem execução há > 2× intervalo (lock preso / scheduler morto);
  (3) divergências abertas de um tenant crescendo > 100 em 24 h (indica regra errada).
- **Painel Grafana:** sincronizações por desfecho, divergências abertas por tenant,
  duração do polling, erros do provedor, eventos `contato.*` do `audit_log`
  (datasource Postgres, reaproveitando o padrão do `audit_log.json` existente).

### Observabilidade & Auditoria

- **a) Logs/traces:** sem span novo (consome os das Fases 1–3); alertas têm link
  para o Tempo/Loki filtrando `service` e `tenant_id`.
- **b) Auditoria:** **sem evento de auditoria** (intencional — monitoramento só lê).
  O painel lê `audit_log` com role de leitura da observabilidade, sem escrever.
- **c) Sanitização:** rótulos de métrica só `tenant_id` e enums de baixa
  cardinalidade — **nunca** telefone, JID ou nome; o painel de auditoria mostra
  `context` sem valores (já não há PII nele, por desenho da Fase 2).
- **Riscos:** cardinalidade explodir com `tenant_id` no histograma → fora; alerta
  ruidoso na 1ª sincronia → janela de 15 min + `for:`.
- **Testes:** validação do JSON do dashboard e do YAML de alertas no CI (lint de
  provisioning); smoke no dev após deploy.

---

## Ordem recomendada de execução

```
Fase 0 (1d) ──► Fase 1 (2–3d) ──► Fase 2 (7–9d) ──┬──► Fase 3.1 proto+gRPC-Web (2d) ──┬──► Fase 4 Flutter (6–7d)
                                                   │                                   └──► Fase 3.2 MCP (1–2d)
                                                   └──► Fase 5 métricas/dashboard (3–4d, em paralelo)
```

- Serial obrigatório: 0 → 1 → 2 → 3.1.
- Paralelo: 4 ∥ 3.2 ∥ 5 depois da 3.1 (5 já pode começar no fim da 2).
- Total: ~22–27 dias corridos em série; ~17–20 com o paralelismo.
- Decisões D1–D3 respondidas antes do início da Fase 2.
- Merge: validar o merge numa branch `ci/` temporária antes de ir para `dev`
  (push em `dev` deploya junto com a CI, sem gate).
- Testes: **só na CI** (a máquina local não roda suítes); localmente apenas
  `cargo fmt`/`clippy`, `ruff`/`mypy`, `flutter analyze`.

---

## Correções aplicadas (vs. plano inicial e vs. doc auxiliar)

| # | Plano/doc dizia | Corrigido para | Por quê | Fonte |
|---|---|---|---|---|
| 1 | Criar tabela `contacts` | Estender `oraculo_contato` | Tabela já existe com RLS, `UNIQUE` vivo e `excluido_em` | `migrations/0004`, `0045` |
| 2 | Tabela `contact_changes` | Histórico no `audit_log` (resumo por lote) | Evita trilha paralela; `audit_log` já tem `context` JSONB + GIN | `migrations/0010`, `0013` |
| 3 | `contact_conflicts` genérica | `contato_divergencia` com índice parcial de 1 pendente/contato/campo | Reentrega do webhook não pode duplicar | gotcha "fora de ordem" + retry 5× do provedor |
| 4 | "Webhooks" a criar | Ajustar `canonical_event` + consumidor existente | Ingestão e tópico `whatsapp.contact.updated` já existem (P8) | `webhook_ingress/src/main.rs`, `worker/src/main.rs` |
| 5 | Importar contatos do aparelho automaticamente | Opt-in por conexão, default desligado (D1) | P8 decidiu explicitamente não criar contato a partir da agenda (LGPD) | comentário em `contatos::atualizar_perfil_whatsapp` |
| 6 | Auth `Authorization: Bearer` | Header `apikey` (token da instância) | evolution-go ≠ Evolution API v2 | `infrastructure_evolution/src/provider.rs`; memória do projeto |
| 7 | `GET /contacts`, `PUT /contacts/{remoteJid}`, `POST /webhook` | Rotas a confirmar no Swagger (Fase 0); sem escrita no aparelho; webhook configurado no `connect` | Rotas da doc auxiliar são da Evolution v2 (Node) | `ref_evolution_go.md` (N9), Swagger `:8082` |
| 8 | Eventos `CONTACT`/`CONTACTS_UPDATE` | Nomes reais a capturar (provável `Contact`/`PushName`); hoje `Contact` é descartado | `canonical_event` não casa `CONTACT` singular | `webhook_ingress::canonical_event` |
| 9 | "API REST" no backend | RPCs no `data_postgres` + métodos gRPC-Web no `AdminService` | Não há REST; Flutter só alcança o que está em `grpc_web.rs` | memória "gRPC-Web exige exposição explícita" |
| 10 | Fase "MCP" = serviços gRPC | 3.1 contratos gRPC-Web + 3.2 tools no `mcp_server` | MCP no projeto é o `mcp_server` Python que fala com o `runtime_api` | `mcp_server/src/mcp_server/grpc/runtime_client.py` |
| 11 | httpx para chamar a Evolution | Rust `reqwest` em `infrastructure_evolution` (via `data_whatsapp`) | Nenhum Python fala com a Evolution; httpx sai do plano | `provider.rs` |
| 12 | Transações `SERIALIZABLE` | `run_in_tenant_transaction` + `SELECT … FOR UPDATE` + `perfil_sincronizado_em` | Serialização só por linha; evita retry de serialization failure em lote | `connection.rs::run_in_tenant_transaction` |
| 13 | Rate limit ~500/min | Polling a 1 req/s por instância, recuo em 429; limite real não documentado | O número da doc auxiliar não tem fonte da evolution-go | — |
| 14 | Libs Rust "não documentadas" (tokio, serde, sqlx, tracing, tonic) | Já documentadas em `doc_dev/libs/rust/` | Docs locais existem e estão atualizadas | `doc_dev/libs/rust/*.md` |
| 15 | sqlx 0.8 / tonic 0.12 | sqlx **0.9**, tonic/prost **0.14**, secrecy **0.10.3**, OTel **0.24** | Versões do workspace | `server/Cargo.toml` |
| 16 | Monitoring como fase isolada de 5–7 d | Logs/spans/auditoria dentro de cada fase; Fase 5 só métricas/dashboard/alertas (3–4 d) | Requisito inviolável de observabilidade por fase | pedido do usuário |
| 17 | `ip_address` em todo evento | `NULL` + `user_agent` preenchido; propagação de IP é item separado (D2) | `Envelope` não carrega IP; `publicar_auditoria` grava `None` | `data_postgres/src/main.rs::publicar_auditoria` |
| 18 | RSOE nas features Python | Não se aplica: não há feature de `ia_engine`; `mcp_server` segue padrão próprio | RSOE é a arquitetura do `ia_engine` | memória "ia_engine no padrão RSOE" |
| 19 | Um RPC por contato | Lote de 200 por RPC | Sincronia da agenda geraria milhares de chamadas | `worker::processar_contato_atualizado` |
| 20 | `mascarar_telefone` local | Função compartilhada numa crate base | Hoje só existe no `webhook_ingress` | `webhook_ingress/src/main.rs` |
| 21 | Body do erro do provedor logado | Truncar `ProviderApi.body` | O corpo pode conter JIDs (PII) | `infrastructure_messaging/src/errors.rs` |
| 22 | Prazo total ~30–39 d | ~22–27 d em série | Tabelas, ingestão, scheduler, métricas e telas-base já existem | inventário da §0 |

### Atualizações pendentes na doc auxiliar (`info_aux_contact-sync.md`)

- Seção Evolution: trocar Bearer → `apikey`; marcar rotas como "a confirmar no
  Swagger"; remover `PUT /contacts` e `POST /webhook` (são da v2 Node); trocar o
  breaking change "v2.2 → v2.3" (versões da v2 Node; a evolution-go é versionada
  pela tag da imagem, ex. 0.7.x).
- Libs Rust: apontar para `doc_dev/libs/rust/*.md` em vez de "a documentar"; corrigir
  versões (sqlx 0.9, tonic 0.14).
- httpx: remover (não há uso).
