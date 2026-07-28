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
///
/// **Uma linha que não decifra não derruba as demais.** Antes, o `?` na
/// decifragem abortava a função inteira: uma única CoreSetting gravada com
/// outra chave (rotação de `ENCRYPTION_KEY` sem re-cifrar, importação parcial)
/// fazia `resolve_runtime_config` falhar e, com ele, a config de **todos** os
/// tenants — a IA parava por completo por causa de uma linha. Agora a chave
/// problemática é omitida do mapa (o consumidor cai no fallback dela) e o
/// incidente aparece no log, em WARN, com o nome da chave.
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
    let mut ilegiveis: Vec<String> = Vec::new();
    for row in rows {
        let val = if row.encrypted {
            // Formato armazenado para coresettings criptografados: "ct_b64:nonce_b64:tag_b64"
            let parts: Vec<&str> = row.value.splitn(3, ':').collect();
            if parts.len() == 3 {
                match cipher.decrypt(parts[0], parts[1], parts[2]) {
                    Ok(bytes) => String::from_utf8(bytes).unwrap_or_default(),
                    Err(_) => {
                        // Sem o erro nem o valor no log: ambos podem carregar
                        // fragmento do material cifrado. Só o nome da chave.
                        ilegiveis.push(row.key);
                        continue;
                    }
                }
            } else {
                row.value
            }
        } else {
            row.value
        };
        map.insert(row.key, val);
    }
    if !ilegiveis.is_empty() {
        tracing::warn!(
            chaves = ?ilegiveis,
            "CoreSettings que não decifram com a ENCRYPTION_KEY atual — omitidas do mapa; \
             quem depender delas cai no fallback (provável rotação de chave sem re-cifrar)"
        );
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
