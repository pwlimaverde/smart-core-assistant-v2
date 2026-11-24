//! Intermediário de webhooks de provedores (ADR `adr-intermediario-webhooks-provedores.md`).
//!
//! Recebe o webhook nativo do provedor (hoje o Evolution Go) e o repassa ao
//! `webhook_ingress` do ambiente indicado no PRIMEIRO segmento do caminho:
//! `POST /{ambiente}/webhook/...` vai para o destino configurado em
//! `PROVIDER_EDGE_DESTINOS`. Cada evento vai para um único ambiente (sem fan-out).
//!
//! O ambiente vai no caminho porque quem registra a instância no provedor é o
//! ambiente dono dela: a URL gravada já carrega o destino certo. Este serviço não
//! lê o corpo, não autentica o provedor (quem faz isso é o `webhook_ingress`, pela
//! apikey/token da instância) e não guarda estado. Repassa status e corpo da
//! resposta, para o provedor reentregar exatamente o que o ingress decidiu.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::{get, post},
    Router,
};

/// Mesmo teto do `webhook_ingress`: a Evolution manda mídia em base64 dentro do
/// webhook (até ~17 MB codificado). Um teto menor cortaria mensagens reais.
const LIMITE_DO_CORPO: usize = 32 * 1024 * 1024;
/// Tempo máximo para o ingress responder. Acima disso o provedor reentrega.
const TIMEOUT_DO_DESTINO: Duration = Duration::from_secs(10);
const PORTA_PADRAO: u16 = 8088;

