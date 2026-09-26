use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Atendente {
    pub id: i32,
    pub tenant_id: Uuid,
    pub nome: String,
    pub slug: String,
    pub telefone: Option<String>,
    pub cargo: String,
    pub email: String,
    pub departamento_id: Option<i32>,
    pub fluxo_id: i32,
    pub usuario_id: Option<i32>,
    pub usuario_sistema: Option<String>,
    pub ativo: bool,
    pub disponivel: bool,
    pub max_atendimentos_simultaneos: i32,
    pub data_ultima_atribuicao: Option<DateTime<Utc>>,
    pub horario_trabalho: serde_json::Value,
    pub especialidades: serde_json::Value,
    pub metadados: serde_json::Value,
    pub data_cadastro: DateTime<Utc>,
    pub ultima_atividade: DateTime<Utc>,
}

#[async_trait]
pub trait AtendenteRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        email: &str,
        cargo: &str,
        fluxo_id: i32,
        departamento_id: Option<i32>,
    ) -> Result<Atendente, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendente>, DbError>;

    /// O atendente vinculado a um usuário do sistema.
    ///
    /// É como o quadro descobre QUEM está arrastando o cartão: a sessão traz
    /// o `auth_user`, e quem atende é a linha de `oraculo_atendente` que aponta
    /// para ele. Nem todo usuário do tenant é atendente — um admin que arrasta
    /// um cartão não vira dono da conversa por isso.
    async fn buscar_por_usuario(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        usuario_id: i32,
    ) -> Result<Option<Atendente>, DbError>;

    /// Atualiza o cadastro do atendente.
    ///
    /// `ativo` e `disponivel` são estados distintos e ambos passam por aqui:
    /// quem está de férias fica ativo e indisponível, e confundir os dois
    /// esconde por que uma fila parou.
    #[allow(clippy::too_many_arguments)]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        cargo: &str,
        departamento_id: Option<i32>,
        fluxo_id: i32,
        ativo: bool,
        disponivel: bool,
        max_simultaneos: i32,
    ) -> Result<bool, DbError>;

    /// Desativa — não apaga. Atendimentos apontam para o atendente, e remover a
    /// linha levaria o histórico de quem atendeu junto.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// Conversas que este atendente ainda está tocando.
    async fn contar_atendimentos_em_andamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError>;

    /// Lista os atendentes do tenant, ativos primeiro.
    ///
    /// Inclui os inativos: quem administra a equipe precisa ver quem saiu para
    /// reativar ou entender uma fila parada.
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Atendente>, DbError>;

    /// Seleciona o próximo atendente da fila de rodízio: quem está há mais tempo
    /// sem receber conversa, entre os que ainda cabem no próprio limite (D2).
    ///
    /// **Trava a linha escolhida** (`FOR UPDATE SKIP LOCKED`). Sem isso, duas
    /// transferências simultâneas leem a mesma pessoa como "a próxima" e ambas
    /// atribuem — `max_atendimentos_simultaneos` seria estourado justamente no
    /// momento de pico, que é quando ele existe para valer. `SKIP LOCKED` faz a
    /// segunda transação pular para o próximo da fila em vez de esperar.
    ///
    /// `departamento_id` e `fluxo_id` são filtros independentes: o atendente tem
    /// `fluxo_id` obrigatório e `departamento_id` opcional, então filtrar pelos
    /// dois de uma vez excluiria quem está no fluxo certo e sem departamento.
    async fn buscar_disponivel_round_robin(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
    ) -> Result<Option<Atendente>, DbError>;

    async fn atualizar_ultima_atribuicao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendente_id: i32,
    ) -> Result<(), DbError>;

    async fn atualizar_disponibilidade(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendente_id: i32,
        disponivel: bool,
    ) -> Result<(), DbError>;
}

pub struct PostgresAtendenteRepository;

/// De que lado o vínculo atendente↔login é procurado.
enum VinculoPor {
    /// O login que está agindo (procura o atendente dele).
    Usuario(i32),
    /// Um atendente recém-criado (procura o login dele).
    Atendente(i32),
}

