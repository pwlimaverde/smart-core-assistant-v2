# Fase N3 — Painel do Tenant (convites, usuários e permissões)

> **Status:** Plano de execução — criado em **2026-07-06**. Terceira fase do backlog
> pós-MVP (N1–N5) — ver [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** dar autonomia ao **admin de tenant** — persona distinta do
> superusuário — com telas de **convite**, **gestão de usuários** e **`flow_permissions`**
> (a UI que alimenta o RBAC fino já implementado no backend), além da configuração
> do tenant (persona/prompts/providers).
> **Decisão travada (memória `convites-tenant-nao-e-painel-superuser`):** convites e
> gestão de usuários **são fluxo do admin de tenant**, não pertencem ao
> `admin_module`/`AdminFacade` do superusuário.
> **Regra inegociável:** observabilidade transversal (auditoria server-side dos
> eventos críticos com `user_agent`; UI sem PII em log; tokens só em secure storage).

---

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Rotas de convite | `runtime_api/src/main.rs:161` (`CreateInvite`/`AcceptInvite`) | **JÁ expostas** na borda autenticada (RBAC fino aplicado no `data_postgres`). | N3.1 **consome** — não cria backend de convite. |
| `flow_permissions` | `security.rs` + `GetUserFlowPermissions` (data_postgres) + Envelope campo 14 | RBAC fino **fim-a-fim pronto**; resolvido por RPC + cache TTL 30s. | N3.2 constrói a **UI de gestão** que grava o vetor no `TenantUser`. |
| `TenantUser` | `tenants/tenants.rs` (`flow_permissions JSONB`, papéis) | Persistência pronta; falta RPC de escrita de papel/permissões pelo admin de tenant. | N3.2 adiciona/consome RPC de update de `TenantUser`. |
| Config do tenant | `TenantConfigCache` + invalidação Pub/Sub | Leitura/escrita e invalidação prontas (usadas pelo superusuário). | N3.3 expõe a **visão do próprio tenant** (sem sair do escopo do tenant). |
| Padrão de módulo Flutter | `admin_module`/`login_module` | data/domain/presentation + `get_it` + `go_router` + `flutter_bloc`. | N3 **replica** o padrão num módulo do tenant. |

> **Conclusão:** o backend de convite/RBAC fino **já existe**; N3 é majoritariamente
> **Flutter** (telas) + alguns RPCs de escrita de `TenantUser` e a separação de
> **escopo de autorização** (admin de tenant ≠ superusuário).

---

## 1. Escopo

### Dentro do escopo
- **N3.1** Telas de **convite** (gerar/listar/revogar) + **aceite de convite** + **Register**.
- **N3.2** Gestão de usuários do tenant: papéis, escopos e **`flow_permissions`** (UI do RBAC fino).
- **N3.3** Tela de **configuração do tenant** (persona/prompts/providers) na visão do próprio tenant.
- **N3.4** Decisão de empacotamento: módulo novo no `smart-core-admin` com **RBAC de UI** vs app dedicado.

### Fora do escopo
- Billing/quota visível ao tenant → N4 (uso/cobrança).
- Painel de treinamento/ingestão de documentos (RAG) → backlog posterior à N2.

---

## 2. Contrato de observabilidade (DoD transversal)

- **Telemetria:** o cliente propaga `traceparent` nas chamadas gRPC-Web; logs de UI **sem PII**.
- **Auditoria (server-side):** o `runtime_api`/`data_postgres` auditam
  `tenant_user.convidado`, `tenant_user.aceito`, `tenant_user.role_change` (WARN),
  `tenant_user.flow_permissions_alteradas` — todos com `user_agent`/`ip` (WS-5b).
  A UI **não** emite auditoria própria.
- **Sanitização:** token de convite e refresh só em `flutter_secure_storage`; nunca
  em log; convites exibidos sem expor segredo em claro além do necessário para o aceite.

---

## 3. N3.1 — Convites e cadastro

**Tarefas**
1. **Tela de convites** (admin de tenant): gerar convite (papel + `flow_permissions`
   iniciais), listar pendentes/aceitos, revogar. Consome `CreateInvite` (já exposto)
   + novo `ListInvites`/`RevokeInvite` se ainda não existirem (verificar cobertura na
   borda; se faltar, adicionar handler forward no `runtime_api` sobre repositório
   `tenants/` existente).
2. **Fluxo de aceite** (`AcceptInvite`, já exposto): tela pública que recebe o token,
   coleta credenciais e cria o `AuthUser` + vínculo `TenantUser`.
3. **Register** do primeiro admin do tenant (se aplicável ao onboarding) — consumir a
   rota correspondente; se não existir, sinalizar dependência de backend.

**DoD:** admin de tenant gera convite; convidado aceita e loga; vínculo `TenantUser`
criado; eventos `tenant_user.convidado`/`.aceito` auditados com `user_agent`.

---

## 4. N3.2 — Gestão de usuários e `flow_permissions`

**Tarefas**
1. **Lista de usuários do tenant** (papel, status, fluxos permitidos) — RPC de leitura
   escopado ao tenant do solicitante (nunca cross-tenant).
2. **Editar papel/escopos** e **`flow_permissions`** (multi-seleção dos fluxos Kanban do
   tenant) — RPC de escrita `UpdateTenantUser { user_id, role, scopes, flow_permissions }`
   sobre o repositório `tenants/`. Ao gravar, **publicar invalidação** do cache curto de
   `flow_permissions` (o runtime_api usa TTL 30s — a mudança reflete no próximo TTL ou
   via invalidação explícita se adicionada).
3. **Validação de escopo de autorização:** só quem tem `tenant:admin` (ou papel
   equivalente) do **próprio tenant** pode gerir usuários — reusar `exigir_qualquer`.

**DoD:** admin de tenant concede/revoga fluxos a um atendente; o atendente passa a
ver (ou deixa de ver) os cards daquele fluxo na fila/Kanban — **validando o RBAC fino
de ponta a ponta pela UI**; `tenant_user.role_change`/`.flow_permissions_alteradas`
auditados.

---

## 5. N3.3 — Configuração do tenant

**Tarefas**
- Tela na visão do **próprio tenant** para persona/prompts/providers (as api keys
  entram cifradas; exibidas **mascaradas**, nunca em log). Reusa `TenantConfig` +
  invalidação de cache (Pub/Sub) já prontos. Escopo restrito ao tenant do solicitante.

**DoD:** alterar a config reflete nos consumidores **sem restart** (invalidação já
implementada); chaves exibidas mascaradas; `config.atualizada` auditado com `user_agent`.

---

## 6. N3.4 — Empacotamento e RBAC de UI

**Decisão a travar (P):** duas opções —
- **(A) Módulo do tenant dentro do `smart-core-admin`**, com **RBAC de UI** (rotas/menus
  condicionados a papel: superusuário vê `admin_module`; admin de tenant vê o módulo do
  tenant). Reaproveita bootstrap/design system/deploy web `/v2/admin`.
- **(B) App Flutter dedicado do tenant** (novo target), reusando os packages
  (`api_client`, `design_system_module`, `login_module`).

**Recomendação:** **(A)** para o MVP do painel do tenant — menor custo, reusa o deploy
web e o design system; separar em app dedicado (B) só se o produto exigir domínios/UX
distintos. **Confirmar com o dono** na fase P.

**DoD:** navegação e menus condicionados ao papel; um atendente/admin de tenant **não**
acessa telas de superusuário (guarda de rota + backend já barra por escopo).

---

## 7. SOLID / Ports & Adapters (Flutter)

- Novo `TenantAdminDataSource` (abstrato, RemoteOnly) → adapter gRPC-Web → services de
  domínio → usecases → controllers `flutter_bloc` → pages. **DIP:** controllers dependem
  do service, não do stub. Componentes reutilizáveis no `design_system_module`.

---

## 8. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Rotas de convite incompletas (list/revoke) na borda | Tela sem endpoint | N3.1 mapeia cobertura primeiro; adicionar forward sobre repo existente se faltar |
| RBAC de UI vazando telas de superusuário | Escalonamento | Guarda de rota **+** backend já barra por escopo (defesa em profundidade) |
| Mudança de `flow_permissions` demora a refletir (cache 30s) | Confusão de UX | Documentar o TTL; opcional: invalidação explícita do cache no update |
| Cross-tenant na listagem de usuários | Falha de isolamento | RPC sempre escopado ao tenant do JWT; RLS como segunda barreira |

---

## 9. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N3** | Mapear cobertura de convite + decidir empacotamento (A/B) | Aprovar `TenantAdminDataSource` + RBAC de UI | Convites; gestão de usuários/fluxos; config tenant | `test-flutter.ps1` contra runtime real; RBAC fino validado pela UI | Eventos auditados; sem PII/segredo |

*Plano aterrado nas rotas de convite já expostas (`runtime_api/src/main.rs:161`), no
RBAC fino fim-a-fim (WS-5a) e na decisão de persona (memória). Pronto para `/plan-restructuring`.*
