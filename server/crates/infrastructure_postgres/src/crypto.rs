use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};

use crate::errors::DbError;

/// Gerencia criptografia simétrica AES-256-GCM das chaves de API em repouso.
/// A chave mestra NUNCA aparece em logs — Debug é implementado manualmente.
pub struct CipherManager {
    key: [u8; 32],
}

impl std::fmt::Debug for CipherManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CipherManager")
            .field("key", &"[REDACTED]")
            .finish()
    }
}

impl CipherManager {
    /// Carrega a chave mestra (32 bytes) da variável de ambiente ENCRYPTION_KEY (base64).
    #[tracing::instrument(err)]
    pub fn new_from_env() -> Result<Self, DbError> {
        let key_str = std::env::var("ENCRYPTION_KEY")
            .map_err(|_| DbError::ConfigError("ENCRYPTION_KEY não configurada".into()))?;
        let key_bytes = BASE64
            .decode(key_str.trim())
            .map_err(|_| DbError::CryptoError("ENCRYPTION_KEY inválida (base64)".into()))?;
        if key_bytes.len() != 32 {
            return Err(DbError::CryptoError(
                "a chave mestra precisa ter exatamente 32 bytes (256 bits)".into(),
            ));
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(&key_bytes);
        Ok(Self { key })
    }

    /// Encripta `plaintext` e retorna (ciphertext_b64, nonce_b64, tag_b64).
    /// Nonce de 96 bits gerado via OsRng (CSPRNG do SO) — nunca reutilizar.
    // `plaintext` é segredo: jamais logar.
    #[tracing::instrument(level = "debug", skip(self, plaintext), err)]
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<(String, String, String), DbError> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| DbError::CryptoError("falha ao inicializar AES-GCM".into()))?;
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        // Resultado: ciphertext || tag (últimos 16 bytes)
        let ct_tag = cipher
            .encrypt(&nonce, plaintext)
            .map_err(|_| DbError::CryptoError("falha na encriptação".into()))?;
        let (ct, tag) = ct_tag.split_at(ct_tag.len() - 16);
        Ok((BASE64.encode(ct), BASE64.encode(nonce), BASE64.encode(tag)))
    }

    /// Descriptografa a partir dos três componentes base64.
    #[tracing::instrument(level = "debug", skip(self, ct_b64, nonce_b64, tag_b64), err)]
    pub fn decrypt(
        &self,
        ct_b64: &str,
        nonce_b64: &str,
        tag_b64: &str,
    ) -> Result<Vec<u8>, DbError> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| DbError::CryptoError("falha ao inicializar AES-GCM".into()))?;
        let ct = BASE64
            .decode(ct_b64)
            .map_err(|_| DbError::CryptoError("ciphertext inválido (base64)".into()))?;
        let nonce_bytes = BASE64
            .decode(nonce_b64)
            .map_err(|_| DbError::CryptoError("nonce inválido (base64)".into()))?;
        let tag = BASE64
            .decode(tag_b64)
            .map_err(|_| DbError::CryptoError("tag inválida (base64)".into()))?;
        let nonce = Nonce::from_slice(&nonce_bytes);
        let mut ct_tag = ct;
        ct_tag.extend_from_slice(&tag);
        cipher
            .decrypt(nonce, ct_tag.as_slice())
            .map_err(|_| DbError::CryptoError("integridade violada ou chave inválida".into()))
    }

    /// Descriptografa uma entrada do dicionário JSONB api_keys.
    /// Retorna String vazia se a chave não estiver presente.
    #[tracing::instrument(level = "debug", skip(self, api_keys), fields(key_name = %key_name), err)]
    pub fn decrypt_from_jsonb(
        &self,
        api_keys: &serde_json::Value,
        key_name: &str,
    ) -> Result<String, DbError> {
        let entry = match api_keys.get(key_name) {
            None | Some(serde_json::Value::Null) => return Ok(String::new()),
            Some(v) => v,
        };
        let ct = entry
            .get("ciphertext")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if ct.is_empty() {
            return Ok(String::new());
        }
        let nonce = entry.get("nonce").and_then(|v| v.as_str()).unwrap_or("");
        let tag = entry.get("tag").and_then(|v| v.as_str()).unwrap_or("");
        let bytes = self.decrypt(ct, nonce, tag)?;
        String::from_utf8(bytes)
            .map_err(|e| DbError::CryptoError(format!("plaintext não é UTF-8: {e}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn get_test_cipher() -> CipherManager {
        // MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE= é base64 de 32 bytes válidos
        let key_str = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=";
        std::env::set_var("ENCRYPTION_KEY", key_str);
        CipherManager::new_from_env().unwrap()
    }

    #[test]
    fn cipher_manager_initializes_from_env_successfully() {
        let _cipher = get_test_cipher();
    }

    #[test]
    fn cipher_manager_fails_initialization_when_key_is_missing() {
        // Arrange
        std::env::remove_var("ENCRYPTION_KEY");

        // Act
        let result = CipherManager::new_from_env();

        // Assert
        assert!(result.is_err());
        assert!(matches!(result.err().unwrap(), DbError::ConfigError(_)));
    }

    #[test]
    fn cipher_manager_fails_initialization_when_key_is_invalid_base64() {
        // Arrange
        std::env::set_var("ENCRYPTION_KEY", "not-base64-content!");

        // Act
        let result = CipherManager::new_from_env();

        // Assert
        assert!(result.is_err());
        assert!(matches!(result.err().unwrap(), DbError::CryptoError(_)));
    }

    #[test]
    fn cipher_manager_fails_initialization_when_key_has_invalid_length() {
        // Arrange - Base64 correspondente a 16 bytes em vez de 32
        let short_key = BASE64.encode(vec![0u8; 16]);
        std::env::set_var("ENCRYPTION_KEY", short_key);

        // Act
        let result = CipherManager::new_from_env();

        // Assert
        assert!(result.is_err());
        assert!(matches!(result.err().unwrap(), DbError::CryptoError(_)));
    }

    #[test]
    fn encrypts_and_decrypts_plaintext_successfully() {
        // Arrange
        let cipher = get_test_cipher();
        let original_text = b"Texto ultra secreto de teste!";

        // Act
        let (ct, nonce, tag) = cipher.encrypt(original_text).unwrap();
        assert!(!ct.is_empty());
        assert!(!nonce.is_empty());
        assert!(!tag.is_empty());

        let decrypted = cipher.decrypt(&ct, &nonce, &tag).unwrap();

        // Assert
        assert_eq!(decrypted, original_text);
    }

    #[test]
    fn decrypt_fails_when_integrity_tag_is_invalid() {
        // Arrange
        let cipher = get_test_cipher();
        let original_text = b"Mensagem secreta";
        let (ct, nonce, tag) = cipher.encrypt(original_text).unwrap();

        // Adultera a tag (altera o primeiro caractere)
        let invalid_tag = if let Some(rest) = tag.strip_prefix('A') {
            format!("B{rest}")
        } else {
            format!("A{}", &tag[1..])
        };

        // Act
        let result = cipher.decrypt(&ct, &nonce, &invalid_tag);

        // Assert
        assert!(result.is_err());
        match result {
            Err(DbError::CryptoError(msg)) => {
                assert!(msg.contains("integridade violada") || msg.contains("chave inválida"))
            }
            _ => panic!("Esperado erro de integridade violada"),
        }
    }

    #[test]
    fn decrypts_api_keys_from_jsonb_correctly() {
        // Arrange
        let cipher = get_test_cipher();
        let secret_key = "sk-live-123456789";
        let (ct, nonce, tag) = cipher.encrypt(secret_key.as_bytes()).unwrap();

        let api_keys_json = json!({
            "openai_api_key": {
                "ciphertext": ct,
                "nonce": nonce,
                "tag": tag
            },
            "groq_api_key": null,
            "corrupt_api_key": {
                "ciphertext": "invalidbase64",
                "nonce": nonce,
                "tag": tag
            }
        });

        // 1. Act & Assert - Recupera chave existente
        let decrypted = cipher
            .decrypt_from_jsonb(&api_keys_json, "openai_api_key")
            .unwrap();
        assert_eq!(decrypted, secret_key);

        // 2. Act & Assert - Chave nula deve retornar string vazia
        let decrypted_null = cipher
            .decrypt_from_jsonb(&api_keys_json, "groq_api_key")
            .unwrap();
        assert!(decrypted_null.is_empty());

        // 3. Act & Assert - Chave inexistente deve retornar string vazia
        let decrypted_missing = cipher
            .decrypt_from_jsonb(&api_keys_json, "google_api_key")
            .unwrap();
        assert!(decrypted_missing.is_empty());

        // 4. Act & Assert - Chave corrompida (base64 inválido) deve retornar erro
        let decrypt_corrupt_res = cipher.decrypt_from_jsonb(&api_keys_json, "corrupt_api_key");
        assert!(decrypt_corrupt_res.is_err());
    }

    #[test]
    fn decrypt_from_jsonb_fails_when_plaintext_is_not_utf8() {
        // Arrange - Encripta bytes que não formam string UTF-8 válida (ex.: 0x80)
        let cipher = get_test_cipher();
        let non_utf8_data = vec![0x80, 0x81, 0xff];
        let (ct, nonce, tag) = cipher.encrypt(&non_utf8_data).unwrap();

        let api_keys_json = json!({
            "invalid_utf8_key": {
                "ciphertext": ct,
                "nonce": nonce,
                "tag": tag
            }
        });

        // Act
        let result = cipher.decrypt_from_jsonb(&api_keys_json, "invalid_utf8_key");

        // Assert
        assert!(result.is_err());
        assert!(matches!(result.err().unwrap(), DbError::CryptoError(_)));
    }

    #[test]
    fn cipher_manager_debug_format_does_not_leak_key_contents() {
        // Arrange
        let cipher = get_test_cipher();

        // Act
        let debug_str = format!("{:?}", cipher);

        // Assert
        assert!(debug_str.contains("CipherManager"));
        assert!(debug_str.contains("[REDACTED]"));
        assert!(!debug_str.contains("MDEy")); // Não deve vazar a base64 da chave
    }
}