/// Liga um atendente ativo e sem vínculo ao login de mesmo e-mail.
///
/// Só dentro do tenant e só a membro ATIVO dele (`tenants_tenantuser`, sob
/// RLS): um e-mail igual de fora do tenant nunca vira atendente aqui. Um login
/// fica com no máximo um atendente por tenant. Devolve o `usuario_id` ligado.
///
/// Sem macro: consulta nova, fora do cache `.sqlx`.
async fn vincular_login_por_email(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    por: VinculoPor,
) -> Result<Option<i32>, DbError> {
    let (usuario, atendente) = match por {
        VinculoPor::Usuario(u) => (Some(u), None),
        VinculoPor::Atendente(a) => (None, Some(a)),
    };
    let ligado: Option<(i32,)> = sqlx::query_as(
        r#"UPDATE oraculo_atendente a
              SET usuario_id = v.user_id
             FROM (
                   SELECT a2.id AS atendente_id, u.id AS user_id
                     FROM oraculo_atendente a2
                     JOIN auth_user u
                       ON lower(trim(u.email)) = lower(trim(a2.email))
                     JOIN tenants_tenantuser tu
                       ON tu.user_id = u.id AND tu.tenant_id = a2.tenant_id
                      AND tu.is_active
                    WHERE a2.tenant_id = $1
                      AND a2.usuario_id IS NULL
                      AND a2.ativo
                      AND trim(a2.email) <> ''
                      AND ($2::int IS NULL OR u.id = $2)
                      AND ($3::int IS NULL OR a2.id = $3)
                      AND NOT EXISTS (
                            SELECT 1 FROM oraculo_atendente j
                             WHERE j.tenant_id = a2.tenant_id AND j.usuario_id = u.id
                          )
                    ORDER BY a2.id, u.id
                    LIMIT 1
                  ) v
            WHERE a.id = v.atendente_id
        RETURNING a.usuario_id"#,
    )
    .bind(tenant_id)
    .bind(usuario)
    .bind(atendente)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(ligado.map(|(u,)| u))
}

