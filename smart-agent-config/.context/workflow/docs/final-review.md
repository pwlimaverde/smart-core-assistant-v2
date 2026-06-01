# Final Review — infrastructure-postgres
Data: 2026-06-01 · Modelo: Opus · Escopo: server/ (main...HEAD)

## Veredito da auditoria de código: CONFORME
## Veredito do ciclo PREVC: INCOMPLETO (fase V — Validation — ainda não executada)

> A auditoria estática do código implementado (fase E) passou limpa e sem correções.
> Porém, conforme a pré-condição de completude do gate, o ciclo **não** é arquivado
> porque a fase **V (Validation)** não foi executada: migrations não aplicadas no
> banco real, `.sqlx/` não gerado, `cargo build/clippy` não validados e testes de
> integração pendentes (estes últimos serão feitos por outro agente, por decisão do
> dono do projeto). O plano **permanece ativo**.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
| --- | --- | --- |
| Workspace `server/Cargo.toml` (virtual, resolver 2) | ✅ | deps e versões idênticas ao plano |
| Crate `infrastructure_postgres/Cargo.toml` | ✅ | features SQLx mínimas corretas; dev-dep tokio macros/rt |
| `.gitignore` (ignora `target/`+`.env`, versiona `.sqlx/`) | ✅ | comentário explícito sobre versionar `.sqlx/` |
| `.env.example` + `rust-toolchain.toml` (stable) | ✅ | nota de porta do túnel 5432 presente |
| Migration 0001 (extensões + `auth_user` global s/ RLS) | ✅ | nota de infra da role `smartcore_app NOBYPASSRLS` como comentário |
| Migration 0002 (tenants: tenant/config/user/invite) | ✅ | RLS de `tenants_tenant` por `id`; demais por `tenant_id` |
| Migration 0003 (plan GLOBAL, subscription, paymentrecord) | ✅ | `plan` sem RLS; `plan_id` ON DELETE RESTRICT |
| Migration 0004 (contato/cliente/M2M) | ✅ | `UNIQUE (tenant_id, telefone)` total; cnpj/cpf UNIQUE parcial |
| Migration 0005 (operacional, ordem FK correta) | ✅ | dep→fluxo→etapa→atendente→app_instance |
| Migration 0006 (atendimentos + atu_*) | ✅ | self-FK em mensagem; todas UNIQUE totais p/ ON CONFLICT |
| Migration 0007 (treinamento RAG, HNSW vector_cosine_ops) | ✅ | `vector(1536)`; índices HNSW + B-tree compostos |
| Migration 0008 (evolution sync) | ✅ | UNIQUE (tenant_id, instance_id, jid) p/ upsert |
| Migration 0009 (coresettings GLOBAL + seed) | ✅ | seed de fallback com ON CONFLICT (key) DO NOTHING |
| `errors.rs` (DbError + from_sqlx_unique 23505) | ✅ | extra útil: helper de UniqueViolation |
| `connection.rs` (set_config(...,true) + migrate + criar_pool) | ✅ | bind `tenant_id.to_string()`; nunca `SET LOCAL = $1` |
| `security.rs` (RequestContext) | ✅ | has_flow_permission estende com tenant:admin/kanban:admin |
| `crypto.rs` (AES-256-GCM, base64 0.22 Engine, Debug REDACTED) | ✅ | formato JSONB {ciphertext,nonce,tag} idêntico ao 08 |
| `config_cache.rs` (DashMap<Uuid,Arc<RuntimeConfig>>) | ✅ | guard solto antes do await (sem deadlock); SecretString |
| `tenants/{tenants,plans,config,settings}.rs` | ✅ | cascata Tenant>CoreSettings; api_keys JSONB NOT NULL |
| `clientes/{contatos,clientes}.rs` | ✅ | ON CONFLICT (tenant_id,telefone); M2M ON CONFLICT DO NOTHING |
| `operacional/{departamentos,atendentes,fluxos,app_instances}.rs` | ✅ | round-robin com COUNT(*)::int em WHERE; $N::int IS NULL OR |
| `atendimentos/{atendimentos,mensagens,movimentos,campos,etiquetas}.rs` | ✅/➕ | `etiquetas.rs` (Etiqueta+Nota) consolida o que o plano citava como arquivos separados |
| `treinamento/{treinamentos,documentos,query_compose}.rs` | ✅ | busca vetorial `<=>` + `"distancia!"`; to_embedding_text |
| `integracoes/{evolution,whitelist}.rs` | ✅ | esta_na_lista COUNT(*)→Option<i64> unwrap_or(0) |
| `lib.rs` + mods de domínio | ✅ | re-exports de conveniência completos |
| AppInstance × EvolutionInstance coexistem | ✅ | tabelas distintas (0005 e 0008), não consolidadas |

## 2. Correções Aplicadas

Nenhuma. A auditoria não identificou divergência corrigível. Todos os pontos de atenção
do briefing foram verificados individualmente (ON CONFLICT vs UNIQUE total/parcial,
nullability→Option, `"distancia!"`, COUNT(*)→Option<i64>, binds do Vector com `as _`,
`set_config` em vez de `SET LOCAL = $1`).

## 3. Decisões Autônomas (revisar depois)

Nenhuma edição autônoma. Observações não-bloqueantes:
- `TenantConfigRow`/`CoreSettingRow` derivam `sqlx::FromRow` mas são consumidos por
  `query_as!` (que não usa FromRow). Inócuo; mantido para estilo uniforme.
- `has_flow_permission` concede acesso também a `tenant:admin` (além de `kanban:admin`) —
  coerente com "tenant:admin implica todos os escopos".
- Alias `at` para `oraculo_atendimento` no round-robin: `AT` é palavra não-reservada; válido.

## 4. Revalidação
- Auditoria estática migration↔struct↔query: ✅ (nomes de coluna, tipos SQL→Rust,
  nullability→Option, ordem posicional em query_as!, placeholders, RETURNING, RLS
  fail-closed, escopo de tenant, has_permission, base64 Engine, SecretString, FKs/ON DELETE).
- cargo build/clippy/sqlx prepare: **N/A** (sem banco — fase V por outro agente).

## 5. Pendências (fase V e operacional)

Riscos que só `cargo sqlx prepare`/clippy com banco real confirmam — foco da fase V:
1. **Gerar o `.sqlx/`** (`cargo sqlx prepare` com túnel aberto) e versioná-lo; sem isso o
   build offline no CI falha.
2. **Nullability do `<=>`**: confirmar `AS "distancia!"` como `f64` non-null em
   `documentos.rs` e `query_compose.rs`.
3. **Cast do Vector (`as _`)** resolvendo `vector(1536)` nas macros (INSERT + busca).
4. **`EXTRACT(EPOCH ...)::int`** em `movimentos.rs` → `Option<i32>` no RETURNING.
5. **Round-robin**: `COUNT(*)::int` no WHERE + alias `at` pelo analyzer do SQLx.
6. **RLS real**: cross-tenant (A não vê B), fail-closed sem `set_config`, role
   `smartcore_app` `NOBYPASSRLS` (provisionada pela infra, não pela migration).
7. **Round-trip do `CipherManager`** e **cache fallback** (Tenant>CoreSettings) — testes
   de integração (Test Writer).
8. **`clippy -D warnings` / `fmt --check`**: possíveis lints menores só visíveis com a toolchain.

Operacional (não-bloqueante): alinhar a porta do `server/.env` ao túnel efetivamente
aberto (o `.env.example` usa 5432) antes de `migrate`/`prepare`.
