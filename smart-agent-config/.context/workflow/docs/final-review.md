# Final Review — camada-abstracao-mensageria
Data: 2026-06-21 · Modelo: Opus · Diff: main...feature/camada-abstracao-mensageria

## Rótulo: CORRIGIDO

## Resumo das correções
- **DESVIO CRÍTICO corrigido**: `admin_pool` agora é mantido vivo em `AppState` do `data_postgres` e usado pelo handler `handler_admin_list_all_connected_instances` para bypassar a RLS na consulta cross-tenant. Sem isso, `bulk_disconnect` sempre retornava count=0.
- **Comentário corrigido**: bloco impreciso "vamos executar e ver se funciona" em `whatsapp.rs:admin_listar_todas_conectadas` substituído por explicação técnica do requisito de BYPASSRLS.
- Desvios menores (audit sem ip/user_agent; audit de bulk_disconnect apenas no control_plane): registrados como decisões autônomas — sem alteração de código.

---

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---------------|--------|------------|
| `infrastructure_messaging` (trait + tipos normalizados) | ✅ | MessagingProvider 11 métodos, ConnectionState, SecretString nas assinaturas. Sem runtime/I/O. |
| `infrastructure_evolution` (impl REST Evolution API) | ➕ | Conforme + melhoria: `send_text` também skipa `text` (PII) no `instrument`, além de `instance_token`. |
| `0008_whatsapp_sync.sql` (schema genérico, 3 tabelas) | ✅ | RLS+FORCE em todas as tabelas. UNIQUE(tenant_id,name). `provider` sem default. |
| `infrastructure_postgres/integracoes/whatsapp.rs` (repositório genérico) | ✅ | `evolution.rs` removido. Traits `WhatsappInstanceRepository` e `WhatsappContactRepository` implementadas. Bug de comentário corrigido. |
| `webhook_ingress` (axum 0.8 local, normaliza webhooks) | ✅ | axum 0.8 local (não no workspace). Rota `{provider}/{tenant_id}/{instance_id}`. `body` skipado. Retorna 202 ACCEPTED. |
| `data_whatsapp` (orquestrador RPC, 7 RPCs) | ⚠️ | Todos 7 RPCs implementados. Audit de bulk_disconnect no control_plane (não duplicado em data_whatsapp — ver §3). |
| `control_plane`: evolution.rs legado removido | ✅ | `src/evolution.rs` deletado. Novo handler `AdminBulkDisconnect` delega a data_whatsapp. |
| `control_plane`: endpoint admin bulk_disconnect | ⚠️ | Implementado como RPC (não HTTP endpoint axum como planejado). Funcional; ip/user_agent ausentes (ver §3). |
| `data_postgres`: handlers whatsapp registrados (7) | ✅ | Todos 7 handlers registrados. Admin_pool mantido vivo (bug crítico corrigido). |
| axum 0.8 SOMENTE em webhook_ingress (não no workspace) | ✅ | `runtime_api` permanece em 0.7.5. |
| Streams `events:stream` e `security:stream` reais | ✅ | `publicar_evento` e `publicar_evento_seguranca` via `transport::bus`. |
| docker/evolution stack isolada | ✅ | `docker/evolution/compose.yml` com postgres_evolution + evolution. |

