// application/src/tokens.rs (comentários em pt-br)
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};

/// Gera um token de refresh aleatório e opaco com 32 bytes (CSPRNG) em base64 URL safe sem padding.
pub fn gerar_refresh_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// Retorna o hash SHA-256 (hexadecimal minúsculo, 64 caracteres) de uma string.
/// Usado para indexar credenciais/identificadores no Redis sem expô-los em claro.
pub fn hash_sha256_hex(input: &str) -> String {
    Sha256::digest(input.as_bytes())
        .iter()
        .map(|b| format!("{:02x}", b))
        .collect()
}

/// Retorna o hash SHA-256 (hexadecimal minúsculo, 64 caracteres) do refresh token.
/// É este hash que é enviado e armazenado no Redis para segurança.
pub fn hash_refresh_token(token: &str) -> String {
    hash_sha256_hex(token)
}
