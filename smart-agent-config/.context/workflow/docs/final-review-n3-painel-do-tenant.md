# Final Review — n3-painel-do-tenant
Data: 2026-07-15 · Modelo: Opus · Diff: dev..HEAD (3 commits: e4225d9, 7511a38, 99ada03)

## Rótulo: CORRIGIDO

## Resumo das correções
- Fechada uma falha de segurança real introduzida no ciclo: convite **revogado** ainda podia ser **aceito** (o `buscar_por_token` ignorava `revoked` e o accept nunca o checava) — a revogação era cosmética. Agora um convite revogado é tratado como inexistente no aceite.
- Preenchida a lacuna de auditoria do bootstrap do 1º admin em `CreateTenant`: a concessão inicial de `tenant:admin` passou a emitir evento de auditoria (`tenant_user_bootstrap_admin`), conforme doc 08 §4.2.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N3.1 — Convites (gerar/listar/revogar) + aceite + register | ⚠️→✅ | RPCs completos e expostos via gRPC-Web; UI de convites com token exibido **só** no diálogo pós-criação. Desvio crítico corrigido: aceite não honrava a revogação. |
| N3.2 — Gestão de usuários + `flow_permissions` | ✅ | `UpdateTenantUser`/`ListTenantUsers` criados do zero; RBAC `tenant:admin` no repositório (`ctx.exigir_qualquer`); filtro explícito `WHERE tenant_id = $1`. Invalidação de cache mantida passiva (TTL 30s) — decisão registrada, não é lacuna. |
| N3.3 — Configuração do tenant (keys mascaradas) | ✅ | `GetMyTenantConfig`/`UpdateMyTenantConfig` tenant-scoped com guard extra `exigir_escopo_tenant_admin`; `tenant_id` sempre de `claims`. Chaves vêm mascaradas (`••••••••`) e o update trata a máscara como "preservar" (sem sobrescrever a chave real). |
| N3.4 — Empacotamento (app dedicado) | ✅ | Decisão do dono: app `smart-core-tenant` criado; `OperacionalModule` removido do `smart-core-admin` (agora só superusuário/`AdminModule`). |
| ➕ Bootstrap do 1º TenantUser admin em `CreateTenant` | ➕ | Além do plano original; gap descoberto na execução. Auditoria agora presente (correção). |
| ➕ Exposição gRPC-Web dos 8 RPCs tenant-scoped | ➕ | Além do plano original; lacuna crítica descoberta na execução (nem CreateInvite/AcceptInvite eram alcançáveis pelo Flutter Web). Guard `exigir_autenticado_do_metadata` + RBAC fino no `data_postgres`. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `server/crates/infrastructure_postgres/src/tenants/tenants.rs:505` (`buscar_por_token`) | Convite revogado ainda era aceitável — accept checava `used`/`expires_at` mas não `revoked`; a feature de revogação do N3 era contornável (link continuava válido). | Query convertida para runtime `query_as::<_, TenantInvite>` com `AND revoked = FALSE` (revogado = inexistente). Sem quebra do cache offline do sqlx. |
| `server/apps/data_postgres/src/main.rs:964` (`handler_create_tenant`) | Bootstrap do 1º admin (concessão de `tenant:admin`) não publicava auditoria — evento crítico de `TenantUser` (doc 08 §4.2) ficava sem trilha. | `if let Err` trocado por `match`; no ramo `Ok` publica `tenant_user_bootstrap_admin` com contexto só de ids (`tenant_id`, `user_id`), sem segredos. |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| CreateInvite | ✅ `#[instrument]` | ✅ `tenant_invite_created` | ✅ | token só na resposta; ausente do log (span sem token). |
| AcceptInvite | ✅ | ✅ `tenant_invite_accepted` | ✅ | `buscar_por_token` com `skip_all` (token é segredo); contexto usa `username` (ator, não segredo). |
| RevokeInvite | ✅ | ✅ `tenant_invite_revoked` | ✅ | contexto só `invite_id`. |
| UpdateTenantUser | ✅ | ✅ `tenant_user_role_change` + `tenant_user_flow_permissions_alteradas` (WARN) | ✅ | contexto só ids/flags booleanas. |
| ListInvites / ListTenantUsers | ✅ | N/A (leitura) | ✅ | projeção `TenantInviteListItem` **sem** `token`. |
| CreateTenant (bootstrap 1º admin) | ✅ | ✅ `tenant_user_bootstrap_admin` (após correção) | ✅ | contexto só `tenant_id`/`user_id`. |
| Get/UpdateMyTenantConfig | ✅ | ✅ (via forward: `tenant_config_updated` + `tenant_api_key_changed`) | ✅ | api_keys mascaradas na leitura; máscara preservada no update (não sobrescreve chave real). |

## 3. Decisões Autônomas (revisar depois)
- **Revogado = inexistente no aceite:** filtro no SQL (`AND revoked = FALSE`) em vez de adicionar campo `revoked` ao struct `TenantInvite` + checagem explícita no handler, para não invalidar o cache offline do sqlx (`query_as!` macro) sem acesso ao banco para `cargo sqlx prepare`. Efeito colateral: o convidado recebe "Convite não encontrado" em vez de "Convite revogado" — aceitável (não vaza o estado do convite). Follow-up de baixo risco se quiserem a mensagem explícita.

## 4. Revalidação
- cargo fmt: ✅ (limpo)
- cargo clippy --all-targets --all-features -D warnings: ✅ (todas as crates)
- cargo check (infrastructure_postgres + data_postgres, reconfirmado pelo agente principal): ✅
- flutter analyze: ✅ (No issues found! — Flutter não foi tocado pelas correções)

## 5. Pendências (escopo extra ou fora do plano)
- Auditoria de `AcceptInvite`/`CreateInvite` inclui `username`/`email` do convidado no contexto — é identidade do ator, não segredo; mantido como está (comportamento pré-existente ao ciclo, dentro do doc 08).
- Nenhum teste automatizado foi adicionado (conforme regra do gate). O teste de integração de revogação existente não cobre o caminho `buscar_por_token` + revoked; um caso "aceitar após revogar → falha" seria uma boa regressão futura.
- Validação manual contra runtime real (subir infra + clicar na UI) não foi realizada neste ciclo — decisão do dono na fase V, aceitando a cobertura de testes automatizados (unit + integração) como evidência suficiente.
