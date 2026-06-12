use application::tokens::{gerar_refresh_token, hash_refresh_token};

#[test]
fn test_gerar_refresh_token_comportamento() {
    let t1 = gerar_refresh_token();
    let t2 = gerar_refresh_token();

    assert!(!t1.is_empty(), "Token não deveria ser vazio");
    assert!(!t2.is_empty(), "Token não deveria ser vazio");
    assert_ne!(t1, t2, "Tokens gerados consecutivamente devem ser únicos");

    // 32 bytes em base64 URL safe sem padding deve ter ~43 caracteres
    assert!(
        t1.len() >= 40 && t1.len() <= 45,
        "Comprimento inesperado: {}",
        t1.len()
    );
}

#[test]
fn test_hash_refresh_token_consistencia() {
    let token = "meu_refresh_token_secreto_123";
    let hash1 = hash_refresh_token(token);
    let hash2 = hash_refresh_token(token);

    assert_eq!(
        hash1, hash2,
        "Hashes para o mesmo token devem ser idênticos"
    );
    assert_eq!(hash1.len(), 64, "SHA-256 em hex deve ter 64 caracteres");

    // O hash deve conter apenas caracteres hexadecimais minúsculos
    assert!(
        hash1
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_uppercase()),
        "Hash deve ser hexadecimal minúsculo"
    );
}
