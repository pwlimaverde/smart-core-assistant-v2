//! Emissão e validação dos dois tokens do fluxo MCP.
//!
//! # Por que são dois, e por que assinados de formas diferentes
//!
//! **Access token do cliente MCP** — assinado em **RS256** com uma chave privada
//! que só o `control_plane` tem. O `mcp_server` valida com a chave *pública*.
//! Isso não é preciosismo: com HMAC, o resource server precisaria do mesmo
//! segredo que assina, e um `mcp_server` comprometido poderia **cunhar** tokens
//! para qualquer tenant. Com assinatura assimétrica ele só consegue conferir os
//! que recebe. O `mcp_server` é o componente exposto à internet e o que executa
//! entrada de terceiros — é exatamente ele que não pode ter poder de emissão.
//!
//! **JWT interno** — assinado em HS256 com o `JWT_SECRET` que o `runtime_api` já
//! valida, com vida curta. É o que o `mcp_server` apresenta ao backend depois de
//! trocar o token do cliente. A spec é literal quanto a isto: *"The MCP server
//! MUST NOT pass through the token it received from the MCP client."*
//!
//! O refresh token não é JWT: é 256 bits de CSPRNG prefixados pelo `grant_id`,
//! porque o AS precisa saber qual linha buscar antes de comparar o hash.

use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Claims do access token entregue ao cliente MCP.
///
/// `aud` é o que amarra o token a este resource server (RFC 8707): um token
/// emitido para outro `resource` é recusado pelo `mcp_server` sem discussão. Sem
/// essa amarra, um token vazado de qualquer serviço nosso valeria no MCP.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpAccessClaims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: usize,
    pub iat: usize,
    pub jti: String,
    pub tenant_id: String,
    pub scopes: Vec<String>,
    pub grant_id: String,
    /// `client_id` do cliente MCP (a URL do CIMD). Vai no token para que a
    /// auditoria do lado do `mcp_server` saiba qual aplicativo agiu, sem uma
    /// consulta a mais.
    pub client_id: String,
}

#[derive(Debug, thiserror::Error)]
pub enum TokenErro {
    #[error("chave de assinatura do MCP ausente ou inválida")]
    ChaveInvalida,
    #[error("falha ao emitir token")]
    FalhaEmissao,
}

/// Par de chaves do access token. A privada assina; a pública é distribuída ao
/// `mcp_server` por configuração.
pub struct ChavesMcp {
    privada: EncodingKey,
    publica: DecodingKey,
}

impl ChavesMcp {
    /// Carrega o par a partir dos PEMs de RSA (PKCS#8/PKCS#1).
    ///
    /// Gerar em produção:
    /// ```text
    /// openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out mcp_oauth_key.pem
    /// openssl rsa -in mcp_oauth_key.pem -pubout -out mcp_oauth_key.pub.pem
    /// ```
    pub fn carregar(pem_privado: &str, pem_publico: &str) -> Result<Self, TokenErro> {
        let privada = EncodingKey::from_rsa_pem(pem_privado.as_bytes())
            .map_err(|_| TokenErro::ChaveInvalida)?;
        let publica = DecodingKey::from_rsa_pem(pem_publico.as_bytes())
            .map_err(|_| TokenErro::ChaveInvalida)?;
        Ok(Self { privada, publica })
    }
}

/// Emite o access token do cliente MCP.
#[allow(clippy::too_many_arguments)]
pub fn emitir_access_token(
    chaves: &ChavesMcp,
    issuer: &str,
    resource: &str,
    user_id: i32,
    tenant_id: Uuid,
    grant_id: Uuid,
    client_id: &str,
    escopos: &[String],
    ttl_s: i64,
) -> Result<(String, McpAccessClaims), TokenErro> {
    let agora = chrono::Utc::now().timestamp() as usize;
    let claims = McpAccessClaims {
        iss: issuer.to_string(),
        sub: user_id.to_string(),
        aud: resource.to_string(),
        exp: agora + ttl_s as usize,
        iat: agora,
        jti: Uuid::now_v7().to_string(),
        tenant_id: tenant_id.to_string(),
        scopes: escopos.to_vec(),
        grant_id: grant_id.to_string(),
        client_id: client_id.to_string(),
    };
    let token = jsonwebtoken::encode(&Header::new(Algorithm::RS256), &claims, &chaves.privada)
        .map_err(|_| TokenErro::FalhaEmissao)?;
    Ok((token, claims))
}

/// Valida um access token MCP: assinatura, `iss`, `exp` e **`aud`**.
///
/// Existe do lado Rust para o endpoint de troca interna — o `mcp_server` faz a
/// mesma validação em Python, com a chave pública. Os dois validam a audiência;
/// nenhum dos dois aceita token de audiência alheia "porque a assinatura confere".
pub fn validar_access_token(
    chaves: &ChavesMcp,
    token: &str,
    issuer: &str,
    resource: &str,
) -> Result<McpAccessClaims, TokenErro> {
    let mut validacao = Validation::new(Algorithm::RS256);
    validacao.set_issuer(&[issuer]);
    validacao.set_audience(&[resource]);
    validacao.validate_exp = true;

    jsonwebtoken::decode::<McpAccessClaims>(token, &chaves.publica, &validacao)
        .map(|d| d.claims)
        .map_err(|_| TokenErro::ChaveInvalida)
}

