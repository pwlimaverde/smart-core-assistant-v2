# Plano Completo — Fase N3: Painel do Tenant (convites, usuários e permissões)

> **Reestruturado em 2026-07-06** a partir de `doc_dev/planejamento/18-fase-N3-painel-do-tenant.md`,
> validado contra a central de libs Flutter (todas ✅, verificadas no ciclo mvp-telas).
> **Canônico:** `.context/plans/n3-painel-do-tenant.md` · **Docs auxiliares:** [info_aux](./info_aux_n3-painel-do-tenant.md)
> **Objetivo:** autonomia do **admin de tenant** (persona distinta do superusuário) — telas de
> convite, gestão de usuários e **`flow_permissions`** (a UI do RBAC fino já pronto no backend)
> + configuração do tenant.
> **Decisão travada (memória `convites-tenant-nao-e-painel-superuser`):** convites/gestão de
> usuários são fluxo do admin de tenant — **não** entram no `admin_module`/`AdminFacade`.

## Correções aplicadas (reestruturação)

| # | O quê | Por quê | Fonte |
|---|---|---|---|
| 1 | Nenhuma correção de API — todas as libs Flutter (flutter_bloc 9.1.1, go_router 17.3.0, get_it 9.2.1, grpc ^5.1.0, flutter_secure_storage 9.x) validadas na central em jun/2026 e sem breaking change pendente | Central USAR LOCAL | triagem 2026-07-06 |
| 2 | RBAC de UI concretizado com o mecanismo de `redirect`/guardas do go_router (rotas por shell condicionadas ao papel) — mesma versão já usada nos módulos existentes | O plano base pedia "guardas por papel" sem apontar o mecanismo | `doc_dev/libs/flutter/go_router.md` |
| 3 | Invalidação explícita do cache de `flow_permissions` no `UpdateTenantUser` promovida de "opcional" a **recomendada** — reusa o padrão Pub/Sub `core:settings:invalidate` já implementado (WS-7.2) | O custo é baixo (padrão pronto) e elimina a janela de 30s de UX confusa | código real do subscriber (mvp-telas) |

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Rotas de convite | `runtime_api/src/main.rs:161` (`CreateInvite`/`AcceptInvite`) | **JÁ expostas** (RBAC no `data_postgres`) | N3.1 consome |
| `flow_permissions` | `security.rs` + `GetUserFlowPermissions` + Envelope campo 14 | RBAC fino fim-a-fim pronto (RPC + cache TTL 30s) | N3.2 constrói a UI de gestão |
| `TenantUser` | `tenants/tenants.rs` (`flow_permissions JSONB`, papéis) | Persistência pronta; **falta RPC de escrita** | N3.2 adiciona `UpdateTenantUser` |
| Config do tenant | `TenantConfigCache` + Pub/Sub | Prontos (usados pelo superusuário) | N3.3 expõe visão do próprio tenant |
| Padrão de módulo | `admin_module`/`login_module` | data/domain/presentation + get_it/go_router/bloc | N3 replica |

> N3 é majoritariamente **Flutter** + alguns RPCs de escrita + separação de escopo de autorização.

## 1. Escopo

**Dentro:** N3.1 convites+aceite+register · N3.2 gestão de usuários/`flow_permissions` · N3.3 config do tenant · N3.4 empacotamento/RBAC de UI.
**Fora:** billing/uso visível ao tenant (→ N4); painel de treinamento RAG (→ pós-N2).

## 2. Etapas

### N3.1 — Convites e cadastro

1. **Tela de convites** (admin de tenant): gerar (papel + `flow_permissions` iniciais), listar pendentes/aceitos, revogar. Consome `CreateInvite` (exposto). **Fase P mapeia a cobertura** de `ListInvites`/`RevokeInvite` na borda; se faltar, adicionar handler forward no `runtime_api` sobre o repositório `tenants/` (padrão dos 18 forwards do admin).
2. **Aceite** (`AcceptInvite`, exposto): tela pública que recebe o token, coleta credenciais e cria `AuthUser` + vínculo `TenantUser`.
3. **Register** do primeiro admin (onboarding): consumir a rota correspondente; se não existir, sinalizar dependência de backend na fase P.

