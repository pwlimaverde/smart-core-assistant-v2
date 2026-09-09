//! Client ID Metadata Document (CIMD) — como o authorization server descobre
//! quem é o cliente MCP sem registro prévio.
//!
//! Na spec MCP, Dynamic Client Registration (RFC 7591) está deprecado: o
//! `client_id` **é** a URL de um documento JSON que o próprio cliente publica, e
//! é esse documento que declara o nome exibido e os `redirect_uris` válidos.
//!
//! # Isto é um fetch HTTP para uma URL que o atacante escolhe
//!
//! Todo o cuidado deste arquivo existe por causa dessa frase. Um AS ingênuo aqui
//! vira scanner de rede interna sob demanda: basta pedir autorização com
//! `client_id=http://10.0.0.5:6379/` e ler a diferença entre as mensagens de
//! erro. As defesas, todas obrigatórias e todas testadas:
//!
//! 1. **Só HTTPS.** Sem exceção para `localhost` — cliente que roda local não
//!    precisa publicar CIMD em `http://`.
//! 2. **Nenhum redirect seguido.** Não é "limite de saltos": é zero. Um 302 para
//!    `http://169.254.169.254/` contorna qualquer validação feita só na URL de
//!    entrada, e nenhum CIMD legítimo precisa redirecionar.
//! 3. **Todo IP resolvido é verificado** antes da conexão: loopback, privado,
//!    link-local (que inclui o `169.254.169.254` das nuvens), multicast e
//!    unspecified são recusados. Um nome que resolve para dois IPs, um público e
//!    um privado, é recusado inteiro.
//! 4. **Timeout curto e teto de corpo**, para que o endpoint não vire um dreno.
//! 5. **`client_id` idêntico à URL do documento.** Sem isso, qualquer um
//!    publicaria um documento afirmando ser outro cliente.
//!
//! # Limitação conhecida (registrada, não resolvida)
//!
//! A verificação de IP acontece na resolução do nome, e a conexão do `reqwest`
//! resolve de novo — há uma janela teórica de DNS rebinding entre as duas. Fechá-la
//! exigiria conectar a um IP fixado e mandar o SNI/Host à parte. O risco residual
//! é baixo (o atacante ganharia um GET cego, sem ler a resposta, contra um host
//! interno) e está registrado aqui em vez de silenciado.

use std::net::IpAddr;
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// Teto do corpo do documento. Um CIMD real tem centenas de bytes; 64 KiB é
/// folga de duas ordens de grandeza e ainda impede que um endpoint hostil
/// entregue um fluxo infinito.
const MAX_CORPO_BYTES: usize = 64 * 1024;
const TIMEOUT: Duration = Duration::from_secs(5);
/// TTL do cache. O documento é público e muda raramente; 10 min evita um fetch
/// por autorização sem tornar difícil corrigir um `redirect_uri` errado.
pub const CACHE_TTL_S: u64 = 600;
/// Tamanho máximo do `client_name` persistido. É texto de terceiro e vai para
/// uma tela: cortar aqui evita que um nome de 40 KB entre no banco.
const MAX_CLIENT_NAME: usize = 200;

// `Serialize` só existe para o cache no Redis (ver `store::cachear_cimd`): o
// documento validado é guardado como veio, para não revalidar a cada autorização.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClientMetadata {
    pub client_id: String,
    #[serde(default)]
    pub client_name: String,
    #[serde(default)]
    pub redirect_uris: Vec<String>,
    #[serde(default)]
    pub client_uri: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum CimdErro {
    #[error("client_id deve ser uma URL https absoluta")]
    UrlInvalida,
    #[error("client_id aponta para um endereço de rede não roteável publicamente")]
    DestinoProibido,
    #[error("não foi possível buscar o documento do cliente")]
    FalhaDeRede,
    #[error("o documento do cliente não é um JSON válido de metadados")]
    DocumentoInvalido,
    #[error("o client_id declarado no documento não corresponde à URL de onde ele veio")]
    ClientIdDivergente,
    #[error("o documento do cliente não declara nenhum redirect_uri")]
    SemRedirectUri,
}

impl CimdErro {
    /// Discriminante estável para log e auditoria (`oauth.cimd_rejeitado`).
    pub fn motivo(&self) -> &'static str {
        match self {
            Self::UrlInvalida => "url_invalida",
            Self::DestinoProibido => "destino_proibido",
            Self::FalhaDeRede => "falha_de_rede",
            Self::DocumentoInvalido => "documento_invalido",
            Self::ClientIdDivergente => "client_id_divergente",
            Self::SemRedirectUri => "sem_redirect_uri",
        }
    }
}

