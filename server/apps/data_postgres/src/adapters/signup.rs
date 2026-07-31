//! Adapter Postgres do cadastro público de tenant.
//!
//! **Tudo aqui usa o `admin_pool` (BYPASSRLS), e isso é essencial.** As tabelas
//! envolvidas têm FORCE RLS com policy `= current_setting('app.current_tenant')`,
//! e no cadastro esse contexto ainda não existe: quem está criando a conta não
//! tem sessão, nem tenant. Sem BYPASSRLS a policy falha fechada em silêncio — a
//! checagem de slug diria "disponível" para um slug em uso, e o INSERT seguinte
//! estouraria com violação de unique. É o mesmo tropeço que o pre-warm de config
//! já custou uma vez.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use infrastructure_postgres::DbError;

use crate::ports::{SignupIniciado, SignupStore, SlugIndisponivel, StatusSignup};

/// Nomes que a plataforma reserva para si — herdados da v1
/// (`docs_dev/planejamento/mapa_navegacao/03_onboarding.md`). Um tenant chamado
/// `admin` ou `api` colidiria com as rotas da própria aplicação.
const SLUGS_RESERVADOS: &[&str] = &[
    "admin",
    "api",
    "www",
    "app",
    "painel",
    "dashboard",
    "public",
    "static",
    "media",
    "tenant",
    "setup",
    "cadastro",
    "login",
];

/// Escopos do primeiro usuário: ele é o dono da conta e precisa conseguir
/// configurar tudo sozinho. Mesmo conjunto que o `CreateTenant` administrativo
/// concede ao bootstrap.
fn escopos_do_dono() -> serde_json::Value {
    serde_json::json!([
        "tenant:admin",
        "atendimentos:read",
        "atendimentos:write",
        "clientes:write"
    ])
}

#[derive(Clone)]
pub struct PgSignupStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgSignupStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }

    /// Pool sem RLS. Sem ele o cadastro não funciona (ver nota do módulo), então
    /// a ausência é ruidosa.
    fn pool_sem_rls(&self) -> &PgPool {
        if self.admin_pool.is_none() {
            tracing::error!(
                "PgSignupStore sem DATABASE_ADMIN_URL: o cadastro público vai falhar ou, \
                 pior, aceitar slugs já em uso — a RLS esconde as linhas existentes"
            );
        }
        self.admin_pool.as_ref().unwrap_or(&self.pool)
    }
}