/// Emite o JWT **interno**, o único que o `runtime_api` aceita.
///
/// Vida curta de propósito: ele existe para durar uma chamada. Se vazar do
/// `mcp_server`, o alcance é de minutos e não de horas.
pub fn emitir_token_interno(
    user_id: i32,
    tenant_id: Uuid,
    is_superuser: bool,
    escopos: &[String],
    ttl_s: i64,
) -> Result<String, error_core::AppError> {
    let agora = chrono::Utc::now().timestamp() as usize;
    let claims = application::jwt::Claims {
        sub: user_id.to_string(),
        tenant_id: if is_superuser {
            String::new()
        } else {
            tenant_id.to_string()
        },
        scopes: escopos.to_vec(),
        is_superuser,
        jti: Uuid::now_v7().to_string(),
        iat: agora,
        exp: agora + ttl_s as usize,
    };
    application::jwt::gerar_access_token(&claims)
}

/// Refresh token opaco no formato `<grant_id>.<segredo>`.
///
/// O `grant_id` em claro não é vazamento: ele é um UUID sem significado fora do
/// banco, e o que autentica é o segredo. Em troca, o AS localiza a linha certa
/// com uma consulta indexada em vez de comparar hashes contra a tabela inteira —
/// que é o que aconteceria com um token totalmente opaco.
pub fn gerar_refresh_token(grant_id: Uuid) -> String {
    format!("{}.{}", grant_id, application::tokens::gerar_refresh_token())
}

/// Separa o refresh token nas suas duas partes. `None` para qualquer formato
/// inesperado — não há mensagem de erro específica, para não ensinar o formato a
/// quem está sondando.
pub fn partir_refresh_token(token: &str) -> Option<(Uuid, String)> {
    let (grant, segredo) = token.split_once('.')?;
    if segredo.is_empty() {
        return None;
    }
    let grant_id = Uuid::parse_str(grant).ok()?;
    Some((grant_id, segredo.to_string()))
}

/// Hash guardado no grant. SHA-256, não argon2id — ver a justificativa na
/// migration `0030`: o segredo tem 256 bits de entropia de CSPRNG.
pub fn hash_refresh(segredo: &str) -> String {
    application::tokens::hash_sha256_hex(segredo)
}

/// Comparação em tempo constante do hash apresentado contra o guardado.
///
/// Os dois são hex de 64 caracteres, então o vazamento por tempo de uma
/// comparação ingênua é pequeno — mas "pequeno" não é argumento para escrever
/// `==` num caminho de autenticação.
pub fn hash_confere(esperado: &str, apresentado: &str) -> bool {
    use subtle::ConstantTimeEq;
    let a = esperado.as_bytes();
    let b = apresentado.as_bytes();
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
}

/// Verificação PKCE S256: `BASE64URL(SHA256(code_verifier)) == code_challenge`.
///
/// `plain` não é aceito. A spec OAuth 2.1 permite só S256 para clientes
/// públicos, e publicamos `code_challenge_methods_supported: ["S256"]` — aceitar
/// `plain` aqui tornaria a metadata mentirosa e a proteção decorativa.
pub fn pkce_confere(code_verifier: &str, code_challenge: &str) -> bool {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    use sha2::{Digest, Sha256};

    // RFC 7636 §4.1: o verifier tem entre 43 e 128 caracteres.
    if !(43..=128).contains(&code_verifier.len()) {
        return false;
    }
    let digest = Sha256::digest(code_verifier.as_bytes());
    let calculado = URL_SAFE_NO_PAD.encode(digest);
    hash_confere(&calculado, code_challenge)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_aceita_o_par_correto() {
        // Vetor do RFC 7636 apêndice B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
        assert!(pkce_confere(verifier, challenge));
    }

    #[test]
    fn pkce_recusa_verifier_errado() {
        let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
        assert!(!pkce_confere(
            "outroVerifierComTamanhoSuficienteParaPassar123",
            challenge
        ));
    }

    #[test]
    fn pkce_recusa_verifier_curto_demais() {
        // Um verifier de 10 caracteres não tem entropia; a RFC exige 43+.
        assert!(!pkce_confere("curtinho12", "qualquer"));
    }

    #[test]
    fn pkce_recusa_modo_plain_disfarcado() {
        // Cliente que mandasse o verifier como challenge (o que `plain` faria)
        // não passa: comparamos contra o SHA-256, sempre.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        assert!(!pkce_confere(verifier, verifier));
    }

    #[test]
    fn refresh_token_carrega_o_grant_e_volta_intacto() {
        let grant = Uuid::now_v7();
        let token = gerar_refresh_token(grant);
        let (lido, segredo) = partir_refresh_token(&token).unwrap();
        assert_eq!(lido, grant);
        assert_eq!(segredo.len(), 43);
    }

    #[test]
    fn refresh_token_malformado_nao_e_aceito() {
        assert!(partir_refresh_token("semponto").is_none());
        assert!(partir_refresh_token("nao-uuid.segredo").is_none());
        assert!(partir_refresh_token(&format!("{}.", Uuid::now_v7())).is_none());
    }

    #[test]
    fn hash_confere_e_falso_para_tamanhos_diferentes() {
        assert!(!hash_confere("abc", "abcd"));
        assert!(hash_confere("abc", "abc"));
    }

    #[test]
    fn hash_do_refresh_e_estavel_e_nao_devolve_o_segredo() {
        let h = hash_refresh("segredo-qualquer");
        assert_eq!(h.len(), 64);
        assert_eq!(h, hash_refresh("segredo-qualquer"));
        assert!(!h.contains("segredo"));
    }
}
