//! Port do cadastro público de tenant (o wizard do app).
//!
//! O cadastro é a única porta de entrada que cria `auth_user`, `tenants_tenant`,
//! `tenants_tenantuser` e `tenants_subscription` sem que exista sessão alguma.
//! Por isso tudo aqui carrega um `signup_token`: os passos 2 em diante só valem
//! para quem começou o cadastro.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use infrastructure_postgres::DbError;
use uuid::Uuid;

/// O que o passo 1 devolve.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SignupIniciado {
    pub tenant_id: Uuid,
    /// Autoriza os passos seguintes. Guardado em `tenants_tenant.access_code`,
    /// coluna que já existia para exatamente este papel (código de acesso
    /// temporário) e que o superusuário pode regerar para destravar um cadastro.
    pub signup_token: String,
    pub user_id: i32,
}

/// Estado corrente de um cadastro, para a tela de acompanhamento.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatusSignup {
    pub tenant_id: Uuid,
    /// 1..4 — espelha `tenants_tenant.onboarding_step`.
    pub passo: i32,
    pub plan_id: Option<i32>,
    /// `PENDING_PAYMENT`, `ACTIVE`, ... — o mesmo vocabulário de
    /// `tenants_subscription.status`.
    pub status_assinatura: String,
    pub tenant_ativo: bool,
    pub periodo_fim: Option<DateTime<Utc>>,
}

/// Por que um slug não pode ser usado.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SlugIndisponivel {
    /// Já existe um tenant com ele.
    EmUso,
    /// Está na lista de nomes que a plataforma reserva para si.
    Reservado,
    /// Formato inválido (tamanho, caracteres).
    Invalido,
}

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait SignupStore: Send + Sync {
    /// `None` = disponível.
    async fn verificar_slug(&self, slug: &str) -> Result<Option<SlugIndisponivel>, DbError>;

    /// Cria, numa única transação: usuário, tenant inativo, vínculo de admin e
    /// assinatura pendente. Falha em qualquer ponto não deixa registro meio
    /// criado.
    ///
    /// `phone` vazio = não informado (o adapter grava NULL). É `&str` e não
    /// `Option<&str>` porque o `automock` exige lifetime nomeado no `Option`.
    #[allow(clippy::too_many_arguments)]
    async fn iniciar(
        &self,
        name: &str,
        slug: &str,
        email: &str,
        username: &str,
        password_hash: &str,
        phone: &str,
    ) -> Result<SignupIniciado, DbError>;

    /// Registra o plano escolhido no passo 2. Ainda não ativa nada.
    async fn selecionar_plano(&self, tenant_id: Uuid, plan_id: i32) -> Result<(), DbError>;

    /// Ativa o tenant e a assinatura após o pagamento confirmado. Idempotente:
    /// chamar de novo (retentativa, webhook duplicado) não estende o período.
    async fn ativar(
        &self,
        tenant_id: Uuid,
        plan_id: i32,
        periodo_fim: DateTime<Utc>,
        gateway: &str,
        referencia_externa: &str,
    ) -> Result<(), DbError>;

    async fn status(&self, tenant_id: Uuid) -> Result<Option<StatusSignup>, DbError>;

    /// Confere o `signup_token` contra o tenant. A comparação acontece no
    /// predicado SQL: não é tempo constante, mas o token tem 80 bits de
    /// entropia e cada tentativa custa um round-trip de banco atrás do rate
    /// limit da borda — adivinhá-lo por timing não é o caminho mais barato.
    async fn validar_token(&self, tenant_id: Uuid, token: &str) -> Result<bool, DbError>;

    /// Planos oferecidos no cadastro (só os ativos).
    async fn listar_planos_publicos(&self) -> Result<Vec<serde_json::Value>, DbError>;
}
