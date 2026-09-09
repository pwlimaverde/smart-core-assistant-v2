# 09. Diretrizes de Controle de Acesso e Permissões (RBAC)

Este documento detalha a estratégia de **Controle de Acesso Baseado em Funções e Escopos (RBAC/Scopes)** do **Smart Core Assistant v2**, bem como o guia de implementação prática na camada de aplicação Rust (usando Axum e SQLx) para garantir que os dados sensíveis dos inquilinos nunca sejam violados.

---

## 1. Visão Geral da Arquitetura de Permissões

Para impedir violações e vazamentos de dados, o sistema adota o princípio de **Defesa em Profundidade**, distribuindo o controle de acesso em três barreiras sequenciais e independentes:

```
[Requisição HTTP]
      │
      ▼
1. CAMADA DE TRANSPORTE (Middleware Axum)
   - Valida a autenticidade do JWT.
   - Extrai as Claims assinadas do Token.
   - Carrega flow_permissions do cache Redis (TTL curto) para evitar JWTs grandes
     e garantir que revogações de acesso reflitam sem esperar expiração do token.
   - Monta e injeta o `RequestContext` como Extension.
      │
      ▼
2. CAMADA DE NEGÓCIO E PERSISTÊNCIA (Repositório Rust)
   - Valida logicamente se o `RequestContext` ativo possui os escopos requeridos.
   - Aborta a transação na primeira violação (Fail-Fast).
      │
      ▼
3. CAMADA DE ARMAZENAMENTO FÍSICO (PostgreSQL RLS)
   - Executa a query sob a sessão isolada com `SET LOCAL app.current_tenant`.
   - Filtra os resultados no motor do banco de dados, atuando como salvaguarda final.
```

---

## 2. O Transportador de Contexto: `RequestContext`

Toda chamada à camada de banco de dados e repositórios deve receber, obrigatoriamente, uma referência ao contexto de segurança da requisição ativa. Este contexto é representado pela struct `RequestContext` e encapsula a identidade do usuário logado e seus limites operacionais.

* **Localização:** `server/crates/infrastructure_postgres/src/security.rs`

```rust
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct RequestContext {
    /// Identificador único e verificado do Tenant ao qual a requisição pertence.
    pub tenant_id: Uuid,

    /// Identificador do usuário logado (referência a auth_user).
    pub user_id: i32,

    /// Lista de escopos de permissão concedidos ao usuário.
    /// Ex: ["clientes:read", "clientes:write", "operacional:admin"]
    pub user_scopes: Vec<String>,

    /// IDs de FluxoAtendimento (Kanban) que o atendente está autorizado a visualizar.
    /// Carregado do campo `flow_permissions` do TenantUser no middleware de autenticação
    /// a partir do cache Redis, garantindo que revogações reflitam sem aguardar
    /// expiração do JWT.
    pub flow_permissions: Vec<i32>,
}

impl RequestContext {
    /// Valida se o contexto atual possui um determinado escopo de permissão.
    pub fn has_permission(&self, permission: &str) -> bool {
        self.user_scopes.iter().any(|p| p == permission)
    }

    /// Valida se o usuário tem acesso a um fluxo específico do Kanban.
    /// Usuários com escopo "kanban:admin" têm acesso irrestrito a todos os fluxos.
    pub fn has_flow_permission(&self, flow_id: i32) -> bool {
        self.has_permission("kanban:admin") || self.flow_permissions.contains(&flow_id)
    }
}
```

---

## 3. Catálogo Canônico de Escopos

Os escopos seguem a convenção `recurso:acao`. A lista abaixo é a fonte de verdade para a emissão de tokens e validação nos repositórios:

| Escopo | Descrição |
|---|---|
| `kanban:admin` | Acesso irrestrito a todos os fluxos e colunas do Kanban |
| `clientes:read` | Visualizar contatos e clientes |
| `clientes:write` | Criar e editar contatos e clientes |
| `operacional:read` | Visualizar departamentos e atendentes |
| `operacional:admin` | Gerenciar departamentos, atendentes e instâncias |
| `atendimentos:read` | Visualizar atendimentos e mensagens |
| `atendimentos:write` | Criar e mover atendimentos no Kanban |
| `treinamento:read` | Visualizar base RAG do tenant |
| `treinamento:write` | Criar e editar treinamentos e documentos |
| `financeiro:read` | Visualizar assinaturas e lançamentos financeiros |
| `financeiro:write` | Registrar lançamentos financeiros |
| `configuracoes:read` | Visualizar configurações do tenant |
| `configuracoes:write` | Editar TenantConfig (prompts, LLM, API keys) |
| `tenant:admin` | Acesso administrativo total ao tenant (implica todos os escopos acima) |

