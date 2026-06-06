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