#[derive(Clone)]
struct Estado {
    destinos: Arc<BTreeMap<String, String>>,
    cliente: reqwest::Client,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("provider_edge", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    observability::instalar_hook_de_panic("provider_edge");

    let destinos = parse_destinos(&std::env::var("PROVIDER_EDGE_DESTINOS").unwrap_or_default())
        .map_err(|e| anyhow::anyhow!("PROVIDER_EDGE_DESTINOS inválido: {e}"))?;
    let porta: u16 = std::env::var("PROVIDER_EDGE_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(PORTA_PADRAO);

    let cliente = reqwest::Client::builder()
        .timeout(TIMEOUT_DO_DESTINO)
        .build()?;
    tracing::info!(
        ambientes = ?destinos.keys().collect::<Vec<_>>(),
        porta,
        "provider_edge configurado"
    );

    let app = construir_app(Estado {
        destinos: Arc::new(destinos),
        cliente,
    });

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", porta)).await?;
    tracing::info!("provider_edge ouvindo em 0.0.0.0:{porta}");

    // Requisições em voo terminam antes de fechar: um webhook cortado no deploy
    // é mensagem de cliente perdida.
    axum::serve(listener, app)
        .with_graceful_shutdown(observability::aguardar_sinal_de_parada())
        .await?;

    observability::shutdown_telemetry();
    Ok(())
}

fn construir_app(estado: Estado) -> Router {
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/{*caminho}", post(encaminhar))
        .layer(DefaultBodyLimit::max(LIMITE_DO_CORPO))
        .with_state(estado)
}

async fn encaminhar(
    State(estado): State<Estado>,
    uri: Uri,
    cabecalhos: HeaderMap,
    corpo: Bytes,
) -> Response {
    let Some((ambiente, resto)) = separar_caminho(uri.path()) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let Some(base) = estado.destinos.get(ambiente) else {
        // Ambiente fora da lista: não repassa nada. O nome é do caminho, não é segredo.
        tracing::warn!(ambiente, "ambiente desconhecido no provider_edge");
        return StatusCode::NOT_FOUND.into_response();
    };

    let mut url = format!("{base}{resto}");
    if let Some(query) = uri.query() {
        url.push('?');
        url.push_str(query);
    }

    let mut repassados = HeaderMap::new();
    for (nome, valor) in cabecalhos.iter() {
        if cabecalho_repassavel(nome.as_str()) {
            repassados.append(nome.clone(), valor.clone());
        }
    }

    let inicio = Instant::now();
    let pedido = estado
        .cliente
        .post(&url)
        .headers(repassados)
        .body(corpo)
        .send();
    match pedido.await {
        Ok(resposta) => {
            let status = resposta.status();
            let corpo_resposta = resposta.bytes().await.unwrap_or_default();
            tracing::info!(
                ambiente,
                status = status.as_u16(),
                tempo_ms = inicio.elapsed().as_millis() as u64,
                "webhook repassado"
            );
            (status, corpo_resposta).into_response()
        }
        Err(erro) => {
            // 504 ou 502: o provedor reentrega. Não registra o corpo (dado do cliente).
            let (status, motivo) = if erro.is_timeout() {
                (StatusCode::GATEWAY_TIMEOUT, "timeout")
            } else {
                (StatusCode::BAD_GATEWAY, "destino_indisponivel")
            };
            tracing::warn!(
                ambiente,
                motivo,
                tempo_ms = inicio.elapsed().as_millis() as u64,
                "falha ao repassar webhook"
            );
            status.into_response()
        }
    }
}

/// Lê `nome=url,nome=url` (ex.: `dev=http://webhook_ingress:9200,prod=http://172.17.0.1:9211`).
/// Recusa lista vazia, nome fora de `[a-z0-9_-]`, URL sem `http(s)://` e nome repetido.
fn parse_destinos(valor: &str) -> Result<BTreeMap<String, String>, String> {
    let mut mapa = BTreeMap::new();
    for item in valor.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let (nome, url) = item
            .split_once('=')
            .ok_or_else(|| format!("entrada sem '=': {item}"))?;
        let nome = nome.trim();
        let url = url.trim().trim_end_matches('/');

        let nome_valido = !nome.is_empty() && nome.chars().all(caractere_de_ambiente);
        if !nome_valido {
            return Err(format!("nome de ambiente inválido: '{nome}'"));
        }
        if !(url.starts_with("http://") || url.starts_with("https://")) {
            return Err(format!("URL sem http(s):// para o ambiente '{nome}'"));
        }
        if mapa.insert(nome.to_string(), url.to_string()).is_some() {
            return Err(format!("ambiente repetido: '{nome}'"));
        }
    }
    if mapa.is_empty() {
        return Err("nenhum destino configurado".into());
    }
    Ok(mapa)
}

/// Separa `/{ambiente}/resto` em `(ambiente, "/resto")`. Sem segundo segmento,
/// ou com ambiente vazio, não há destino: devolve `None`.
fn separar_caminho(caminho: &str) -> Option<(&str, &str)> {
    let sem_barra = caminho.strip_prefix('/')?;
    let (ambiente, _) = sem_barra.split_once('/')?;
    if ambiente.is_empty() {
        return None;
    }
    let inicio_do_resto = 1 + ambiente.len();
    Some((ambiente, &caminho[inicio_do_resto..]))
}

fn caractere_de_ambiente(c: char) -> bool {
    matches!(c, 'a'..='z' | '0'..='9' | '-' | '_')
}

/// Cabeçalhos hop-by-hop e os que o cliente HTTP recalcula não são repassados.
/// O resto segue, inclusive `apikey`, `traceparent` e `content-type`.
const CABECALHOS_NAO_REPASSADOS: [&str; 10] = [
    "host",
    "content-length",
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
];

fn cabecalho_repassavel(nome: &str) -> bool {
    !CABECALHOS_NAO_REPASSADOS.contains(&nome.to_ascii_lowercase().as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    #[test]
    fn parse_destinos_aceita_lista_valida_e_tira_barra_final() {
        let mapa = parse_destinos("dev=http://webhook_ingress:9200/,prod=http://172.17.0.1:9211")
            .expect("lista válida");
        assert_eq!(mapa.len(), 2);
        assert_eq!(mapa["dev"], "http://webhook_ingress:9200");
        assert_eq!(mapa["prod"], "http://172.17.0.1:9211");
    }

    #[test]
    fn parse_destinos_recusa_configuracao_ruim() {
        assert!(parse_destinos("").is_err(), "vazio");
        assert!(parse_destinos("dev").is_err(), "sem '='");
        assert!(parse_destinos("Dev=http://a:1").is_err(), "nome em maiúscula");
        assert!(parse_destinos("dev=webhook_ingress:9200").is_err(), "sem esquema");
        assert!(parse_destinos("dev=http://a:1,dev=http://b:2").is_err(), "repetido");
    }

    #[test]
    fn separar_caminho_extrai_ambiente_e_resto() {
        assert_eq!(
            separar_caminho("/dev/webhook/evolution/t-1/181"),
            Some(("dev", "/webhook/evolution/t-1/181"))
        );
        assert_eq!(separar_caminho("/prod/"), Some(("prod", "/")));
        assert_eq!(separar_caminho("/dev"), None, "sem resto");
        assert_eq!(separar_caminho("/"), None, "raiz");
        assert_eq!(separar_caminho("//webhook"), None, "ambiente vazio");
    }

    #[test]
    fn cabecalho_repassavel_descarta_so_hop_by_hop() {
        assert!(cabecalho_repassavel("apikey"));
        assert!(cabecalho_repassavel("traceparent"));
        assert!(cabecalho_repassavel("content-type"));
        assert!(!cabecalho_repassavel("host"));
        assert!(!cabecalho_repassavel("content-length"));
        assert!(!cabecalho_repassavel("Transfer-Encoding"));
        assert!(!cabecalho_repassavel("connection"));
    }

    fn estado_de_teste() -> Estado {
        let mut destinos = BTreeMap::new();
        // Endereço que não responde: os testes abaixo não podem depender de rede.
        destinos.insert("dev".to_string(), "http://127.0.0.1:1".to_string());
        Estado {
            destinos: Arc::new(destinos),
            cliente: reqwest::Client::new(),
        }
    }

    #[tokio::test]
    async fn health_responde_ok() {
        let resposta = construir_app(estado_de_teste())
            .oneshot(Request::get("/health").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resposta.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn ambiente_desconhecido_responde_404_sem_repassar() {
        let resposta = construir_app(estado_de_teste())
            .oneshot(
                Request::post("/prod/webhook/evolution/t/1")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resposta.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn destino_fora_do_ar_responde_502_para_o_provedor_reentregar() {
        let resposta = construir_app(estado_de_teste())
            .oneshot(
                Request::post("/dev/webhook/evolution/t/1")
                    .body(Body::from("{}"))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resposta.status(), StatusCode::BAD_GATEWAY);
    }
}