### 3.1 Mapa rota → escopo da borda gRPC-Web (N13.3)

Até a fase N13, o catálogo acima estava **documentado e não aplicado**: a borda
exigia `tenant:admin` em todas as 40 rotas encaminhadas por `encaminhar_tenant`, e
os handlers operacionais escritos à mão exigiam apenas sessão válida. Na prática
só existiam dois papéis — admin e ninguém — e um `viewer` conseguia enviar mensagem
a cliente final.

A fonte de verdade do mapa é `server/apps/runtime_api/src/rbac.rs`. Ele é
**fail-closed**: rota não declarada é negada, e o teste
`toda_rota_de_encaminhar_tenant_tem_escopo_declarado` lê o próprio `grpc_web.rs` e
falha se uma rota nova entrar sem escopo.

`tenant:admin` e o coringa `*` do superusuário satisfazem qualquer linha e por isso
não aparecem na coluna.

| Rota | Escopo exigido |
|---|---|
| `ListFluxos`, `ListEtapasFluxo` | `atendimentos:read` |
| `CreateFluxo`, `UpdateFluxo`, `DesativarFluxo` | `kanban:admin` |
| `CreateEtapaFluxo`, `UpdateEtapaFluxo`, `DesativarEtapaFluxo`, `MoverEtapaFluxo` | `kanban:admin` |
| `ListDepartamentos`, `ListAtendentes` | `operacional:read` |
| `CreateDepartamento`, `UpdateDepartamento`, `DesativarDepartamento` | `operacional:admin` |
| `CreateAtendente`, `UpdateAtendente`, `DesativarAtendente` | `operacional:admin` |
| `ListWhatsappInstances`, `GetWhatsappInstanceStatus` | `operacional:read` |
| `CreateWhatsappInstance`, `ReconnectWhatsappInstance`, `DeleteWhatsappInstance` | `operacional:admin` |
| `ListTreinamentos`, `GetTreinamento`, `QueryCompose`, `ListIntents` | `treinamento:read` |
| `CreateTreinamento`, `FinalizarTreinamento`, `RemoverTreinamento` | `treinamento:write` |
| `CreateIntent`, `UpdateIntent`, `RemoveIntent` | `treinamento:write` |
| `GetDetalheAtendimento` | `atendimentos:read` |
| `CreateEtiqueta`, `AlternarEtiqueta`, `CreateNota` | `atendimentos:write` |
| `ListContatos` | `clientes:read` |
| `GetPainelTenant` | `atendimentos:read` |
| `UpdateTenantConfig` | `configuracoes:write` |
| `GetOnboardingProgress` | `configuracoes:read` |
| `SetOnboardingProgress` | `configuracoes:write` |

Handlers operacionais (fora do `encaminhar_tenant`), que antes exigiam só sessão:

| Rota | Escopo exigido |
|---|---|
| `ListAtendimentos`, `GetThread`, `ListarMidiasAtendimento` | `atendimentos:read` |
| `MoveAtendimentoEtapa`, `SetAtendimentoStatus` | `atendimentos:write` |
| `SolicitarUploadMidia`, `EnviarMidiaAtendimento` | `atendimentos:write` |
| **`SendOutboundMessage`** | `atendimentos:write` |
| `TestarPergunta` | `treinamento:read` |
| `GetMyTenantConfig` | `configuracoes:read` |
| `UpdateMyTenantConfig` | `configuracoes:write` |
| `CreateInvite`, `ListInvites`, `RevokeInvite` | `tenant:admin` |
| `ListTenantUsers`, `UpdateTenantUser` | `tenant:admin` |
| `ListMcpGrants`, `RevokeMcpGrant` | *só sessão* — o recurso é do próprio usuário |

`SendOutboundMessage` está em negrito porque é a rota com o único efeito
irreversível do sistema (a mensagem chega ao telefone de um cliente real) e era a
única do grupo operacional que também saía com `flow_permissions` **vazio** no
envelope. As duas coisas foram corrigidas em N13.3.