/// Valida a forma do slug antes de ir ao banco: 3 a 63 caracteres, minúsculas,
/// dígitos e hífen, sem hífen nas pontas.
fn slug_bem_formado(slug: &str) -> bool {
    let n = slug.len();
    if !(3..=63).contains(&n) {
        return false;
    }
    if slug.starts_with('-') || slug.ends_with('-') {
        return false;
    }
    slug.chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// Token de autorização dos passos 2 em diante. Mesmo formato do `access_code`
/// gerado pelo painel (`handler_generate_access_code`), e guardado na mesma
/// coluna: 20 hex maiúsculos de um UUID v4.
fn gerar_signup_token() -> String {
    Uuid::new_v4().simple().to_string()[..20].to_uppercase()
}

#[async_trait]
impl SignupStore for PgSignupStore {
    #[tracing::instrument(skip_all, fields(slug = %slug))]
    async fn verificar_slug(&self, slug: &str) -> Result<Option<SlugIndisponivel>, DbError> {
        let slug = slug.trim().to_lowercase();

        if !slug_bem_formado(&slug) {
            return Ok(Some(SlugIndisponivel::Invalido));
        }
        if SLUGS_RESERVADOS.contains(&slug.as_str()) {
            return Ok(Some(SlugIndisponivel::Reservado));
        }

        let existe = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM tenants_tenant WHERE lower(slug) = $1",
        )
        .bind(&slug)
        .fetch_one(self.pool_sem_rls())
        .await?;

        Ok((existe > 0).then_some(SlugIndisponivel::EmUso))
    }

    #[tracing::instrument(skip_all, fields(slug = %slug))]
    async fn iniciar(
        &self,
        name: &str,
        slug: &str,
        email: &str,
        username: &str,
        password_hash: &str,
        phone: &str,
    ) -> Result<SignupIniciado, DbError> {
        let phone = (!phone.trim().is_empty()).then(|| phone.trim());
        let mut tx = self.pool_sem_rls().begin().await?;

        // 1. O usuário dono. Vem primeiro porque o tenant referencia `owner_id`
        //    — e é justamente o que o `CreateTenant` do painel não faz (ele cai
        //    no `owner_id = 1`, o superusuário).
        let user_id: i32 = sqlx::query_scalar(
            "INSERT INTO auth_user (username, email, password_hash, is_superuser) \
             VALUES ($1, $2, $3, false) RETURNING id",
        )
        .bind(username)
        .bind(email)
        .bind(password_hash)
        .fetch_one(&mut *tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;

        // 2. O tenant, INATIVO. Só o pagamento confirmado o liga.
        let tenant_id = Uuid::new_v4();
        let signup_token = gerar_signup_token();
        sqlx::query(
            "INSERT INTO tenants_tenant \
                 (id, name, slug, api_key, owner_id, email, phone, active, \
                  setup_completed, onboarding_step, access_code) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, false, false, 2, $8)",
        )
        .bind(tenant_id)
        .bind(name)
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .bind(user_id)
        .bind(email)
        .bind(phone)
        .bind(&signup_token)
        .execute(&mut *tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;

        // 3. O vínculo que dá ao dono os escopos de administração do tenant.
        sqlx::query(
            "INSERT INTO tenants_tenantuser \
                 (user_id, tenant_id, role, module_permissions, flow_permissions) \
             VALUES ($1, $2, 'admin', $3, '[]'::jsonb)",
        )
        .bind(user_id)
        .bind(tenant_id)
        .bind(escopos_do_dono())
        .execute(&mut *tx)
        .await?;

        // 4. A assinatura pendente. Existir desde já é o que permite a um
        //    webhook de gateway, minutos depois, ter o que ativar.
        sqlx::query(
            "INSERT INTO tenants_subscription (tenant_id, status) VALUES ($1, 'PENDING_PAYMENT')",
        )
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        Ok(SignupIniciado {
            tenant_id,
            signup_token,
            user_id,
        })
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, plan_id = plan_id))]
    async fn selecionar_plano(&self, tenant_id: Uuid, plan_id: i32) -> Result<(), DbError> {
        let mut tx = self.pool_sem_rls().begin().await?;

        let afetou = sqlx::query(
            "UPDATE tenants_subscription SET plan_id = $1, updated_at = NOW() \
             WHERE tenant_id = $2 AND status = 'PENDING_PAYMENT'",
        )
        .bind(plan_id)
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();

        if afetou == 0 {
            tx.rollback().await?;
            // Assinatura ativa não volta para a escolha de plano por esta porta
            // pública — trocar de plano é operação autenticada.
            return Err(DbError::NotFound);
        }

        sqlx::query(
            "UPDATE tenants_tenant SET onboarding_step = 3, updated_at = NOW() WHERE id = $1",
        )
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, plan_id = plan_id))]
    async fn ativar(
        &self,
        tenant_id: Uuid,
        plan_id: i32,
        periodo_fim: DateTime<Utc>,
        gateway: &str,
        referencia_externa: &str,
    ) -> Result<(), DbError> {
        let mut tx = self.pool_sem_rls().begin().await?;

        // `status <> 'ACTIVE'` é a guarda de idempotência: um webhook duplicado
        // ou uma retentativa do cliente não estende o período de novo.
        let afetou = sqlx::query(
            "UPDATE tenants_subscription \
                SET plan_id = $1, status = 'ACTIVE', \
                    current_period_start = NOW(), current_period_end = $2, \
                    payment_gateway = $3, external_subscription_id = $4, updated_at = NOW() \
              WHERE tenant_id = $5 AND status <> 'ACTIVE'",
        )
        .bind(plan_id)
        .bind(periodo_fim)
        .bind(gateway)
        .bind(referencia_externa)
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();

        if afetou == 0 {
            tx.rollback().await?;
            tracing::info!(
                tenant_id = %tenant_id,
                "ativação ignorada: a assinatura já estava ACTIVE"
            );
            return Ok(());
        }

        // O tenant só existe de verdade a partir daqui. `access_code` é zerado
        // junto: o token de cadastro cumpriu o papel e não deve sobreviver ao
        // fluxo que autorizava.
        sqlx::query(
            "UPDATE tenants_tenant \
                SET active = true, setup_completed = true, onboarding_step = 4, \
                    access_code = NULL, updated_at = NOW() \
              WHERE id = $1",
        )
        .bind(tenant_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn status(&self, tenant_id: Uuid) -> Result<Option<StatusSignup>, DbError> {
        let row = sqlx::query(
            "SELECT t.onboarding_step, t.active, \
                    s.plan_id, s.status, s.current_period_end \
               FROM tenants_tenant t \
               LEFT JOIN tenants_subscription s ON s.tenant_id = t.id \
              WHERE t.id = $1",
        )
        .bind(tenant_id)
        .fetch_optional(self.pool_sem_rls())
        .await?;

        Ok(row.map(|r| StatusSignup {
            tenant_id,
            passo: r.get::<i32, _>("onboarding_step"),
            plan_id: r.get::<Option<i32>, _>("plan_id"),
            status_assinatura: r
                .get::<Option<String>, _>("status")
                .unwrap_or_else(|| "SEM_ASSINATURA".to_string()),
            tenant_ativo: r.get::<bool, _>("active"),
            periodo_fim: r.get::<Option<DateTime<Utc>>, _>("current_period_end"),
        }))
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn validar_token(&self, tenant_id: Uuid, token: &str) -> Result<bool, DbError> {
        if token.trim().is_empty() {
            return Ok(false);
        }
        // `access_code` vira NULL na ativação, e NULL nunca casa em `=` — o token
        // deixa de valer sozinho quando o cadastro termina.
        let encontrado = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM tenants_tenant WHERE id = $1 AND access_code = $2",
        )
        .bind(tenant_id)
        .bind(token.trim())
        .fetch_one(self.pool_sem_rls())
        .await?;
        Ok(encontrado > 0)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_planos_publicos(&self) -> Result<Vec<serde_json::Value>, DbError> {
        // Só o que está à venda, e só o que interessa a quem escolhe: preço e
        // limites. Nada de contagem de assinantes ou campos internos.
        let rows = sqlx::query(
            "SELECT id, name, description, price, max_instances, max_departments, max_fluxos \
               FROM tenants_plan WHERE active = true ORDER BY id",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .iter()
            .map(|r| {
                serde_json::json!({
                    "id": r.get::<i32, _>("id"),
                    "name": r.get::<String, _>("name"),
                    "description": r.get::<String, _>("description"),
                    "price": r.get::<Option<rust_decimal::Decimal>, _>("price")
                        .map(|p| p.to_string()).unwrap_or_default(),
                    "max_instances": r.get::<i32, _>("max_instances"),
                    "max_departments": r.get::<i32, _>("max_departments"),
                    "max_fluxos": r.get::<i32, _>("max_fluxos"),
                })
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aceita_slug_bem_formado() {
        assert!(slug_bem_formado("minha-empresa"));
        assert!(slug_bem_formado("abc"));
        assert!(slug_bem_formado("loja123"));
    }

    #[test]
    fn recusa_slug_malformado() {
        assert!(!slug_bem_formado("ab"), "curto demais");
        assert!(!slug_bem_formado(&"a".repeat(64)), "longo demais");
        assert!(!slug_bem_formado("-loja"), "hífen na ponta");
        assert!(!slug_bem_formado("loja-"), "hífen na ponta");
        assert!(!slug_bem_formado("Minha-Empresa"), "maiúsculas");
        assert!(!slug_bem_formado("minha empresa"), "espaço");
        assert!(!slug_bem_formado("empresa_1"), "underscore");
        assert!(!slug_bem_formado("empresa.com"), "ponto");
    }

    #[test]
    fn reserva_os_nomes_da_plataforma() {
        // Um tenant com slug `admin` colidiria com as rotas do próprio painel.
        for reservado in ["admin", "api", "painel", "login", "cadastro"] {
            assert!(SLUGS_RESERVADOS.contains(&reservado), "{reservado}");
        }
    }

    #[test]
    fn token_de_cadastro_tem_o_formato_do_access_code() {
        let token = gerar_signup_token();
        assert_eq!(token.len(), 20, "cabe no VARCHAR(20) da coluna");
        assert!(token.chars().all(|c| c.is_ascii_hexdigit()));
        assert_eq!(token, token.to_uppercase());
        assert_ne!(token, gerar_signup_token(), "não pode ser previsível");
    }

    #[test]
    fn dono_nasce_com_escopo_de_administracao_do_tenant() {
        let escopos = escopos_do_dono();
        let lista = escopos.as_array().expect("lista de escopos");
        assert!(lista.iter().any(|e| e == "tenant:admin"));
    }
}
