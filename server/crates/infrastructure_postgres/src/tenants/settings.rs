use std::collections::HashMap;

use sqlx::PgPool;

use crate::{crypto::CipherManager, errors::DbError};

#[derive(Debug, sqlx::FromRow)]
pub struct CoreSettingRow {
    pub key: String,
    pub value: String,
    pub encrypted: bool,
}

/// Carrega todas as CoreSettings globais em um mapa key→value.
/// Valores encrypted são descriptografados antes de retornar.
#[tracing::instrument(skip(pool, cipher), err)]
pub async fn load_all_settings(
    pool: &PgPool,
    cipher: &CipherManager,
) -> Result<HashMap<String, String>, DbError> {
    let rows = sqlx::query_as!(
        CoreSettingRow,
        "SELECT key, value, encrypted FROM settings_manager_coresettings ORDER BY key"
    )
    .fetch_all(pool)
    .await?;

    let mut map = HashMap::with_capacity(rows.len());
    for row in rows {
        let val = if row.encrypted {
            // Formato armazenado para coresettings criptografados: "ct_b64:nonce_b64:tag_b64"
            let parts: Vec<&str> = row.value.splitn(3, ':').collect();
            if parts.len() == 3 {
                let bytes = cipher.decrypt(parts[0], parts[1], parts[2])?;
                String::from_utf8(bytes).unwrap_or_default()
            } else {
                row.value
            }
        } else {
            row.value
        };
        map.insert(row.key, val);
    }
    Ok(map)
}

/// Obtém ou insere/atualiza uma configuração global.
// `value` pode ser segredo (quando `encrypted`): omitido do span.
#[tracing::instrument(skip(pool, value, description), fields(key = %key, encrypted = encrypted), err)]
pub async fn upsert_setting(
    pool: &PgPool,
    key: &str,
    value: &str,
    encrypted: bool,
    description: &str,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"INSERT INTO settings_manager_coresettings (key, value, encrypted, description, updated_at)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (key) DO UPDATE
               SET value = EXCLUDED.value,
                   encrypted = EXCLUDED.encrypted,
                   description = EXCLUDED.description,
                   updated_at = NOW()"#,
        key, value, encrypted, description
    )
    .execute(pool)
    .await?;
    Ok(())
}
