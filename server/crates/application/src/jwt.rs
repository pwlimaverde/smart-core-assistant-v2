// application/src/jwt.rs (comentários em pt-br)
use error_core::AppError;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

static ENCODING_KEY: OnceLock<EncodingKey> = OnceLock::new();
static DECODING_KEY: OnceLock<DecodingKey> = OnceLock::new();

/// Claims do access token (doc 09 §6.1). `tenant_id` vazio/nil = superusuário (contexto global).
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,         // auth_user.id como string
    pub tenant_id: String,   // UUID ou "" para superusuário
    pub scopes: Vec<String>, // catálogo canônico de escopos
    pub is_superuser: bool,
    pub jti: String, // UUID v7 — blocklist no logout
    pub iat: usize,
    pub exp: usize,
}

/// Inicializa as chaves HMAC a partir do JWT_SECRET (uma vez no boot da runtime_api).
pub fn inicializar_chaves(secret: &str) -> Result<(), AppError> {
    if secret.len() < 32 {
        return Err(AppError::Internal(
            "JWT_SECRET deve ter ao menos 32 bytes".into(),
        ));
    }
    // Set retorna Ok(()) se o valor foi definido, senão Err(value). Ignoramos se já definido.
    let _ = ENCODING_KEY.set(EncodingKey::from_secret(secret.as_bytes()));
    let _ = DECODING_KEY.set(DecodingKey::from_secret(secret.as_bytes()));
    Ok(())
}

/// Gera um access token assinado com HS256 a partir das claims informadas.
pub fn gerar_access_token(claims: &Claims) -> Result<String, AppError> {
    let key = ENCODING_KEY
        .get()
        .ok_or_else(|| AppError::Internal("chaves JWT não inicializadas".into()))?;
    encode(&Header::new(Algorithm::HS256), claims, key)
        .map_err(|e| AppError::Auth(format!("falha ao emitir token: {e}")))
}

/// Valida assinatura e expiração do access token informado.
pub fn validar_access_token(token: &str) -> Result<Claims, AppError> {
    let key = DECODING_KEY
        .get()
        .ok_or_else(|| AppError::Internal("chaves JWT não inicializadas".into()))?;
    let validation = Validation::new(Algorithm::HS256);
    decode::<Claims>(token, key, &validation)
        .map(|d| d.claims)
        .map_err(|e| AppError::Auth(format!("token inválido ou expirado: {e}")))
}