---

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| `data_postgres/src/main.rs:25-35` | `AppState` sem campo para admin pool; consulta cross-tenant sempre bloqueada por RLS | Adicionado `admin_pool: Option<PgPool>` com doc-comment explicando o requisito de BYPASSRLS |
| `data_postgres/src/main.rs:53-60` | `admin_pool` fechado imediatamente após migrations (`admin_pool.close().await`) | Reescrito para `let admin_pool = if ... Some(ap) else None` — pool mantido vivo para runtime |
| `data_postgres/src/main.rs:92` | `AppState` não incluía `admin_pool` | Adicionado `admin_pool: admin_pool.clone()` no bloco de inicialização |
| `data_postgres/src/main.rs:461-463` | Closure do route `AdminListAllConnectedInstances` não passava admin_pool | Atualizada para `handler_admin_list_all_connected_instances(state.pool, state.admin_pool, env)` |
| `data_postgres/src/main.rs:3587-3613` | Handler usava `pool.begin()` direto sob RLS → 0 linhas | Assinatura recebe `admin_pool: Option<PgPool>`; usa `effective_pool`; `tracing::warn!` quando ausente |
| `infrastructure_postgres/src/integracoes/whatsapp.rs:303-306` | Comentário "vamos executar e ver se funciona" — impreciso e inadequado para produção | Substituído por explicação técnica do comportamento RLS e requisito de BYPASSRLS |

---

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---------------|-----------|-----------|-------------|------------|
| `MessagingProvider` (infrastructure_messaging) | ✅ N/A | N/A | ✅ | Crate sem runtime; SecretString em todas assinaturas |
| `EvolutionProvider` (infrastructure_evolution) | ✅ | N/A | ✅ | `#[instrument(err, skip(self, instance_token))]` em todos os métodos; body de erro truncado ≤ 200 chars; `text` também skipado em send_text |
| `webhook_ingress` (ingest de webhooks) | ✅ | N/A | ✅ | `body` em skip; apenas event_type + metadados logados; 202 ACCEPTED mesmo para eventos ignorados |
| `data_whatsapp:CreateWhatsappInstance` | ✅ | ✅ | ✅ | `whatsapp.instance.create` publicado em `security:stream` com user_id, instance_name, provider. Sem token. |
| `data_whatsapp:DeleteWhatsappInstance` | ✅ | ✅ | ✅ | `whatsapp.instance.delete` publicado em `security:stream` |
| `data_whatsapp:AdminBulkDisconnect` | ✅ | ⚠️ | ✅ | Audit publicado no `control_plane` (não data_whatsapp) — ver §3. user_id presente; ip/user_agent ausentes (RPC). |
| `AdminListAllConnectedInstances` (degradação) | ✅ | N/A | ✅ | Novo `tracing::warn!` torna degradação sem DATABASE_ADMIN_URL observável |
| `infrastructure_postgres/whatsapp.rs` (repositório) | ✅ | N/A | ✅ | `#[instrument(skip_all)]` em todos handlers; `api_key` não logado |

---

## 3. Decisões Autônomas (revisar depois)
- **Audit de bulk_disconnect**: evento `whatsapp.admin.bulk_disconnect` publicado APENAS no `control_plane`, não em `data_whatsapp`. Duplicar geraria evento dobrado. O `user_id` do `Envelope` está presente. Campos `ip_address`/`user_agent` ausentes pois a operação trafega por RPC (não HTTP endpoint). Se forem requisito futuro, propagar via campos do `Envelope`.
- **AdminBulkDisconnect como RPC (não HTTP)**: o plano previa `POST /api/v2/admin/whatsapp/disconnect-all` em axum, mas a implementação usa o padrão RPC do projeto. A operação funciona; o endpoint HTTP pode ser exposto via `runtime_api` futuramente se necessário.

---

## 4. Revalidação
- cargo check (`-p data_postgres -p infrastructure_postgres`, SQLX_OFFLINE=true): ✅ sem erros nem warnings

---

## 5. Pendências (escopo extra ou fora do plano)
- **Operacional**: confirmar que `DATABASE_ADMIN_URL` está configurada no ambiente de produção onde `data_postgres` roda. Sem ela, `AdminListAllConnectedInstances` recai no pool com RLS ativa → lista vazia → bulk_disconnect sem efeito (agora com `tracing::warn!` explícito). Esta é uma dependência de deploy, não de código.
- **Testes de integração** (V2 do plano): `.\infra\test-local.ps1` não foi executado neste ciclo (exige túnel SSH para Hostinger). A build compilou limpa; validação de integração real fica pendente para executar manualmente antes do merge.
