# 03 — Infraestrutura PostgreSQL (`infrastructure_postgres`)

> **Histórico.** Plano canonizado pela skill `plan-restructuring` para o dotcontext.
> A fonte da verdade é o plano canônico em
> `.context/plans/archive/infrastructure-postgres/` (`plano_completo` + `info_aux`).
> Mantido aqui como registro do estado da fundação de persistência.
>
> **Status:** ✅ **Concluído** (fundação implementada e validada).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês
> (verbos pt-br: `criar_*`, `buscar_*`, `inicializar_*`).

## 1. Objetivo

A crate `infrastructure_postgres` centraliza **todo** o acesso de persistência ao PostgreSQL de forma a servir como uma **biblioteca interna exclusiva** do aplicativo `apps/data_postgres`. Ela implementa o banco **único multi-tenant** com isolamento por **Row-Level Security (RLS)**, busca vetorial (pgvector 1536, cosseno), cache de configuração e criptografia de credenciais. Nenhuma outra crate de negócio consome o Postgres diretamente.

> Regra central de RLS: **toda query em tabela de tenant DEVE correr dentro de
> `run_in_tenant_transaction`** (que seta `app.current_tenant` via
> `SELECT set_config(...)`), ativando as policies RLS fail-closed baseadas no `RequestContext`.

---

## 1.1 O Serviço de Dados `data_postgres`

O aplicativo `apps/data_postgres` é o processo servidor que expõe as capacidades desta crate para o resto do monorepo através de dois planos:
- **Plano Síncrono (RPC direto)**: Servidor UDS expondo métodos via FlatBuffers (padrão) e gRPC (fallback) para atender leituras e escritas rápidas que exijam resposta imediata (ack).
- **Plano Assíncrono (Consumidor do Bus)**: Consome eventos do barramento Redis Streams para processar persistências do fluxo de mensagens de forma assíncrona.
- **Relay Outbox**: Escuta notificações `LISTEN/NOTIFY` do banco e repassa eventos de domínio no bus.

---

## 2. Escopo entregue

- **Conexão e migrations:** `criar_pool`, `inicializar_banco_dados`,
  `run_in_tenant_transaction`; `criar_admin_pool` (BYPASSRLS, só lookups
  pré-tenant — login/registro/convites).
- **RLS:** `security.rs` (`RequestContext`) + função RLS
  (`0001_create_rls_function.sql`); policies por tabela
  (`USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)`).
- **Criptografia:** `crypto.rs` (`CipherManager`, **AES-256-GCM**) cifra api keys
  de provedores e tokens de instância; chave-mestra via env.
- **Cache:** `config_cache.rs` (`TenantConfigCache` com `DashMap<Uuid,
  Arc<RuntimeConfig>>`) — substitui o modelo de pools por tenant da v1.
- **Auth (fundação):** `auth/` (`AuthUser`, `AuthUserRepository`, Argon2 em
  `password.rs` — `hash_password`/`verify_password`).
- **Repositórios por domínio:** `tenants/`, `clientes/`, `operacional/`,
  `atendimentos/`, `treinamento/`, `integracoes/`.
- **Erro único** `DbError` (via `thiserror`); sem `unwrap()/expect()` em produção.
- Testes de integração contra Postgres real (isolamento multi-tenant).

## 3. Migrations (`migrations/`)

| Migration | Módulo | Conteúdo |
|---|---|---|
| `0001_create_rls_function` | RLS | Extensões (`vector`, `uuid-ossp`) + função/contexto RLS |
| `0002_tenants` | Tenants | tenant raiz, `tenant_config` (IA/branding), usuários e convites |
| `0003_plans_subscriptions` | Billing | planos, assinaturas, limites do SaaS |
| `0004_clientes_contatos` | Clientes | clientes corporativos + contatos (números WhatsApp) |
| `0005_operacional` | Operacional | departamento → fluxo → etapa → atendente → app_instance |
| `0006_atendimentos` | Atendimentos | tickets, mensagens, campos dinâmicos, etiquetas, notas, movimentos |
| `0007_treinamento_rag` | IA/RAG | base vetorial (`vector(1536)`, HNSW cosseno) + intenções (`query_compose`) |
| `0008_evolution_sync` | Integrações | instâncias Evolution, contatos sincronizados, whitelist |
| `0009_settings_manager` | Settings | `CoreSettings` (config dinâmica global; substitui Remote Config) |
| `0010_audit_log` | Auditoria | tabela de logs de auditoria persistidos a partir do bus (consumidos do Redis Streams) |
| `0011_outbox` | Outbox | tabela transacional de outbox + `LISTEN/NOTIFY` para o relay de eventos de domínio no bus |

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade |
|---|---|
| `connection.rs` | pool, migrations, `run_in_tenant_transaction`, `criar_admin_pool` |
| `security.rs` | `RequestContext` + helpers de permissão (`has_permission`, `has_flow_permission`) |
| `crypto.rs` | `CipherManager` (AES-256-GCM) |
| `config_cache.rs` | `TenantConfigCache` / `RuntimeConfig` (DashMap) |
| `errors.rs` | `DbError` único |
| `auth/` | `users.rs`, `password.rs` (Argon2) |
| `tenants/` | `tenants.rs`, `config.rs`, `plans.rs`, `settings.rs` |
| `clientes/` | `clientes.rs`, `contatos.rs` |
| `operacional/` | `departamentos.rs`, `fluxos.rs`, `atendentes.rs`, `app_instances.rs` |
| `atendimentos/` | `atendimentos.rs`, `mensagens.rs`, `campos.rs`, `etiquetas.rs`, `movimentos.rs` |
| `treinamento/` | `documentos.rs`, `treinamentos.rs`, `query_compose.rs` |
| `integracoes/` | `evolution.rs`, `whitelist.rs` |
| `auditoria/` | `audit_log.rs` (persistência dos logs de auditoria consumidos do bus) |

## 5. Decisões-chave (resumo)

- **Banco único + RLS** (não banco-por-tenant da v1) — ver
  [00-planejamento-inicial.md §6](./00-planejamento-inicial.md).
- **`SET LOCAL ... = $1` não funciona** com bind; usar
  `SELECT set_config('app.current_tenant', $1, true)` (escopo de transação).
- **pgvector dimensão fixa 1536** + busca **sempre** com `tenant_id = $N`
  explícito (índice + isolamento).
- **DashMap** para cache de config (clonar `Arc`/`PgPool` antes de `.await`;
  nunca segurar `Ref` através de await).
- **SQLx offline** (`cargo sqlx prepare` → `.sqlx/` versionado;
  `SQLX_OFFLINE=true` no CI).

## 6. Configuração e ambiente

- **Variáveis:** `DATABASE_URL` (pool tenant-scoped) e `DATABASE_ADMIN_URL`
  (pool admin BYPASSRLS — só login/registro/convites). Em dev, via túnel SSH
  (`infra/tunnel.ps1` → `localhost:5434`).
- **Docker:** serviço `postgres` (`pgvector/pgvector:pg16`) em
  `docker/compose/data.yml` + `docker/init-scripts/01-extensions.sql`.

## 7. Relação com as fases
Cobre integralmente a persistência da **Fase 1** e de boa parte das F2-F5. No entanto, pós-refator, ela é consumida **exclusivamente** através de chamadas RPC IPC para o serviço `data_postgres` tipadas via `contracts`. O `runtime_api`, `worker` e `control_plane` conversam com o `data_postgres` em vez de carregar esta crate diretamente.

---

*Consolidação da fundação de persistência. A verdade técnica reside no código físico e nos schemas unificados de contratos.*