### 3.2 Credenciais não-interativas (N13)

Além da sessão do painel, existe um segundo caminho de credencial: o **OAuth 2.1
do servidor MCP**, para agentes de IA externos. Ele não amplia o catálogo de
escopos nem cria escopos próprios — ele **projeta** os mesmos 14.

Três propriedades que o tornam seguro apesar de ser credencial de longa duação:

1. **Subconjunto por construção.** A tela de consentimento só oferece os escopos
   que o usuário logado possui. Não existe caminho de emissão em que se peça a
   mais — a garantia é estrutural, não uma validação que alguém pode esquecer de
   chamar.
2. **Reinterseção a cada emissão.** Os escopos do grant são reinterseccionados com
   os escopos atuais do usuário em todo access token. Rebaixar alguém no painel
   encolhe o agente dele na renovação seguinte, sem tocar no consentimento.
3. **Sem superusuário.** Uma conta com `is_superuser` não pode conectar agente
   (D4 da fase): um token vazado alcança no máximo um tenant.

O detalhamento está em `06_modulo_integracoes.md` §4.

---

> **Mapeamento de roles para escopos:** A role `admin` recebe `tenant:admin`. A role `manager` recebe todos os escopos de `read` e `write` exceto `financeiro:write` e `configuracoes:write`. A role `staff` recebe `clientes:read`, `atendimentos:read` e `atendimentos:write`. A role `viewer` recebe apenas os escopos `read`. Esta expansão acontece no `control_plane` no momento de emissão do JWT.

---

## 4. Implementação Prática: Middleware HTTP (Axum)

O middleware intercepta o cabeçalho `Authorization: Bearer <JWT>`, decodifica-o de forma segura e carrega o `RequestContext` — incluindo `flow_permissions` do Redis — injetando-o como extensão da requisição.

> **Importante:** O `tenant_id` **nunca** deve ser lido de parâmetros do corpo JSON ou query string. Ele deve ser obtido exclusivamente das Claims assinadas e verificadas do JWT.

> **Importante:** O segredo JWT (`JWT_SECRET`) deve ser carregado **uma única vez na inicialização** do servidor e injetado como estado da aplicação Axum (`State<AppState>`). Nunca chamar `std::env::var()` dentro do middleware a cada requisição — isso causa I/O desnecessário e impede rotação de segredo sem restart.

```rust
// server/apps/runtime_api/src/middleware/auth.rs
use axum::{
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};
use infrastructure_postgres::security::RequestContext;
use crate::state::AppState;

#[derive(serde::Deserialize)]
struct Claims {
    sub: String,          // user_id como string
    tenant_id: String,    // tenant UUID como string
    scopes: Vec<String>,  // escopos concedidos na emissão do token
    exp: u64,             // timestamp de expiração (validado automaticamente)
}

pub async fn auth_middleware<B>(
    State(state): State<AppState>,
    mut req: Request<B>,
    next: Next<B>,
) -> Result<Response, StatusCode> {
    let auth_header = req
        .headers()
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !auth_header.starts_with("Bearer ") {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let token = &auth_header[7..];

    // Especifica HS256 explicitamente para evitar algorithm confusion attacks
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_exp = true;

    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(state.jwt_secret.as_bytes()),
        &validation,
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let claims = token_data.claims;

    let tenant_id = uuid::Uuid::parse_str(&claims.tenant_id)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;
    let user_id = claims.sub.parse::<i32>()
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // flow_permissions carregados do Redis com TTL curto (ex: 60s).
    // Se o cache expirar ou não existir, busca do banco via TenantUser.
    // Garante que revogações de acesso a fluxos reflitam sem aguardar
    // expiração do JWT (que pode ter validade longa).
    let flow_permissions = state
        .permissions_cache
        .get_flow_permissions(tenant_id, user_id)
        .await
        .unwrap_or_default();

    let ctx = RequestContext {
        tenant_id,
        user_id,
        user_scopes: claims.scopes,
        flow_permissions,
    };

    req.extensions_mut().insert(ctx);
    Ok(next.run(req).await)
}
```

---

## 5. Implementação Prática: Validação no Repositório (Rust/SQLx)

Toda implementação concreta de repositório dentro da crate `infrastructure_postgres` deve receber a transação SQLx ativa e o `RequestContext`, validando o escopo antes de executar qualquer operação de escrita:

