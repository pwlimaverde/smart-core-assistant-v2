# Módulo Auth — Autenticação e Gestão de Usuários

## Schema `auth_user`

Tabela global, **sem RLS**. Toda query em `auth_user` usa pool direto (sem `set_config`).

```sql
CREATE TABLE auth_user (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(150) NOT NULL UNIQUE,
    email         VARCHAR(254) NOT NULL DEFAULT '',
    password_hash VARCHAR(255) NOT NULL DEFAULT '',  -- argon2id PHC string
    first_name    VARCHAR(150) NOT NULL DEFAULT '',
    last_name     VARCHAR(150) NOT NULL DEFAULT '',
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    is_staff      BOOLEAN NOT NULL DEFAULT FALSE,
    is_superuser  BOOLEAN NOT NULL DEFAULT FALSE,    -- acesso ao control_plane
    last_login    TIMESTAMPTZ,
    date_joined   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX auth_user_email_idx     ON auth_user (email) WHERE email != '';
CREATE        INDEX auth_user_superuser_idx ON auth_user (is_superuser) WHERE is_superuser = TRUE;
```

A tabela é criada já completa na migration inicial `0001_create_rls_function.sql` (não há migration de patch — o desenvolvimento partiu de um schema consolidado).

---

## Hierarquia de Usuários

```
auth_user
├── is_superuser = true  →  Superuser do Sistema
│       Acesso: control_plane, CoreSettings, todos os tenants, planos
│       JWT: tenant_id = null, scopes = ["system:admin"]
│       NÃO tem TenantUser associado.
│
└── is_superuser = false  →  Usuário de Tenant
    ├── tenants_tenant.owner_id  →  Tenant Owner
    │       Role automática: tenant:admin
    │       Criado junto com o tenant.
    │
    └── tenants_tenantuser.user_id  →  Funcionário
            Role: admin | manager | staff | viewer
            Criado via convite (tenants_tenantinvite).
```

---

## Relação com `oraculo_atendente`

`oraculo_atendente.usuario_id` é FK **real** para `auth_user(id)` com `ON DELETE SET NULL`.
Era FK lógica no legado por causa do isolamento multi-banco; no banco único atual a constraint é definida na criação da tabela em `0005_operacional.sql`.

---

## Hash de Senha — argon2id

Crate: `argon2 = { version = "0.5", features = ["std"] }`

```rust
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

// Hash
let salt = SaltString::generate(&mut OsRng);
let hash = Argon2::default().hash_password(plaintext.as_bytes(), &salt)?.to_string();

// Verify
let parsed = PasswordHash::new(stored_hash)?;
Argon2::default().verify_password(plaintext.as_bytes(), &parsed).is_ok()
```

O resultado é uma string PHC (`$argon2id$v=19$...`) armazenada em `password_hash`.

---

## JWT Claims

```json
{
  "sub":       "<user_id>",
  "tenant_id": "<uuid> | null",
  "scopes":    ["tenant:admin", "atendimentos:read", ...],
  "exp":       1234567890
}
```

- Superuser: `tenant_id = null`, `scopes = ["system:admin"]`.
- Usuário de tenant: `tenant_id` preenchido, `scopes` derivados do `role` em `tenants_tenantuser`.

---

## Fluxos de Autenticação

### Login
1. Receber `username`/`email` + senha.
2. `buscar_por_username` ou `buscar_por_email` via **admin pool** (sem RLS).
3. `verify_password(plaintext, user.password_hash)`.
4. Se ok: `atualizar_ultimo_login`, emitir JWT.

### Registro (Tenant Owner)
1. `hash_password(plaintext)`.
2. `criar(pool, username, email, hash, false)` em `auth_user`.
3. `criar_tenant(tx, ..., owner_id = user.id)`.
4. `criar_tenantuser(tx, ctx, user.id, "admin")`.

### Aceite de Convite
1. `buscar_por_token(admin_pool, token)` — **admin pool** necessário (cross-tenant, NOBYPASSRLS).
2. Validar `expires_at` e `used`.
3. Criar `auth_user` + `TenantUser` com role do convite.
4. `marcar_usado(admin_pool, invite_id)` — idem.

### Logout
Invalidar JWT no lado do servidor (Redis blocklist) — fora do escopo desta crate.

---

## Lookups Pré-Auth vs. Lookups Normais

| Operação | Pool | Motivo |
|---|---|---|
| `AuthUserRepository::*` | pool direto | `auth_user` sem RLS |
| `TenantUserRepository::buscar_por_user_id` | **admin_pool** | cross-tenant, NOBYPASSRLS bloqueia |
| `TenantInviteRepository::buscar_por_token` | **admin_pool** | idem |
| `TenantInviteRepository::marcar_usado` | **admin_pool** | idem |
| Demais operações tenant | `run_in_tenant_transaction` | RLS obrigatório |

O parâmetro `admin_pool: &PgPool` no trait sinaliza ao chamador que precisa de uma conexão com privilégios de bypass (role com `BYPASSRLS` ou owner da tabela).
