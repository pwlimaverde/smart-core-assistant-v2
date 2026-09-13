//! N11 E8 — tokens de redefinição de senha.
//!
//! Só o **hash** do token toca o banco (ver a migration 0033). As queries são
//! de tempo de execução (`sqlx::query`), como as do convite, para não depender
//! do cache offline do sqlx.

use chrono::{DateTime, Utc};
use sqlx::PgPool;

use crate::errors::DbError;

/// Registra um pedido de redefinição, aposentando os anteriores do usuário.
///
/// Se a pessoa pediu duas vezes, só o último e-mail vale — e um link esquecido
/// na caixa de entrada não fica esperando alguém achá-lo.
#[tracing::instrument(skip_all, fields(user_id = user_id))]
pub async fn registrar(
    pool: &PgPool,
    user_id: i32,
    token_hash: &str,
    expira_em: DateTime<Utc>,
) -> Result<(), DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query(
        "UPDATE auth_password_reset SET used_at = NOW() \
         WHERE user_id = $1 AND used_at IS NULL",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO auth_password_reset (user_id, token_hash, expires_at) \
         VALUES ($1, $2, $3)",
    )
    .bind(user_id)
    .bind(token_hash)
    .bind(expira_em)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

/// Consome o token e grava a senha nova, numa transação só.
///
/// `None` quando o token não existe, venceu, já foi usado, ou quando o usuário
/// está desativado. Para quem chama os quatro são a mesma resposta ("este link
/// não vale mais"): distinguir diria a quem tem o link se ele algum dia valeu.
///
/// Consumir e trocar juntos é o que impede o link de valer duas vezes — dois
/// cliques simultâneos disputam o mesmo `UPDATE … WHERE used_at IS NULL`, e só
/// um recebe a linha de volta.
#[tracing::instrument(skip_all)]
pub async fn consumir_e_trocar_senha(
    pool: &PgPool,
    token_hash: &str,
    password_hash: &str,
) -> Result<Option<i32>, DbError> {
    let mut tx = pool.begin().await?;

    let user_id: Option<i32> = sqlx::query_scalar(
        "UPDATE auth_password_reset SET used_at = NOW() \
         WHERE token_hash = $1 AND used_at IS NULL AND expires_at > NOW() \
         RETURNING user_id",
    )
    .bind(token_hash)
    .fetch_optional(&mut *tx)
    .await?;
    // Sem `commit`, a transação desfaz ao sair do escopo.
    let Some(user_id) = user_id else {
        return Ok(None);
    };

    let trocou =
        sqlx::query("UPDATE auth_user SET password_hash = $1 WHERE id = $2 AND is_active = TRUE")
            .bind(password_hash)
            .bind(user_id)
            .execute(&mut *tx)
            .await?
            .rows_affected()
            > 0;
    if !trocou {
        return Ok(None);
    }

    // Outros pedidos pendentes do mesmo usuário perdem o sentido: a senha que
    // eles vieram trocar já foi trocada.
    sqlx::query(
        "UPDATE auth_password_reset SET used_at = NOW() \
         WHERE user_id = $1 AND used_at IS NULL",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(Some(user_id))
}