```rust
// server/crates/infrastructure_postgres/src/tenants/plans.rs
use async_trait::async_trait;
use sqlx::{Postgres, Transaction};
use rust_decimal::Decimal;
use crate::errors::DbError;
use crate::security::RequestContext;

pub struct PostgresFaturamentoRepository;

#[async_trait]
pub trait FaturamentoRepository: Send + Sync {
    async fn registrar_lancamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        valor: Decimal,
        metodo: &str,
        descricao: &str,
    ) -> Result<(), DbError>;
}

#[async_trait]
impl FaturamentoRepository for PostgresFaturamentoRepository {
    async fn registrar_lancamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        valor: Decimal,
        metodo: &str,
        descricao: &str,
    ) -> Result<(), DbError> {
        // Barreira 1: validação de escopo antes de qualquer I/O
        if !ctx.has_permission("financeiro:write") {
            return Err(DbError::PermissionDenied);
        }

        // Barreira 2: tenant_id extraído do RequestContext verificado (nunca do payload)
        // O RLS do banco está ativo na transação via SET LOCAL app.current_tenant
        sqlx::query!(
            r#"
            INSERT INTO tenants_paymentrecord
                (tenant_id, amount, payment_date, payment_method,
                 period_start, period_end, notes, created_at)
            VALUES
                ($1, $2, CURRENT_DATE, $3,
                 CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days', $4, NOW())
            "#,
            ctx.tenant_id,
            valor,
            metodo,
            descricao,
        )
        .execute(&mut **tx)
        .await
        .map_err(DbError::SqlxError)?;

        Ok(())
    }
}
```

---

## 6. Mitigação de Ameaças (OWASP Top 10)

### 6.1 IDOR (Insecure Direct Object Reference)
* **Ameaça:** Um usuário do *Tenant A* altera o ID na URL (ex: `/api/contatos/123` → `/api/contatos/456`) e acessa dados do *Tenant B*.
* **Defesa:** As queries incluem `WHERE tenant_id = $1` com o valor extraído do `RequestContext` (origem: JWT verificado). O RLS ativo reforça o filtro no PostgreSQL. Um ID de outro tenant retorna `None` ou vazio — nunca dados cruzados.

### 6.2 Privilege Escalation (Escalação de Privilégios)
* **Ameaça:** Um atendente comum tenta executar operações administrativas manipulando a requisição.
* **Defesa:** Os escopos são carregados das Claims do JWT no middleware e validados atomicamente no repositório via `ctx.has_permission()`. Modificação dos escopos no lado do cliente é detectada pela verificação de assinatura do JWT.

### 6.3 Injeção de SQL (SQL Injection)
* **Ameaça:** Parâmetros adulterados tentam alterar a lógica de seleção de tenants.
* **Defesa:** O uso obrigatório das macros `sqlx::query!` e `sqlx::query_as!` parametriza e prepara todos os valores no driver PostgreSQL — injeção SQL direta é impossível por construção.

### 6.4 Broken Access Control por Revogação Tardia
* **Ameaça:** As permissões de fluxo de um atendente são revogadas no painel, mas o JWT ainda válido continua concedendo acesso.
* **Defesa:** `flow_permissions` **não** são embutidas no JWT. São carregadas do cache Redis (TTL curto de 60s) pelo middleware a cada requisição. Revogar o acesso no painel invalida o cache Redis, e na próxima requisição o middleware já não concede acesso ao fluxo.

---

## 7. Check-list de Code Review (Permissões)

- [ ] O `tenant_id` é obtido exclusivamente do `RequestContext` (origem: JWT), nunca de parâmetros HTTP externos?
- [ ] Toda operação de escrita valida `ctx.has_permission("recurso:write")` antes de executar a query?
- [ ] Filtros de Kanban por fluxo usam `ctx.has_flow_permission(flow_id)` ou `ctx.flow_permissions`?
- [ ] O escopo utilizado na validação pertence ao catálogo canônico da Seção 3?
- [ ] O middleware usa `Validation::new(Algorithm::HS256)` com `validate_exp = true`?
- [ ] O `JWT_SECRET` é injetado como estado da aplicação (carregado uma vez), não lido por `env::var()` no middleware?
- [ ] `flow_permissions` são carregadas do Redis (TTL curto) pelo middleware, não embutidas no JWT?
