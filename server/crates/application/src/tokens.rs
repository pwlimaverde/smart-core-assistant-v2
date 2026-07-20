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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gerar_refresh_token_produz_valores_unicos_a_cada_chamada() {
        let t1 = gerar_refresh_token();
        let t2 = gerar_refresh_token();

        assert_ne!(t1, t2, "duas chamadas consecutivas não podem colidir");
    }

    #[test]
    fn gerar_refresh_token_tem_comprimento_esperado_para_32_bytes_base64() {
        let token = gerar_refresh_token();
        // 32 bytes em base64 URL-safe sem padding rendem 43 caracteres.
        assert_eq!(token.len(), 43);
        assert!(
            token
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'),
            "token deve usar apenas o alfabeto URL-safe"
        );
    }

    #[test]
    fn hash_sha256_hex_confere_com_vetor_conhecido() {
        // sha256("") — vetor de teste bem conhecido.
        assert_eq!(
            hash_sha256_hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn hash_sha256_hex_e_deterministico_e_minusculo() {
        let entrada = "valor_arbitrario_123";
        let h1 = hash_sha256_hex(entrada);
        let h2 = hash_sha256_hex(entrada);

        assert_eq!(h1, h2, "mesma entrada deve gerar o mesmo hash");
        assert_eq!(h1.len(), 64);
        assert!(h1
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }

    #[test]
    fn hash_sha256_hex_entradas_distintas_geram_hashes_distintos() {
        assert_ne!(hash_sha256_hex("a"), hash_sha256_hex("b"));
    }

    #[test]
    fn hash_refresh_token_delega_para_hash_sha256_hex() {
        let token = "refresh-token-de-exemplo";
        assert_eq!(hash_refresh_token(token), hash_sha256_hex(token));
    }
}