/// `true` quando o IP não deve ser alcançado a partir do AS.
pub fn ip_proibido(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_broadcast()
                || v4.is_multicast()
                || v4.is_unspecified()
                || v4.is_documentation()
                // 100.64.0.0/10 (CGNAT) e 192.0.0.0/24 (IETF) não têm predicado
                // estável na std; a rede do Docker cai em `is_private`, mas a
                // CGNAT aparece em algumas nuvens e vale recusar.
                || (v4.octets()[0] == 100 && (64..128).contains(&v4.octets()[1]))
                || (v4.octets()[0] == 192 && v4.octets()[1] == 0 && v4.octets()[2] == 0)
        }
        IpAddr::V6(v6) => {
            v6.is_loopback()
                || v6.is_multicast()
                || v6.is_unspecified()
                // fc00::/7 (unique local) e fe80::/10 (link local) não têm
                // predicado estável fora de nightly.
                || (v6.segments()[0] & 0xfe00) == 0xfc00
                || (v6.segments()[0] & 0xffc0) == 0xfe80
                // IPv4 mapeado: ::ffff:10.0.0.1 contornaria a checagem v4.
                || v6.to_ipv4_mapped().map(|v4| ip_proibido(&IpAddr::V4(v4))).unwrap_or(false)
        }
    }
}

/// Valida o esquema e o destino da URL **antes** de qualquer conexão.
fn validar_destino(url: &url::Url) -> Result<(), CimdErro> {
    if url.scheme() != "https" {
        return Err(CimdErro::UrlInvalida);
    }
    let host = url.host_str().ok_or(CimdErro::UrlInvalida)?;
    let porta = url.port_or_known_default().unwrap_or(443);

    // Um host que já é literal de IP nem chega ao resolvedor.
    if let Ok(ip) = host.parse::<IpAddr>() {
        return if ip_proibido(&ip) {
            Err(CimdErro::DestinoProibido)
        } else {
            Ok(())
        };
    }

    use std::net::ToSocketAddrs;
    let enderecos = (host, porta)
        .to_socket_addrs()
        .map_err(|_| CimdErro::FalhaDeRede)?
        .collect::<Vec<_>>();

    if enderecos.is_empty() {
        return Err(CimdErro::FalhaDeRede);
    }
    // Basta UM endereço proibido para recusar: um nome que resolve para público
    // e privado ao mesmo tempo é o padrão clássico de rebinding.
    if enderecos.iter().any(|addr| ip_proibido(&addr.ip())) {
        return Err(CimdErro::DestinoProibido);
    }
    Ok(())
}

/// Busca e valida o documento de metadados do cliente.
///
/// `client_id` é a URL; o retorno é o documento já validado e com o
/// `client_name` truncado no tamanho que o banco aceita.
#[tracing::instrument(skip_all, fields(cimd_host = tracing::field::Empty))]
pub async fn buscar(
    cliente_http: &reqwest::Client,
    client_id: &str,
) -> Result<ClientMetadata, CimdErro> {
    let url = url::Url::parse(client_id).map_err(|_| CimdErro::UrlInvalida)?;

    // O host entra no span de propósito: é ele que denuncia uma tentativa de
    // SSRF numa varredura de logs. A URL completa não entra (pode carregar
    // caminho arbitrário escolhido pelo atacante).
    if let Some(host) = url.host_str() {
        tracing::Span::current().record("cimd_host", host);
    }

    validar_destino(&url)?;

    let resposta = cliente_http
        .get(url.clone())
        .header(reqwest::header::ACCEPT, "application/json")
        .timeout(TIMEOUT)
        .send()
        .await
        .map_err(|_| CimdErro::FalhaDeRede)?;

    if !resposta.status().is_success() {
        return Err(CimdErro::FalhaDeRede);
    }

    // Lê com teto: `bytes()` sozinho aceitaria um corpo arbitrariamente grande.
    if let Some(tamanho) = resposta.content_length() {
        if tamanho as usize > MAX_CORPO_BYTES {
            return Err(CimdErro::DocumentoInvalido);
        }
    }
    let corpo = resposta.bytes().await.map_err(|_| CimdErro::FalhaDeRede)?;
    if corpo.len() > MAX_CORPO_BYTES {
        return Err(CimdErro::DocumentoInvalido);
    }

    let mut metadata: ClientMetadata =
        serde_json::from_slice(&corpo).map_err(|_| CimdErro::DocumentoInvalido)?;

    validar_documento(&mut metadata, client_id)?;
    Ok(metadata)
}

