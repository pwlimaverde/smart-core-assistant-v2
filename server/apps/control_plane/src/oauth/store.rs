//! Estado efêmero do fluxo OAuth: o "ticket" que atravessa login e
//! consentimento, o código de autorização e o cache do CIMD.
//!
//! Tudo vive no Redis, nada no Postgres. O que fica no banco é o **grant** — o
//! consentimento duradouro. Aqui só mora o que expira em segundos.
//!
//! # Por que este arquivo fala com o Redis direto, sem passar pelo `data_redis`
//!
//! A convenção da casa é que os serviços de aplicação alcancem o Redis pela
//! porta `data_redis`. A exceção aqui é deliberada e tem um motivo só: o consumo
//! do código de autorização precisa ser **atômico e de uso único**, e a garantia
//! vem do `GETDEL` do próprio Redis. Encapsulá-lo numa RPC acrescentaria um salto
//! de rede exatamente na operação mais sensível do fluxo sem acrescentar uma
//! garantia — e criaria a tentação de, um dia, implementar o "GETDEL" como
//! GET seguido de DEL do outro lado, que é a falha clássica de replay de código.
//! O `control_plane` já mantém uma conexão Redis própria (o stream de auditoria),
//! então nenhuma dependência nova entra por isso.
//!
//! Requer Redis 6.2+ (`GETDEL`). A stack roda 7.x.

use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// TTL do ticket que carrega a requisição de autorização entre as telas de login
/// e consentimento. 10 minutos: tempo de alguém digitar a senha com calma, não
/// tempo de deixar a aba aberta a tarde inteira.
const TICKET_TTL_S: u64 = 600;

/// TTL do código de autorização. A spec pede "curto"; a RFC 6749 sugere no
/// máximo 10 min e recomenda 1 min. O cliente troca o código imediatamente após
/// o redirect, então 60s é folgado.
const CODIGO_TTL_S: u64 = 60;

/// A requisição de autorização, congelada no momento em que chegou.
///
/// Ela viaja por um identificador opaco (o ticket) em vez de por campos ocultos
/// no formulário. A diferença importa: com campos ocultos, o `redirect_uri` e os
/// escopos seriam reenviados pelo navegador e poderiam ser adulterados entre a
/// validação e o consentimento. Com ticket, o que foi validado é o que é usado.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequisicaoAutorizacao {
    pub client_id: String,
    pub client_name: String,
    pub redirect_uri: String,
    pub state: Option<String>,
    pub code_challenge: String,
    pub resource: String,
    pub escopos_pedidos: Vec<String>,
    pub somente_localhost: bool,
    /// Preenchido depois do login; `None` enquanto o ticket ainda é anônimo.
    pub usuario: Option<UsuarioDoTicket>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsuarioDoTicket {
    pub user_id: i32,
    pub tenant_id: Uuid,
    /// Escopos que o usuário possui **hoje**. Congelados no ticket só para
    /// montar a tela; a interseção que vale é refeita a cada emissão de token.
    pub escopos: Vec<String>,
}

/// O código de autorização, com tudo a que ele está amarrado.
///
/// Amarrar o código ao `code_challenge`, ao `redirect_uri` e ao `resource` é o
/// que impede três ataques distintos: código interceptado sem o verifier,
/// código entregue num redirect que não é o do cliente, e código emitido para um
/// recurso e usado em outro.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodigoAutorizacao {
    pub grant_id: Uuid,
    pub user_id: i32,
    pub tenant_id: Uuid,
    pub client_id: String,
    pub redirect_uri: String,
    pub code_challenge: String,
    pub resource: String,
    pub escopos: Vec<String>,
}

fn chave_ticket(ticket: &str) -> String {
    format!("mcp:oauth:ticket:{ticket}")
}

fn chave_codigo(codigo: &str) -> String {
    format!("mcp:oauth:code:{codigo}")
}

fn chave_cimd(client_id: &str) -> String {
    // O `client_id` é uma URL de terceiro: entra na chave como hash, para não
    // permitir que ele injete separadores no espaço de nomes do Redis.
    format!(
        "mcp:oauth:cimd:{}",
        application::tokens::hash_sha256_hex(client_id)
    )
}

/// Identificador opaco de 256 bits. Serve para ticket e para código de
/// autorização — os dois precisam ser impossíveis de adivinhar.
pub fn novo_identificador() -> String {
    application::tokens::gerar_refresh_token()
}

pub async fn gravar_ticket(
    redis: &mut redis::aio::ConnectionManager,
    ticket: &str,
    req: &RequisicaoAutorizacao,
) -> redis::RedisResult<()> {
    let json = serde_json::to_string(req).unwrap_or_default();
    redis
        .set_ex::<_, _, ()>(chave_ticket(ticket), json, TICKET_TTL_S)
        .await
}