#[async_trait]
impl AtendenteRepository for PostgresAtendenteRepository {
    // `nome`/`email` são PII: `skip_all`.
    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        email: &str,
        cargo: &str,
        fluxo_id: i32,
        departamento_id: Option<i32>,
    ) -> Result<Atendente, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Atendente,
            r#"INSERT INTO oraculo_atendente
                   (tenant_id, nome, email, cargo, fluxo_id, departamento_id)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, nome, slug, telefone, cargo, email,
                         departamento_id, fluxo_id, usuario_id, usuario_sistema,
                         ativo, disponivel, max_atendimentos_simultaneos,
                         data_ultima_atribuicao, horario_trabalho, especialidades,
                         metadados, data_cadastro, ultima_atividade"#,
            ctx.tenant_id,
            nome,
            email,
            cargo,
            fluxo_id,
            departamento_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        // O atendente novo já nasce ligado ao login de mesmo e-mail, se a
        // pessoa já é membro do tenant; senão, liga no primeiro "Assumir".
        let mut row = row;
        if let Some(usuario) =
            vincular_login_por_email(tx, ctx.tenant_id, VinculoPor::Atendente(row.id)).await?
        {
            row.usuario_id = Some(usuario);
        }
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendente>, DbError> {
        let row = sqlx::query_as!(
            Atendente,
            r#"SELECT id, tenant_id, nome, slug, telefone, cargo, email,
                      departamento_id, fluxo_id, usuario_id, usuario_sistema,
                      ativo, disponivel, max_atendimentos_simultaneos,
                      data_ultima_atribuicao, horario_trabalho, especialidades,
                      metadados, data_cadastro, ultima_atividade
               FROM oraculo_atendente
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(usuario_id = usuario_id))]
    async fn buscar_por_usuario(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        usuario_id: i32,
    ) -> Result<Option<Atendente>, DbError> {
        // Login ainda sem atendente: liga pelo e-mail antes de buscar. O
        // cadastro nunca preenchia o vínculo, e sem ele "Assumir" dizia que o
        // usuário não era atendente.
        vincular_login_por_email(tx, ctx.tenant_id, VinculoPor::Usuario(usuario_id)).await?;
        // Só atendente ATIVO: quem saiu da equipe não volta a receber conversa
        // por ter arrastado um cartão.
        let row = sqlx::query_as!(
            Atendente,
            r#"SELECT id, tenant_id, nome, slug, telefone, cargo, email,
                      departamento_id, fluxo_id, usuario_id, usuario_sistema,
                      ativo, disponivel, max_atendimentos_simultaneos,
                      data_ultima_atribuicao, horario_trabalho, especialidades,
                      metadados, data_cadastro, ultima_atividade
               FROM oraculo_atendente
               WHERE tenant_id = $1 AND usuario_id = $2 AND ativo = true
               LIMIT 1"#,
            ctx.tenant_id,
            usuario_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    // `nome` é PII: `skip_all`.
    #[tracing::instrument(skip_all, fields(id = id, fluxo_id = fluxo_id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        cargo: &str,
        departamento_id: Option<i32>,
        fluxo_id: i32,
        ativo: bool,
        disponivel: bool,
        max_simultaneos: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_atendente
                  SET nome = $3, cargo = $4, departamento_id = $5, fluxo_id = $6,
                      ativo = $7, disponivel = $8, max_atendimentos_simultaneos = $9,
                      ultima_atividade = NOW()
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id,
            nome,
            cargo,
            departamento_id,
            fluxo_id,
            ativo,
            disponivel,
            max_simultaneos
        )
        .execute(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        // Sai de disponível junto: um atendente inativo que continuasse
        // "disponível" seguiria elegível no round-robin.
        let res = sqlx::query!(
            r#"UPDATE oraculo_atendente
                  SET ativo = false, disponivel = false, ultima_atividade = NOW()
                WHERE tenant_id = $1 AND id = $2 AND ativo = true"#,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn contar_atendimentos_em_andamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError> {
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "total!"
                 FROM oraculo_atendimento
                WHERE tenant_id = $1 AND atendente_humano_id = $2
                  AND status NOT IN ('resolvido', 'cancelado', 'arquivado')"#,
            ctx.tenant_id,
            id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total)
    }

    #[tracing::instrument(skip_all, fields(departamento_id, fluxo_id))]
    async fn buscar_disponivel_round_robin(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
    ) -> Result<Option<Atendente>, DbError> {
        // `NULLS FIRST`: quem nunca recebeu conversa vai antes de quem já
        // recebeu — é a ordem justa para quem acabou de entrar na equipe.
        // Desempate por `id` para a fila ser determinística quando duas pessoas
        // têm o mesmo instante (equipe recém-criada tem todo mundo em NULL).
        //
        // A contagem de carga usa o MESMO recorte de
        // `contar_atendimentos_em_andamento` (`NOT IN` dos estados finais), e não
        // uma lista dos estados abertos: um status novo entraria como carga em
        // vez de sumir silenciosamente do cálculo.
        //
        // `at.tenant_id = a.tenant_id` é redundante sob RLS, e está aqui de
        // propósito: `atendente_humano_id` vem de uma sequência global, então a
        // subconsulta sem recorte de tenant só está correta por causa da
        // política — e a política pode um dia ser afrouxada para uma migração.
        let row = sqlx::query_as!(
            Atendente,
            r#"SELECT a.id, a.tenant_id, a.nome, a.slug, a.telefone, a.cargo, a.email,
                      a.departamento_id, a.fluxo_id, a.usuario_id, a.usuario_sistema,
                      a.ativo, a.disponivel, a.max_atendimentos_simultaneos,
                      a.data_ultima_atribuicao, a.horario_trabalho, a.especialidades,
                      a.metadados, a.data_cadastro, a.ultima_atividade
               FROM oraculo_atendente a
               WHERE a.tenant_id = $1
                 AND a.ativo = true
                 AND a.disponivel = true
                 AND ($2::int IS NULL OR a.departamento_id = $2)
                 AND ($3::int IS NULL OR a.fluxo_id = $3)
                 AND (
                     SELECT COUNT(*)::int
                     FROM oraculo_atendimento at
                     WHERE at.tenant_id = a.tenant_id
                       AND at.atendente_humano_id = a.id
                       AND at.status NOT IN ('resolvido', 'cancelado', 'arquivado')
                 ) < a.max_atendimentos_simultaneos
               ORDER BY a.data_ultima_atribuicao ASC NULLS FIRST, a.id
               FOR UPDATE SKIP LOCKED
               LIMIT 1"#,
            ctx.tenant_id,
            departamento_id,
            fluxo_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendente_id = atendente_id))]
    async fn atualizar_ultima_atribuicao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendente_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_atendente
               SET data_ultima_atribuicao = NOW(), ultima_atividade = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            atendente_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendente_id = atendente_id, disponivel = disponivel))]
    async fn atualizar_disponibilidade(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendente_id: i32,
        disponivel: bool,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_atendente SET disponivel = $1, ultima_atividade = NOW()
               WHERE tenant_id = $2 AND id = $3"#,
            disponivel,
            ctx.tenant_id,
            atendente_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Atendente>, DbError> {
        ctx.exigir_qualquer(&["operacional:read", "operacional:admin", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Atendente,
            r#"SELECT id, tenant_id, nome, slug, telefone, cargo, email,
                      departamento_id, fluxo_id, usuario_id, usuario_sistema,
                      ativo, disponivel, max_atendimentos_simultaneos,
                      data_ultima_atribuicao, horario_trabalho, especialidades,
                      metadados, data_cadastro, ultima_atividade
               FROM oraculo_atendente
               WHERE tenant_id = $1
               ORDER BY ativo DESC, nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