/// Regras aplicadas ao documento já desserializado. Separado de [`buscar`] para
/// ser testável sem rede.
pub fn validar_documento(
    metadata: &mut ClientMetadata,
    client_id_pedido: &str,
) -> Result<(), CimdErro> {
    if metadata.client_id != client_id_pedido {
        return Err(CimdErro::ClientIdDivergente);
    }
    if metadata.redirect_uris.is_empty() {
        return Err(CimdErro::SemRedirectUri);
    }
    // Só `https` ou `http://localhost` — a exceção de localhost existe para
    // clientes de desktop, que escutam numa porta efêmera da própria máquina.
    metadata
        .redirect_uris
        .retain(|uri| redirect_uri_aceitavel(uri));
    if metadata.redirect_uris.is_empty() {
        return Err(CimdErro::SemRedirectUri);
    }

    if metadata.client_name.trim().is_empty() {
        // Sem nome declarado, a tela mostra o host — melhor que "cliente
        // desconhecido", e é o host que o usuário precisa reconhecer de qualquer
        // forma.
        metadata.client_name = url::Url::parse(client_id_pedido)
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
            .unwrap_or_else(|| "Aplicativo".to_string());
    }
    metadata.client_name = metadata.client_name.chars().take(MAX_CLIENT_NAME).collect();
    Ok(())
}

/// `redirect_uri` aceitável: HTTPS em qualquer host, ou HTTP restrito a
/// loopback. Fragmentos são proibidos pelo OAuth 2.1.
pub fn redirect_uri_aceitavel(uri: &str) -> bool {
    let Ok(url) = url::Url::parse(uri) else {
        return false;
    };
    if url.fragment().is_some() {
        return false;
    }
    match url.scheme() {
        "https" => true,
        "http" => matches!(
            url.host_str(),
            Some("localhost") | Some("127.0.0.1") | Some("[::1]") | Some("::1")
        ),
        // Esquemas próprios de app (`claudeapp://`) não são aceitos na v1: não
        // dá para mostrar ao usuário um host que ele reconheça, e a spec pede
        // exatamente isso na tela de consentimento.
        _ => false,
    }
}

/// `true` quando **todos** os redirect_uris do cliente são de loopback.
///
/// A spec manda avisar com mais ênfase nesse caso: um cliente que só redireciona
/// para a própria máquina é, quase sempre, software rodando localmente — e é o
/// cenário em que um atacante convence a vítima a autorizar um "cliente" que na
/// verdade é o processo dele.
pub fn somente_localhost(metadata: &ClientMetadata) -> bool {
    metadata.redirect_uris.iter().all(|uri| {
        url::Url::parse(uri)
            .ok()
            .and_then(|u| {
                u.host_str()
                    .map(|h| matches!(h, "localhost" | "127.0.0.1" | "::1"))
            })
            .unwrap_or(false)
    })
}