pub async fn ler_ticket(
    redis: &mut redis::aio::ConnectionManager,
    ticket: &str,
) -> Option<RequisicaoAutorizacao> {
    let json: Option<String> = redis.get(chave_ticket(ticket)).await.ok().flatten();
    json.and_then(|j| serde_json::from_str(&j).ok())
}

pub async fn consumir_ticket(
    redis: &mut redis::aio::ConnectionManager,
    ticket: &str,
) -> Option<RequisicaoAutorizacao> {
    let json: Option<String> = redis::cmd("GETDEL")
        .arg(chave_ticket(ticket))
        .query_async(redis)
        .await
        .ok()
        .flatten();
    json.and_then(|j| serde_json::from_str(&j).ok())
}

pub async fn gravar_codigo(
    redis: &mut redis::aio::ConnectionManager,
    codigo: &str,
    dados: &CodigoAutorizacao,
) -> redis::RedisResult<()> {
    let json = serde_json::to_string(dados).unwrap_or_default();
    redis
        .set_ex::<_, _, ()>(chave_codigo(codigo), json, CODIGO_TTL_S)
        .await
}

/// Consome o código de autorização — **uma única vez**.
///
/// `GETDEL` é o ponto inteiro da função: ele lê e apaga na mesma operação, do
/// lado do servidor. Duas trocas concorrentes do mesmo código produzem um
/// sucesso e um `None`, sem janela entre a leitura e a remoção. Um `GET` seguido
/// de `DEL` teria essa janela, e é assim que códigos são replayados.
pub async fn consumir_codigo(
    redis: &mut redis::aio::ConnectionManager,
    codigo: &str,
) -> Option<CodigoAutorizacao> {
    let json: Option<String> = redis::cmd("GETDEL")
        .arg(chave_codigo(codigo))
        .query_async(redis)
        .await
        .ok()
        .flatten();
    json.and_then(|j| serde_json::from_str(&j).ok())
}

pub async fn cimd_do_cache(
    redis: &mut redis::aio::ConnectionManager,
    client_id: &str,
) -> Option<super::cimd::ClientMetadata> {
    let json: Option<String> = redis.get(chave_cimd(client_id)).await.ok().flatten();
    json.and_then(|j| serde_json::from_str(&j).ok())
}

pub async fn cachear_cimd(
    redis: &mut redis::aio::ConnectionManager,
    client_id: &str,
    metadata: &super::cimd::ClientMetadata,
) {
    let json = serde_json::to_string(metadata).unwrap_or_default();
    let _ = redis
        .set_ex::<_, _, ()>(chave_cimd(client_id), json, super::cimd::CACHE_TTL_S)
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identificadores_sao_unicos_e_url_safe() {
        let a = novo_identificador();
        let b = novo_identificador();
        assert_ne!(a, b);
        assert!(a
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
    }

    #[test]
    fn chave_do_cimd_nao_carrega_a_url_do_terceiro() {
        // Um client_id com ':' ou '*' não pode virar padrão de chave no Redis.
        let chave = chave_cimd("https://mau.example/x:*:y");
        assert!(!chave.contains("mau.example"));
        assert!(chave.starts_with("mcp:oauth:cimd:"));
        // sha256 hex tem 64 caracteres.
        assert_eq!(chave.len(), "mcp:oauth:cimd:".len() + 64);
    }

    #[test]
    fn chaves_de_ticket_e_codigo_vivem_em_espacos_separados() {
        // Um ticket nunca pode ser aceito como código: espaços de nome
        // diferentes garantem isso mesmo se os identificadores colidirem.
        assert_ne!(chave_ticket("x"), chave_codigo("x"));
    }

    #[test]
    fn requisicao_serializa_e_volta_intacta() {
        let req = RequisicaoAutorizacao {
            client_id: "https://claude.ai/mcp-client".to_string(),
            client_name: "Claude".to_string(),
            redirect_uri: "https://claude.ai/cb".to_string(),
            state: Some("abc".to_string()),
            code_challenge: "desafio".to_string(),
            resource: "https://mcp.smartcoreassistant.com.br".to_string(),
            escopos_pedidos: vec!["atendimentos:read".to_string()],
            somente_localhost: false,
            usuario: Some(UsuarioDoTicket {
                user_id: 7,
                tenant_id: Uuid::nil(),
                escopos: vec!["atendimentos:read".to_string()],
            }),
        };
        let json = serde_json::to_string(&req).unwrap();
        let volta: RequisicaoAutorizacao = serde_json::from_str(&json).unwrap();
        assert_eq!(volta.client_id, req.client_id);
        assert_eq!(volta.usuario.unwrap().user_id, 7);
    }
}
