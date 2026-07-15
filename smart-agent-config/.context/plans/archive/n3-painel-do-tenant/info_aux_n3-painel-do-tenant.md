# Documentação Auxiliar — Fase N3: Painel do Tenant (convites, usuários, permissões)

> Gerado em: 2026-07-06
> Plano canônico: `.context/plans/n3-painel-do-tenant.md`
> Plano completo: `.context/plans/n3-painel-do-tenant/plano_completo_n3-painel-do-tenant.md`
> Origem do plano-base: `doc_dev/planejamento/18-fase-N3-painel-do-tenant.md`

## Libs Flutter (todas USAR LOCAL — central `doc_dev/libs/flutter/`, verificadas durante o ciclo mvp-telas)

| Lib | Versão | Verificação | Uso na N3 |
|---|---|---|---|
| flutter_bloc | 9.1.1 (bloc ^9.2.1) | 2026-06-14 | controllers das telas de convite/usuários/config |
| go_router | 17.3.0 | 2026-06-14 | rotas do módulo do tenant + guardas por papel (RBAC de UI) |
| get_it | 9.2.1 | 2026-06-14 | injeção do `TenantAdminDataSource` (disposal LIFO estrito desde 9.0) |
| grpc (Dart) | ^5.1.0 | 2026-06-18 | gRPC-Web contra o `runtime_api` (mesmo adapter dos módulos existentes) |
| flutter_secure_storage | 9.x | 2026-06-14 | tokens (refresh/convite) — nunca em SharedPreferences/log |
| return_success_or_error | 2.0.0 | 2026-06-14 | contrato de retorno dos usecases |
| mocktail | 1.0.4 | 2026-05-31 | mocks nos testes de controller/usecase |
| melos | 7.8.2 | 2026-06-14 | orquestração dos packages do monorepo Flutter |

Notas da central relevantes:
- `go_router.md`: guardas via `redirect` com estado de auth/papel; rotas aninhadas por shell — usar para condicionar menu superusuário × admin de tenant.
- `flutter_bloc.md`: 9.x manteve API de `Cubit`/`BlocBuilder` — padrão dos módulos existentes se aplica sem mudança.

## Backend (referência — rotas já existentes ou a adicionar)

| Recurso | Estado | Referência |
|---|---|---|
| `CreateInvite` / `AcceptInvite` | **já expostos** na borda autenticada | `server/apps/runtime_api/src/main.rs:161` |
| `ListInvites` / `RevokeInvite` | **verificar cobertura** na fase P; se faltar, forward no `runtime_api` sobre repositório `tenants/` existente | padrão dos 18 forwards do admin |
| `GetUserFlowPermissions` | pronto (RBAC fino fim-a-fim, cache TTL 30s) | `data_postgres` + Envelope campo 14 |
| `UpdateTenantUser { role, scopes, flow_permissions }` | **a criar** (RPC de escrita) | repositório `tenants/tenants.rs` (`flow_permissions JSONB`) |
| `TenantConfig` + invalidação Pub/Sub | prontos (canal `core:settings:invalidate`) | usados pelo painel do superusuário |

## Serviços Externos
Nenhum novo — tudo via `runtime_api` (gRPC-Web same-origin em `/v2/admin`).

## Grupo C — Observabilidade e Auditoria (por etapa)

| Etapa | Logs/trace | Auditoria (server-side, com `user_agent`/`ip` — WS-5b) | Sanitização |
|---|---|---|---|
| N3.1 convites | cliente propaga `traceparent`; spans nos handlers | `tenant_user.convidado` (INFO), `tenant_user.aceito` (INFO), revogação (WARN) — eventos de `TenantInvite` são críticos (doc 08 §4.2) | token de convite nunca em log; exibição mascarada |
| N3.2 usuários/fluxos | spans no `UpdateTenantUser` | `tenant_user.role_change` (WARN), `tenant_user.flow_permissions_alteradas` (WARN) — mudança de cargo/permissão é evento crítico | ids apenas; sem nomes/telefones em log |
| N3.3 config do tenant | span + invalidação Pub/Sub | `config.atualizada` com `user_agent`; troca de api key = `api_key.update` (crítico, descrição **sem** o segredo) | api keys cifradas; UI exibe mascarado |
| N3.4 empacotamento/RBAC UI | logs de navegação sem PII | sem evento (guarda de UI; o backend já audita negações por escopo) | — |

## Notas Gerais
- **Decisão travada (memória `convites-tenant-nao-e-painel-superuser`):** convites/gestão de usuários são fluxo do **admin de tenant** — não entram no `admin_module`/`AdminFacade` do superusuário.
- Cache de `flow_permissions` tem TTL 30s — mudança reflete em ≤30s; avaliar invalidação explícita no update (mesmo padrão Pub/Sub do TenantConfig).
- Decisão de empacotamento (N3.4): recomendação **(A)** módulo do tenant dentro do `smart-core-admin` com RBAC de UI; confirmar com o dono na fase P.
