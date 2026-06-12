use application::jwt::{gerar_access_token, inicializar_chaves, validar_access_token, Claims};
use error_core::AppError;

#[test]
fn test_inicializar_chaves_muito_curto_retorna_erro() {
    let resultado = inicializar_chaves("curto");
    assert!(resultado.is_err());
    if let Err(AppError::Internal(msg)) = resultado {
        assert!(msg.contains("JWT_SECRET deve ter ao menos 32 bytes"));
    } else {
        panic!("Deveria retornar AppError::Internal");
    }
}

#[test]
fn test_inicializar_chaves_correto_sucesso() {
    let resultado = inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo_jwt");
    assert!(resultado.is_ok());
}

#[test]
fn test_gerar_e_validar_token_fluxo_feliz() {
    let _ = inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo_jwt");

    let claims = Claims {
        sub: "123".to_string(),
        tenant_id: "tenant-abc".to_string(),
        scopes: vec!["atendimentos:read".to_string()],
        is_superuser: false,
        jti: "jti-123".to_string(),
        iat: chrono::Utc::now().timestamp() as usize,
        exp: (chrono::Utc::now().timestamp() + 3600) as usize,
    };

    let token_res = gerar_access_token(&claims);
    assert!(
        token_res.is_ok(),
        "Erro ao gerar token: {:?}",
        token_res.err()
    );
    let token = token_res.unwrap();

    let validar_res = validar_access_token(&token);
    assert!(
        validar_res.is_ok(),
        "Erro ao validar token: {:?}",
        validar_res.err()
    );
    let claims_validadas = validar_res.unwrap();

    assert_eq!(claims_validadas.sub, "123");
    assert_eq!(claims_validadas.tenant_id, "tenant-abc");
    assert_eq!(
        claims_validadas.scopes,
        vec!["atendimentos:read".to_string()]
    );
    assert!(!claims_validadas.is_superuser);
    assert_eq!(claims_validadas.jti, "jti-123");
}

#[test]
fn test_validar_token_invalido_retorna_erro() {
    let _ = inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo_jwt");
    let resultado = validar_access_token("token.invalido.assinadoerrado");
    assert!(resultado.is_err());
    if let Err(AppError::Auth(msg)) = resultado {
        assert!(msg.contains("token inválido ou expirado"));
    } else {
        panic!("Deveria retornar AppError::Auth");
    }
}

#[test]
fn test_validar_token_expirado_retorna_erro() {
    let _ = inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo_jwt");

    let claims_expiradas = Claims {
        sub: "123".to_string(),
        tenant_id: "tenant-abc".to_string(),
        scopes: vec![],
        is_superuser: false,
        jti: "jti-expired".to_string(),
        iat: (chrono::Utc::now().timestamp() - 200) as usize,
        exp: (chrono::Utc::now().timestamp() - 120) as usize, // já expirado (além do leeway de 60s)
    };

    let token = gerar_access_token(&claims_expiradas).unwrap();
    let resultado = validar_access_token(&token);
    assert!(resultado.is_err());
    if let Err(AppError::Auth(msg)) = resultado {
        assert!(msg.contains("token inválido ou expirado"));
    } else {
        panic!("Deveria retornar AppError::Auth");
    }
}
