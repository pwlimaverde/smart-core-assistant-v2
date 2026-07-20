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

#[cfg(test)]
mod tests {
    use super::*;

    /// Segredo válido (>= 32 bytes) reutilizado pelos testes; `inicializar_chaves`
    /// é idempotente (ignora chamadas repetidas), então é seguro chamar em cada teste.
    const SEGREDO: &str = "segredo_de_teste_com_pelo_menos_32_bytes_util";

    fn claims_validas(ttl_s: i64) -> Claims {
        let agora = chrono::Utc::now().timestamp() as usize;
        Claims {
            sub: "42".to_string(),
            tenant_id: "tenant-xyz".to_string(),
            scopes: vec!["atendimentos:read".to_string()],
            is_superuser: false,
            jti: "jti-teste".to_string(),
            iat: agora,
            exp: (agora as i64 + ttl_s) as usize,
        }
    }

    #[test]
    fn inicializar_chaves_rejeita_segredo_menor_que_32_bytes() {
        let resultado = inicializar_chaves("curto_demais");
        let err = resultado.unwrap_err();
        assert!(matches!(err, AppError::Internal(msg) if msg.contains("32 bytes")));
    }

    #[test]
    fn inicializar_chaves_aceita_segredo_de_32_bytes_ou_mais() {
        assert!(inicializar_chaves(SEGREDO).is_ok());
    }

    #[test]
    fn inicializar_chaves_e_idempotente_em_chamadas_repetidas() {
        // A segunda chamada não deve falhar nem sobrescrever silenciosamente
        // um estado inválido — o `let _ =` no código de produção ignora o Err
        // de "já definido" do OnceLock.
        assert!(inicializar_chaves(SEGREDO).is_ok());
        assert!(inicializar_chaves(SEGREDO).is_ok());
    }

    #[test]
    fn gerar_e_validar_token_fluxo_feliz_preserva_claims() {
        let _ = inicializar_chaves(SEGREDO);
        let claims = claims_validas(3600);

        let token = gerar_access_token(&claims).expect("deveria gerar o token");
        let validadas = validar_access_token(&token).expect("deveria validar o token");

        assert_eq!(validadas.sub, claims.sub);
        assert_eq!(validadas.tenant_id, claims.tenant_id);
        assert_eq!(validadas.scopes, claims.scopes);
        assert_eq!(validadas.is_superuser, claims.is_superuser);
        assert_eq!(validadas.jti, claims.jti);
    }

    #[test]
    fn validar_token_com_assinatura_adulterada_retorna_erro_auth() {
        let _ = inicializar_chaves(SEGREDO);
        let claims = claims_validas(3600);
        let mut token = gerar_access_token(&claims).unwrap();
        // Adultera o último caractere da assinatura para invalidar o HMAC.
        token.pop();
        token.push(if token.ends_with('A') { 'B' } else { 'A' });

        let err = validar_access_token(&token).unwrap_err();
        assert!(matches!(err, AppError::Auth(msg) if msg.contains("token inválido ou expirado")));
    }

    #[test]
    fn validar_token_malformado_retorna_erro_auth() {
        let _ = inicializar_chaves(SEGREDO);
        let err = validar_access_token("nao.e.um-jwt-valido").unwrap_err();
        assert!(matches!(err, AppError::Auth(_)));
    }

    #[test]
    fn validar_token_expirado_retorna_erro_auth() {
        let _ = inicializar_chaves(SEGREDO);
        // TTL negativo: `exp` já ficou no passado além do leeway padrão da lib.
        let claims = claims_validas(-120);
        let token = gerar_access_token(&claims).unwrap();

        let err = validar_access_token(&token).unwrap_err();
        assert!(matches!(err, AppError::Auth(msg) if msg.contains("token inválido ou expirado")));
    }

    #[test]
    fn claims_de_superusuario_serializam_tenant_id_vazio() {
        let _ = inicializar_chaves(SEGREDO);
        let mut claims = claims_validas(3600);
        claims.tenant_id = String::new();
        claims.is_superuser = true;
        claims.scopes = vec!["*".to_string()];

        let token = gerar_access_token(&claims).unwrap();
        let validadas = validar_access_token(&token).unwrap();

        assert!(validadas.is_superuser);
        assert_eq!(validadas.tenant_id, "");
        assert_eq!(validadas.scopes, vec!["*".to_string()]);
    }
}
