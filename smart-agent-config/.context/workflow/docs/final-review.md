# Final Review (fase V→C) — infrastructure-postgres
Data: 2026-06-01 · Modelo: Opus · Diff: main...HEAD (server/)

## Veredito: CORRIGIDO — ciclo COMPLETO (libera arquivamento)

Fases PREVC: P ✅ · R ✅ · E ✅ · V ✅ (migrations no banco real, build offline, testes
verdes, clippy/fmt limpos) · C (em andamento — este gate). A implementação está conforme o
plano aprovado; o auditor Opus aplicou 2 correções não-bloqueantes e revalidou.

> Substitui o relatório anterior (fase E), cujo veredito era CONFORME/INCOMPLETO por falta
> da fase V. Agora a fase V está cumprida.

## 1. Plano vs. Implementado (resumo)

| Item | Status |
| --- | --- |
| Workspace + crate + features SQLx | ✅ |
| `.sqlx/` de workspace versionado (97 queries, build offline) | ✅ |
| Migrations 0001–0009 com RLS (29 tabelas ENABLE+FORCE+POLICY fail-closed) | ✅ |
| Tabelas globais sem RLS (auth_user, tenants_plan, settings_manager_coresettings) | ✅ |
| `tenants_tenant` policy por `id`; demais por `tenant_id` | ✅ |
| Núcleo errors/connection(`set_config`)/security/crypto(AES-GCM, base64 Engine)/config_cache | ✅ |
| Repos por domínio (trait+impl, `tenant_id` explícito, `has_permission` nas escritas) | ✅ |
| Busca vetorial pgvector (`<=>`, HNSW, `"distancia!"`, `as _`) | ✅ |
| Correção fase V: `config.rs` lê TenantConfig sob tx com `set_config` | ✅ |
| Correção fase V: `atualizar_status` cast `$1::text` | ✅ |
| Separação admin/runtime (role `app_runtime` NOBYPASSRLS) | ✅ |
| Testes CRUD + RLS isolation por domínio + e2e cascade | ✅ / ➕ isolation de atendimentos |

## 2. Correções aplicadas pelo auditor (fase C)

| Arquivo | Problema | Correção |
| --- | --- | --- |
| `src/tenants/tenants.rs` | `buscar_por_user_id`/`buscar_por_token`/`marcar_usado` rodam no `&PgPool` sem `app.current_tenant`; sob NOBYPASSRLS retornam vazio/no-op silencioso. São lookups **intencionalmente cross-tenant** (bootstrap de auth — o tenant ainda não é conhecido). | Doc-comments explícitos avisando que o consumidor (middleware JWT, fase futura) DEVE executá-los por caminho com bypass legítimo (conexão admin dedicada ou função `SECURITY DEFINER`). Sem introduzir role/policy nova (fora de escopo). |
| `tests/atendimentos/mod.rs` | Faltava teste de isolamento RLS no maior domínio (os demais tinham). | Adicionado `test_atendimentos_rls_isolation` (Tenant B não vê atendimento de A). |

## 3. Revalidação
- cargo build (offline, `.sqlx`): ✅
- cargo clippy --all-targets -D warnings: ✅
- cargo fmt --check: ✅
- cargo test (banco real, túnel 5434): ✅ 7 unit + 20 integração, 0 falhas

## 4. Pendências / Recomendações futuras (não bloqueiam o arquivamento)
1. **Auth/JWT (fase futura):** implementar o bypass legítimo dos 3 lookups cross-tenant
   pré-auth (conexão admin restrita ou `SECURITY DEFINER` com `search_path` fixo). Hoje
   documentados no código; retornam vazio sob a role de runtime.
2. **`audit_log`:** migração dedicada permanece fora de escopo (08 §4.2), conforme plano.
3. **Teste fail-closed explícito** ("sem `set_config` → 0 linhas") como caso isolado — hoje
   comprovado indiretamente pelos isolamentos cross-tenant.
4. Provisionamento da role `app_runtime` deve ser portado para script de infra/IaC
   (hoje criada manualmente no banco do Hostinger; senha em `server/.env` git-ignored).