**Observabilidade & Auditoria:**
- *Logs/trace:* cliente propaga `traceparent` no gRPC-Web; spans nos handlers de convite.
- *Auditoria (server-side, doc 08 §4.2 — `TenantInvite` é evento crítico):* `tenant_user.convidado` (INFO), `tenant_user.aceito` (INFO), revogação (WARN) — com `user_id`/`ip`/`user_agent` (WS-5b). A UI não emite auditoria própria.
- *Sanitização:* token de convite só em `flutter_secure_storage`/trânsito; exibição mascarada; nunca em log.

**DoD:** admin gera convite; convidado aceita e loga; vínculo criado; eventos auditados com `user_agent`.

### N3.2 — Gestão de usuários e `flow_permissions`

1. **Lista de usuários do tenant** (papel, status, fluxos) — RPC de leitura **escopado ao tenant do JWT** (nunca cross-tenant; RLS como segunda barreira).
2. **`UpdateTenantUser { user_id, role, scopes, flow_permissions }`** (RPC de escrita novo sobre `tenants/`): edição de papel/escopos + multi-seleção dos fluxos Kanban. Ao gravar, **publicar invalidação** do cache curto de `flow_permissions` (correção #3 — padrão Pub/Sub pronto; senão, TTL 30s).
3. **Escopo de autorização:** só `tenant:admin` (ou equivalente) do próprio tenant gere usuários — reusar `exigir_qualquer`.

**Observabilidade & Auditoria:**
- *Logs/trace:* span no `UpdateTenantUser` com `tenant_id`/ator.
- *Auditoria:* `tenant_user.role_change` (WARN) e `tenant_user.flow_permissions_alteradas` (WARN) — mudança de cargo/permissão é evento crítico; metadados com `user_agent`/`ip`.
- *Sanitização:* só ids em log.

**DoD:** admin concede/revoga fluxos; o atendente passa a ver (ou deixa de ver) os cards daquele fluxo — **RBAC fino validado ponta-a-ponta pela UI**; eventos auditados.

### N3.3 — Configuração do tenant

- Tela na visão do próprio tenant para persona/prompts/providers. Api keys entram cifradas e são exibidas **mascaradas**. Reusa `TenantConfig` + invalidação Pub/Sub. Escopo restrito ao tenant do solicitante.

**Observabilidade & Auditoria:** `config.atualizada` com `user_agent`; troca de api key = `api_key.update` (crítico; descrição **sem** o segredo). Chave nunca em log/UI em claro.

**DoD:** alteração reflete nos consumidores **sem restart**; chaves mascaradas; eventos auditados.

### N3.4 — Empacotamento e RBAC de UI (decisão da fase P)

- **(A) — recomendada:** módulo do tenant dentro do `smart-core-admin` com **RBAC de UI** (guardas `redirect` do go_router por papel: superusuário vê `admin_module`; admin de tenant vê o módulo do tenant). Reusa bootstrap/design system/deploy `/v2/admin`.
- **(B):** app Flutter dedicado (novo target), reusando packages. Só se o produto exigir domínio/UX distintos.
- **Confirmar com o dono na fase P.**

**Observabilidade & Auditoria:** logs de navegação sem PII; **sem evento de auditoria** (a guarda de UI é conveniência; o backend já barra e audita por escopo — defesa em profundidade).

**DoD:** menus/rotas condicionados ao papel; atendente/admin de tenant não acessa telas de superusuário.

## 3. SOLID / Ports & Adapters (Flutter)

`TenantAdminDataSource` (abstrato, RemoteOnly) → adapter gRPC-Web → services → usecases → controllers `flutter_bloc` → pages. DIP: controllers dependem do service, não do stub. Componentes reutilizáveis no `design_system_module`.

## 4. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Rotas de convite incompletas na borda | Tela sem endpoint | Fase P mapeia cobertura; forward sobre repo existente se faltar |
| RBAC de UI vazando telas de superusuário | Escalonamento | Guarda de rota **+** backend barra por escopo (defesa em profundidade) |
| Mudança de permissão demorando a refletir | UX confusa | Invalidação explícita no update (correção #3); TTL 30s documentado como fallback |
| Cross-tenant na listagem | Isolamento | RPC escopado ao tenant do JWT; RLS como segunda barreira |

## 5. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N3** | Mapear cobertura de convite + decidir empacotamento (A/B) | Aprovar `TenantAdminDataSource` + RBAC de UI | Convites; gestão de usuários/fluxos; config tenant | `test-flutter.ps1` contra runtime real; RBAC fino validado pela UI | Eventos auditados; sem PII/segredo |