/// Comparação por **igualdade exata**, como a spec exige. Nunca prefixo, nunca
/// curinga: `https://claude.ai/cb` e `https://claude.ai/cb/` são URIs
/// diferentes, e tratá-las como iguais abriria a porta para redirecionar o
/// código de autorização para um caminho que o cliente não declarou.
pub fn redirect_uri_declarado(metadata: &ClientMetadata, redirect_uri: &str) -> bool {
    metadata.redirect_uris.iter().any(|uri| uri == redirect_uri)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc(client_id: &str, redirects: &[&str]) -> ClientMetadata {
        ClientMetadata {
            client_id: client_id.to_string(),
            client_name: "Claude".to_string(),
            redirect_uris: redirects.iter().map(|s| s.to_string()).collect(),
            client_uri: None,
        }
    }

    // --- guarda anti-SSRF -------------------------------------------------

    #[test]
    fn recusa_loopback_ipv4() {
        assert!(ip_proibido(&"127.0.0.1".parse().unwrap()));
    }

    #[test]
    fn recusa_rede_privada() {
        assert!(ip_proibido(&"10.1.2.3".parse().unwrap()));
        assert!(ip_proibido(&"192.168.0.1".parse().unwrap()));
        assert!(ip_proibido(&"172.16.5.5".parse().unwrap()));
    }

    #[test]
    fn recusa_metadata_de_nuvem() {
        // 169.254.169.254 é o endpoint de credenciais de AWS/GCP/Azure. É o
        // alvo número um de SSRF e cai em link-local.
        assert!(ip_proibido(&"169.254.169.254".parse().unwrap()));
    }

    #[test]
    fn recusa_cgnat() {
        assert!(ip_proibido(&"100.64.0.1".parse().unwrap()));
    }

    #[test]
    fn recusa_ipv4_mapeado_em_ipv6() {
        // ::ffff:10.0.0.1 contornaria uma checagem que só olhasse a família v6.
        assert!(ip_proibido(&"::ffff:10.0.0.1".parse().unwrap()));
    }

    #[test]
    fn recusa_unique_local_e_link_local_ipv6() {
        assert!(ip_proibido(&"fc00::1".parse().unwrap()));
        assert!(ip_proibido(&"fe80::1".parse().unwrap()));
        assert!(ip_proibido(&"::1".parse().unwrap()));
    }

    #[test]
    fn aceita_ip_publico() {
        assert!(!ip_proibido(&"1.1.1.1".parse().unwrap()));
        assert!(!ip_proibido(&"2606:4700:4700::1111".parse().unwrap()));
    }

    #[test]
    fn recusa_http_mesmo_para_host_publico() {
        let url = url::Url::parse("http://claude.ai/mcp-client").unwrap();
        assert!(matches!(validar_destino(&url), Err(CimdErro::UrlInvalida)));
    }

    #[test]
    fn recusa_https_apontando_para_ip_privado_literal() {
        let url = url::Url::parse("https://10.0.0.5/mcp").unwrap();
        assert!(matches!(
            validar_destino(&url),
            Err(CimdErro::DestinoProibido)
        ));
    }

    // --- validação do documento ------------------------------------------

    #[test]
    fn recusa_client_id_divergente_da_url() {
        let mut d = doc("https://outro.example/cliente", &["https://claude.ai/cb"]);
        assert!(matches!(
            validar_documento(&mut d, "https://claude.ai/mcp-client"),
            Err(CimdErro::ClientIdDivergente)
        ));
    }

    #[test]
    fn recusa_documento_sem_redirect_uri() {
        let mut d = doc("https://claude.ai/mcp-client", &[]);
        assert!(matches!(
            validar_documento(&mut d, "https://claude.ai/mcp-client"),
            Err(CimdErro::SemRedirectUri)
        ));
    }

    #[test]
    fn descarta_redirect_uri_de_esquema_proibido_e_recusa_se_sobrar_nenhum() {
        let mut d = doc("https://claude.ai/mcp-client", &["claudeapp://callback"]);
        assert!(matches!(
            validar_documento(&mut d, "https://claude.ai/mcp-client"),
            Err(CimdErro::SemRedirectUri)
        ));
    }

    #[test]
    fn aceita_http_apenas_em_loopback() {
        assert!(redirect_uri_aceitavel("http://localhost:8080/cb"));
        assert!(redirect_uri_aceitavel("http://127.0.0.1:8080/cb"));
        assert!(!redirect_uri_aceitavel("http://claude.ai/cb"));
    }

    #[test]
    fn recusa_redirect_uri_com_fragmento() {
        assert!(!redirect_uri_aceitavel("https://claude.ai/cb#x"));
    }

    #[test]
    fn nome_vazio_vira_o_host_do_client_id() {
        let mut d = ClientMetadata {
            client_id: "https://claude.ai/mcp-client".to_string(),
            client_name: "   ".to_string(),
            redirect_uris: vec!["https://claude.ai/cb".to_string()],
            client_uri: None,
        };
        validar_documento(&mut d, "https://claude.ai/mcp-client").unwrap();
        assert_eq!(d.client_name, "claude.ai");
    }

    #[test]
    fn nome_gigante_e_truncado_antes_de_chegar_ao_banco() {
        let mut d = ClientMetadata {
            client_id: "https://claude.ai/mcp-client".to_string(),
            client_name: "A".repeat(10_000),
            redirect_uris: vec!["https://claude.ai/cb".to_string()],
            client_uri: None,
        };
        validar_documento(&mut d, "https://claude.ai/mcp-client").unwrap();
        assert_eq!(d.client_name.chars().count(), MAX_CLIENT_NAME);
    }

    // --- redirect_uri ------------------------------------------------------

    #[test]
    fn redirect_uri_e_comparado_por_igualdade_exata() {
        let d = doc("https://claude.ai/mcp-client", &["https://claude.ai/cb"]);
        assert!(redirect_uri_declarado(&d, "https://claude.ai/cb"));
        // Uma barra a mais é outra URI. Nada de prefixo.
        assert!(!redirect_uri_declarado(&d, "https://claude.ai/cb/"));
        assert!(!redirect_uri_declarado(&d, "https://claude.ai/cb?x=1"));
        assert!(!redirect_uri_declarado(&d, "https://claude.ai/cbb"));
    }

    #[test]
    fn detecta_cliente_somente_localhost() {
        assert!(somente_localhost(&doc(
            "https://x/y",
            &["http://localhost:1/cb"]
        )));
        assert!(!somente_localhost(&doc(
            "https://x/y",
            &["http://localhost:1/cb", "https://claude.ai/cb"]
        )));
    }
}
