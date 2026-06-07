# 03 — Infraestrutura PostgreSQL (`infrastructure_postgres`)

> **Status:** ✅ **Concluído** — fundação implementada, testada e mergeada em `dev`.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês
> (verbos pt-br: `criar_*`, `buscar_*`, `inicializar_*`).
> **Última revisão:** 2026-06-07

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

### 6.1 Variáveis de ambiente

| Variável | Pool | Propósito |
|---|---|---|
| `DATABASE_URL` | tenant-scoped (RLS ativo) | Toda query de domínio com `run_in_tenant_transaction` |
| `DATABASE_ADMIN_URL` | admin (BYPASSRLS) | Migrations, login, registro, convites, superuser |

**Desenvolvimento local:** acessar via túnel SSH (`infra/tunnel.ps1`) → `localhost:5434`.
**Produção:** PostgreSQL Docker na VM Hostinger, porta `5434`, banco `smartcore_v2`.
**Dev no servidor:** mesmo PostgreSQL, banco `smartcore_v2_dev`, porta `5434`.

### 6.2 Docker Compose

```yaml
# docker/compose/data.yml — serviço postgres
postgres:
  image: pgvector/pgvector:pg16
  container_name: smartcore-v2-postgres
  ports:
    - "5434:5432"
  volumes:
    - smartcore_v2_postgres_data:/var/lib/postgresql/data
    - ./init-scripts:/docker-entrypoint-initdb.d
  environment:
    POSTGRES_DB: smartcore_v2
    POSTGRES_USER: smartcore_app
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

### 6.3 Usuários e privilégios no PostgreSQL

| Usuário | Papel | Acesso |
|---|---|---|
| `smartcore_app` | Role da aplicação | SELECT/INSERT/UPDATE/DELETE em tabelas de domínio; BYPASSRLS bloqueado |
| `smartcore_admin` | Role administrativo | BYPASSRLS; CREATE/DROP para migrations |

Criar manualmente após o primeiro `docker compose up`:
```sql
CREATE USER smartcore_admin WITH PASSWORD 'SENHA_ADMIN' BYPASSRLS;
GRANT ALL PRIVILEGES ON DATABASE smartcore_v2 TO smartcore_admin;
GRANT ALL PRIVILEGES ON DATABASE smartcore_v2_dev TO smartcore_admin;
```

### 6.4 Bootstrap do superusuário

O superusuário é criado via CLI (não via migration):
```powershell
# Windows (local)
.\infra\create-superuser.ps1

# Ou diretamente:
cargo run -p control_plane -- create-superuser --username admin --email admin@local --password <senha>
```
A CLI é um thin client RPC que envia ao `data_postgres` via TCP/UDS. O banco nunca é
acessado diretamente pela CLI.

## 7. Relação com as fases

| Fase | Dependência desta crate |
|---|---|
| F0/F1 ✅ | Fundação completa: conexão, RLS, migrations, auth, CRUD de todos os domínios |
| F-devops ⬜ | Migrations rodadas pelo `data_postgres` no boot de cada ambiente (dev/prod) |
| F6 ⬜ | `AuthUserRepository` (login, registro, tokens); `criar_admin_pool` para JWT bootstrap |
| F2-admin ⬜ | `TenantRepository`, `PlanRepository`, `SubscriptionRepository`, `PaymentRecordRepository` |
| F3 ⬜ | `ContaRepository`, `MensagemRepository` (ingestão de webhooks) |
| F4 ⬜ | `AtendimentoRepository`, `KanbanRepository`, `AtendenteRepository` |
| F5 ⬜ | `DocumentoRepository` (pgvector 1536, HNSW), `QueryComposeRepository` |

> O `runtime_api`, `worker`, `control_plane` e `messaging_gateway` **nunca** importam
> esta crate diretamente. Toda comunicação é via RPC ao `data_postgres`.

## 8. Comandos de referência

As migrations vivem em `crates/infrastructure_postgres/migrations/` (use `--source`).

```bash
# Rodar migrations (desenvolvimento — túnel SSH ativo).
# Em produção o data_postgres roda as migrations embutidas no boot.
cd server && DATABASE_URL="..." \
  sqlx migrate run --source crates/infrastructure_postgres/migrations

# Verificar status das migrations
cd server && DATABASE_URL="..." \
  sqlx migrate info --source crates/infrastructure_postgres/migrations

# Gerar cache SQLx offline (após adicionar/alterar query! / query_as!)
# O .sqlx/ é versionado e o CI valida com `cargo sqlx prepare --check`.
cd server && cargo sqlx prepare --workspace

# Testes de integração (requer PostgreSQL real via túnel)
cd server && cargo test -p infrastructure_postgres

# Reset do schema remoto (CUIDADO — destrói dados)
cd server && DATABASE_URL="..." sqlx database drop && DATABASE_URL="..." sqlx database create
```

---

*Fundação de persistência concluída. Retroalimentar apenas se surgir nova migration ou mudança de arquitetura na camada de dados. Última revisão: 2026-06-07.*
