use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

use crate::errors::DbError;

// `plaintext` é a senha em claro: jamais logar.
#[tracing::instrument(level = "debug", skip(plaintext), err)]
pub fn hash_password(plaintext: &str) -> Result<String, DbError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(plaintext.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| DbError::CryptoError(format!("falha ao gerar hash de senha: {e}")))
}

pub fn verify_password(plaintext: &str, phc_hash: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(phc_hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(plaintext.as_bytes(), &parsed)
        .is_ok()
}

/// Variante assíncrona de [`hash_password`]: executa o cálculo CPU-bound do Argon2
/// em uma thread de bloqueio dedicada (`spawn_blocking`), liberando o executor async.
#[tracing::instrument(level = "debug", skip(plaintext), err)]
pub async fn hash_password_async(plaintext: String) -> Result<String, DbError> {
    // `move` transfere a senha para a thread de bloqueio; ela nunca é logada.
    tokio::task::spawn_blocking(move || hash_password(&plaintext))
        .await
        .map_err(|e| {
            DbError::CryptoError(format!("falha ao agendar hash em spawn_blocking: {e}"))
        })?
}

/// Variante assíncrona de [`verify_password`]: roda a verificação Argon2 (CPU-bound)
/// fora do executor async. Retorna `false` em qualquer falha de junção da task.
#[tracing::instrument(level = "debug", skip(plaintext, phc_hash))]
pub async fn verify_password_async(plaintext: String, phc_hash: String) -> bool {
    tokio::task::spawn_blocking(move || verify_password(&plaintext, &phc_hash))
        .await
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_verify_roundtrip() {
        let hash = hash_password("senha_secreta_123").unwrap();
        assert!(hash.starts_with("$argon2id$"));
        assert!(verify_password("senha_secreta_123", &hash));
    }

    #[test]
    fn test_verify_wrong_password() {
        let hash = hash_password("correta").unwrap();
        assert!(!verify_password("errada", &hash));
    }

    #[test]
    fn test_verify_invalid_hash() {
        assert!(!verify_password("qualquer", "hash_invalido"));
    }

    #[test]
    fn test_hashes_are_unique() {
        let h1 = hash_password("mesma_senha").unwrap();
        let h2 = hash_password("mesma_senha").unwrap();
        assert_ne!(h1, h2, "cada hash deve ter salt único");
    }
}
