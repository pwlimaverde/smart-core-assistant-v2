//! Authorization server OAuth 2.1 do módulo MCP (N13.1).
//!
//! É a peça que faz o botão **Conectar** do Claude (e do ChatGPT, e do Cursor)
//! funcionar: o cliente descobre este servidor a partir do `mcp_server`, manda o
//! usuário para cá, e o usuário faz login e aprova o que está concedendo — sem
//! copiar token nenhum.
//!
//! # O que este arquivo é obrigado a fazer, e por quê
//!
//! Um authorization server escrito à mão é a maior superfície de risco do plano
//! inteiro. A lista abaixo não é um checklist de qualidade: é o conjunto de
//! obrigações normativas da spec, e cada uma tem um teste de recusa.
//!
//! 1. HTTPS em tudo (garantido pelo Caddy; `redirect_uri` só https ou loopback).
//! 2. PKCE **S256** verificado no `/oauth/token`, com
//!    `code_challenge_methods_supported` publicado na metadata.
//! 3. `redirect_uri` validado por **igualdade exata** contra o que o CIMD declara.
//! 4. `iss` na resposta de autorização (RFC 9207) — inclusive nas de erro.
//! 5. Audiência honrada: o `resource` pedido vira o `aud` do token.
//! 6. Rotação de refresh token, com reuso derrubando o grant inteiro.
//! 7. CIMD validado (`client_id` == URL) e cacheado.
//! 8. Guarda anti-SSRF no fetch do CIMD (ver `cimd.rs`).
//! 9. Consentimento exibindo `client_name`, o **hostname do `redirect_uri`** e
//!    aviso reforçado para cliente só-localhost.
//! 10. Código de autorização de uso único, TTL curto, amarrado ao
//!     `code_challenge` e ao `redirect_uri`.
//!
//! # O que NÃO acontece aqui
//!
//! Este servidor não fala com o Postgres. O grant é persistido por RPC ao
//! `data_postgres`, como todo o resto do `control_plane`.

pub mod cimd;
pub mod html;
pub mod scopes;
pub mod store;
pub mod tokens;

use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::{ConnectInfo, Form, Query, State},
    http::{header, StatusCode},
    response::{Html, IntoResponse, Redirect, Response},
    routing::{get, post},
    Json, Router,
};

/// `Form` que junta chave repetida num `Vec` (usa `serde_html_form`).
///
/// O `axum::Form` usa `serde_urlencoded`, que **não** faz isso: um formulário
/// com várias caixas `name="escopos"` chega como `escopos=a&escopos=b` e
/// explode com *"invalid type: string, expected a sequence"*. Pior, com UMA
/// caixa marcada o erro é o mesmo — foi assim que o defeito apareceu, no
/// primeiro consentimento real.
///
/// Só o consentimento precisa disto; login e token continuam no `axum::Form`,
/// que basta para campos escalares.
use axum_extra::extract::Form as FormComRepeticao;
use contracts::{Envelope, MessageKind};
use serde::Deserialize;
use uuid::Uuid;

use application::auth::login::AuthDeps;

/// Configuração do AS, toda por ambiente.
pub struct OauthConfig {
    /// URL pública deste authorization server. Precisa bater **exatamente** com
    /// o `issuer` publicado na metadata, senão um cliente conforme recusa.
    pub issuer: String,
    /// URL pública do resource server (`mcp_server`). Vira o `aud` dos tokens.
    pub resource: String,
    pub access_ttl_s: i64,
    pub refresh_ttl_s: i64,
    pub token_interno_ttl_s: i64,
    /// Segredo compartilhado com o `mcp_server` para a troca interna de token.
    /// Não é credencial de usuário: identifica o processo.
    pub servico_secreto: String,
}

impl OauthConfig {
    pub fn from_env() -> Self {
        let issuer = std::env::var("MCP_OAUTH_ISSUER")
            .unwrap_or_else(|_| "https://auth.smartcoreassistant.com.br".to_string());
        let resource = std::env::var("MCP_OAUTH_RESOURCE")
            .unwrap_or_else(|_| "https://mcp.smartcoreassistant.com.br".to_string());
        Self {
            // Barra final quebra a comparação de `issuer` e de `aud`: o cliente
            // compara string, não URL normalizada.
            issuer: issuer.trim_end_matches('/').to_string(),
            resource: resource.trim_end_matches('/').to_string(),
            access_ttl_s: var_i64("MCP_ACCESS_TTL_S", 900),
            refresh_ttl_s: var_i64("MCP_REFRESH_TTL_S", 30 * 24 * 3600),
            token_interno_ttl_s: var_i64("MCP_TOKEN_INTERNO_TTL_S", 300),
            servico_secreto: std::env::var("MCP_SERVICE_SECRET").unwrap_or_default(),
        }
    }

    /// Janela real de revogação, em minutos — o número que aparece na tela de
    /// consentimento e na tela de aplicativos conectados.
    pub fn janela_revogacao_min(&self) -> i64 {
        // `(x + 59) / 60` e não `x.div_ceil(60)`: `div_ceil` é estável apenas para
        // inteiros SEM sinal — em `i64` ainda depende do feature instável
        // `int_roundings` (rust-lang/rust#88581). Trocar por `div_ceil` aqui parece
        // mais limpo e não compila.
        (self.access_ttl_s + 59) / 60
    }
}

fn var_i64(nome: &str, padrao: i64) -> i64 {
    std::env::var(nome)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(padrao)
}

#[derive(Clone)]
pub struct OauthState {
    pub config: Arc<OauthConfig>,
    pub chaves: Arc<tokens::ChavesMcp>,
    pub redis: redis::aio::ConnectionManager,
    pub http: reqwest::Client,
    pub auth: Arc<AuthDeps>,
    /// `Arc` porque `MuxClient` não é `Clone` — ele guarda a conexão viva atrás
    /// de um `Mutex`, e clonar significaria abrir uma conexão por requisição.
    pub pg: Arc<transport::MuxClient>,
}

pub fn rotas(estado: OauthState) -> Router {
    Router::new()
        .route("/.well-known/oauth-authorization-server", get(metadata_as))
        // Alguns clientes pedem a metadata no caminho com sufixo do recurso
        // (RFC 8414 §3.1). Servir o mesmo documento nos dois evita o 404 que
        // faria o cliente desistir antes de tentar o caminho canônico.
        .route(
            "/.well-known/oauth-authorization-server/mcp",
            get(metadata_as),
        )
        .route("/oauth/authorize", get(authorize))
        .route("/oauth/authorize/login", post(authorize_login))
        .route("/oauth/authorize/consent", post(authorize_consent))
        .route("/oauth/token", post(token))
        .route("/internal/mcp/token-exchange", post(token_exchange))
        .route("/health", get(|| async { "ok" }))
        .with_state(estado)
}

// ---------------------------------------------------------------------------
// Metadata (RFC 8414)
// ---------------------------------------------------------------------------

/// `code_challenge_methods_supported` é o campo que não pode faltar: a spec MCP
/// manda o cliente **recusar** um AS que não o publique. Publicar `["S256"]` e
/// só aceitar S256 no token endpoint mantém a promessa honesta.
async fn metadata_as(State(estado): State<OauthState>) -> impl IntoResponse {
    let c = &estado.config;
    let corpo = serde_json::json!({
        "issuer": c.issuer,
        "authorization_endpoint": format!("{}/oauth/authorize", c.issuer),
        "token_endpoint": format!("{}/oauth/token", c.issuer),
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
        "client_id_metadata_document_supported": true,
        "authorization_response_iss_parameter_supported": true,
        "scopes_supported": scopes::todos(),
        "service_documentation": "https://smartcoreassistant.com.br/docs/mcp",
    });
    (
        // Sem `Content-Type` explícito: o `Json` já o define, e declarar os dois
        // só criaria dúvida sobre qual vence.
        //
        // A metadata é pública e estável; cache curto tira carga sem atrapalhar
        // uma correção.
        [(header::CACHE_CONTROL, "public, max-age=300")],
        Json(corpo),
    )
}

// ---------------------------------------------------------------------------
// /oauth/authorize
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct AuthorizeParams {
    pub response_type: Option<String>,
    pub client_id: Option<String>,
    pub redirect_uri: Option<String>,
    pub state: Option<String>,
    pub code_challenge: Option<String>,
    pub code_challenge_method: Option<String>,
    pub scope: Option<String>,
    pub resource: Option<String>,
}

/// Erro que ainda **não** pode ser devolvido por redirect.
///
/// A distinção é normativa: enquanto `client_id` e `redirect_uri` não estiverem
/// validados, redirecionar seria mandar a mensagem de erro para uma URI que o
/// atacante escolheu. Nesses casos a resposta é uma página, não um 302.
fn erro_de_pagina(titulo: &str, detalhe: &str) -> Response {
    (
        StatusCode::BAD_REQUEST,
        Html(html::tela_erro(titulo, detalhe)),
    )
        .into_response()
}

/// Erro devolvido ao cliente por redirect, já com `iss` (RFC 9207).
///
/// O `iss` também vai nas respostas de erro de propósito: sem ele, um cliente
/// que fale com vários AS não sabe **qual** deles recusou, e a mitigação de
/// mix-up deixa de valer justamente no caminho de erro, que é o mais explorado.
/// A origem do endereço de retorno, no formato que o `form-action` do CSP aceita.
///
/// `None` quando não dá para montar uma origem segura — e aí a tela fica só com
/// `'self'`, que é o comportamento antigo.
fn origem_de_retorno(redirect_uri: &str) -> Option<String> {
    let url = url::Url::parse(redirect_uri).ok()?;
    let origem = match url.scheme() {
        "http" | "https" => {
            let host = url.host_str()?;
            match url.port() {
                Some(porta) => format!("{}://{}:{}", url.scheme(), host, porta),
                None => format!("{}://{}", url.scheme(), host),
            }
        }
        // Esquema próprio de app de desktop (ex.: `cursor://`).
        outro => format!("{outro}:"),
    };
    // Nada que feche a diretiva ou abra outra: o valor vai para um header.
    if origem
        .chars()
        .any(|c| c.is_whitespace() || matches!(c, ';' | ',' | '\'' | '"'))
    {
        return None;
    }
    Some(origem)
}

/// CSP das telas do fluxo de autorização.
///
/// O `form-action` também vale para o **redirecionamento** que responde ao
/// formulário: com só `'self'`, o navegador bloqueava o 303 de volta ao cliente
/// (`https://claude.ai/api/mcp/auth_callback`, `http://localhost:…/callback`)
/// depois de "Aprovar", e a tela ficava parada sem erro nenhum. A origem exata do
/// retorno deste pedido entra na lista — só ela, não "qualquer https".
fn csp_do_fluxo(redirect_uri: &str) -> String {
    let retorno = origem_de_retorno(redirect_uri)
        .map(|o| format!(" {o}"))
        .unwrap_or_default();
    format!(
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'{retorno};          base-uri 'none'; frame-ancestors 'none'"
    )
}

/// Uma tela do fluxo (login ou consentimento) com a CSP que deixa o formulário
/// voltar ao cliente.
fn tela_do_fluxo(status: StatusCode, corpo: String, redirect_uri: &str) -> Response {
    let mut resposta = (status, Html(corpo)).into_response();
    if let Ok(valor) = header::HeaderValue::from_str(&csp_do_fluxo(redirect_uri)) {
        resposta
            .headers_mut()
            .insert(header::CONTENT_SECURITY_POLICY, valor);
    }
    resposta
}

fn erro_por_redirect(
    redirect_uri: &str,
    issuer: &str,
    state: Option<&str>,
    erro: &str,
    descricao: &str,
) -> Response {
    let mut url = match url::Url::parse(redirect_uri) {
        Ok(u) => u,
        Err(_) => return erro_de_pagina("Endereço de retorno inválido", descricao),
    };
    {
        let mut q = url.query_pairs_mut();
        q.append_pair("error", erro);
        q.append_pair("error_description", descricao);
        q.append_pair("iss", issuer);
        if let Some(s) = state {
            q.append_pair("state", s);
        }
    }
    Redirect::to(url.as_str()).into_response()
}

#[tracing::instrument(skip_all, fields(client_id = tracing::field::Empty))]
async fn authorize(
    State(estado): State<OauthState>,
    Query(params): Query<AuthorizeParams>,
) -> Response {
    let cfg = &estado.config;

    let Some(client_id) = params.client_id.as_deref().filter(|s| !s.is_empty()) else {
        return erro_de_pagina(
            "Pedido incompleto",
            "O aplicativo não informou quem ele é (client_id).",
        );
    };
    tracing::Span::current().record("client_id", client_id);

    let Some(redirect_uri) = params.redirect_uri.as_deref().filter(|s| !s.is_empty()) else {
        return erro_de_pagina(
            "Pedido incompleto",
            "O aplicativo não informou para onde devolver o acesso (redirect_uri).",
        );
    };

    // 1. Documento do cliente (cache primeiro; o fetch tem guarda anti-SSRF).
    let mut redis = estado.redis.clone();
    let metadata = match store::cimd_do_cache(&mut redis, client_id).await {
        Some(m) => m,
        None => match cimd::buscar(&estado.http, client_id).await {
            Ok(m) => {
                store::cachear_cimd(&mut redis, client_id, &m).await;
                m
            }
            // Cliente conhecido cujo documento não se alcança daqui (o Claude,
            // atrás do Cloudflare): vale o documento embutido. Ver
            // `cimd::documento_conhecido`.
            Err(e) => match cimd::documento_conhecido(client_id) {
                Some(m) => {
                    tracing::warn!(
                        motivo = e.motivo(),
                        "documento do cliente MCP inalcançável; usando o conhecido"
                    );
                    store::cachear_cimd(&mut redis, client_id, &m).await;
                    m
                }
                None => {
                    tracing::warn!(
                        motivo = e.motivo(),
                        "documento de metadados do cliente MCP recusado"
                    );
                    // Sem CIMD válido não há `redirect_uri` confiável: página,
                    // não redirect.
                    return erro_de_pagina("Aplicativo não reconhecido", &e.to_string());
                }
            },
        },
    };

    // 2. `redirect_uri` por igualdade exata. Daqui em diante o redirect é seguro.
    if !cimd::redirect_uri_declarado(&metadata, redirect_uri) {
        tracing::warn!("redirect_uri não declarado pelo cliente MCP");
        return erro_de_pagina(
            "Endereço de retorno não autorizado",
            "O endereço para onde o aplicativo pediu para devolver o acesso não está \
             declarado no documento público dele.",
        );
    }

    // 3. Daqui para baixo, erro vai por redirect com `iss`.
    if params.response_type.as_deref() != Some("code") {
        return erro_por_redirect(
            redirect_uri,
            &cfg.issuer,
            params.state.as_deref(),
            "unsupported_response_type",
            "somente o fluxo de código de autorização é aceito",
        );
    }
    if params.code_challenge_method.as_deref() != Some("S256") {
        return erro_por_redirect(
            redirect_uri,
            &cfg.issuer,
            params.state.as_deref(),
            "invalid_request",
            "PKCE com code_challenge_method=S256 é obrigatório",
        );
    }
    let Some(code_challenge) = params.code_challenge.as_deref().filter(|s| s.len() >= 43) else {
        return erro_por_redirect(
            redirect_uri,
            &cfg.issuer,
            params.state.as_deref(),
            "invalid_request",
            "code_challenge ausente ou curto demais",
        );
    };

    // 4. Audiência (RFC 8707). Pedido para outro recurso é recusado: emitir um
    // token com `aud` que não é o nosso seria emitir para um servidor alheio.
    let resource = params.resource.as_deref().unwrap_or(&cfg.resource);
    if resource.trim_end_matches('/') != cfg.resource {
        return erro_por_redirect(
            redirect_uri,
            &cfg.issuer,
            params.state.as_deref(),
            "invalid_target",
            "este servidor só emite acesso para o próprio recurso MCP",
        );
    }

    let escopos_pedidos: Vec<String> = params
        .scope
        .as_deref()
        .unwrap_or("")
        .split_whitespace()
        .map(str::to_string)
        .collect();

    let requisicao = store::RequisicaoAutorizacao {
        client_id: client_id.to_string(),
        client_name: metadata.client_name.clone(),
        redirect_uri: redirect_uri.to_string(),
        state: params.state.clone(),
        code_challenge: code_challenge.to_string(),
        resource: cfg.resource.clone(),
        escopos_pedidos: scopes::apenas_conhecidos(&escopos_pedidos),
        somente_localhost: cimd::somente_localhost(&metadata),
        usuario: None,
    };

    let ticket = store::novo_identificador();
    if store::gravar_ticket(&mut redis, &ticket, &requisicao)
        .await
        .is_err()
    {
        return erro_por_redirect(
            redirect_uri,
            &cfg.issuer,
            params.state.as_deref(),
            "server_error",
            "não foi possível iniciar a autorização",
        );
    }

    tela_do_fluxo(
        StatusCode::OK,
        html::tela_login(&ticket, &metadata.client_name, None),
        redirect_uri,
    )
}

// ---------------------------------------------------------------------------
// Login dentro do fluxo
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct LoginForm {
    pub ticket: String,
    pub email: String,
    pub senha: String,
}

#[tracing::instrument(skip_all)]
async fn authorize_login(
    State(estado): State<OauthState>,
    Form(form): Form<LoginForm>,
) -> Response {
    let mut redis = estado.redis.clone();
    let Some(mut requisicao) = store::ler_ticket(&mut redis, &form.ticket).await else {
        return erro_de_pagina(
            "Sessão de autorização expirada",
            "A tela ficou aberta tempo demais. Volte ao aplicativo e conecte de novo.",
        );
    };

    let traceparent = novo_traceparent();
    let usuario = match application::auth::login::autenticar(
        &estado.auth,
        &traceparent,
        &form.email,
        &form.senha,
    )
    .await
    {
        Ok(u) => u,
        Err(e) => {
            // A mensagem ao usuário é genérica de propósito (não revela se o
            // e-mail existe); o motivo real fica no log, sem a credencial.
            tracing::warn!(erro = %e, "login recusado no fluxo OAuth do MCP");
            let msg = if matches!(e, error_core::AppError::RateLimit(_)) {
                "Muitas tentativas. Aguarde um minuto e tente de novo."
            } else {
                "E-mail ou senha incorretos."
            };
            return tela_do_fluxo(
                StatusCode::UNAUTHORIZED,
                html::tela_login(&form.ticket, &requisicao.client_name, Some(msg)),
                &requisicao.redirect_uri,
            );
        }
    };

    // Superusuário não conecta agente: D4 do plano. Um token de superusuário
    // alcançaria todos os tenants, e o limite de dano do desenho inteiro é
    // "um token vazado alcança no máximo um tenant".
    if usuario.is_superuser {
        return erro_de_pagina(
            "Conta não elegível",
            "Contas de superusuário não podem conectar agentes externos. \
             Use uma conta do próprio negócio.",
        );
    }

    let escopos_ofertaveis = scopes::escopos_ofertaveis(&usuario.scopes);
    if escopos_ofertaveis.is_empty() {
        return erro_de_pagina(
            "Sem permissões para conceder",
            "Sua conta não tem nenhuma permissão que possa ser concedida a um agente. \
             Fale com o administrador do seu negócio.",
        );
    }

    requisicao.usuario = Some(store::UsuarioDoTicket {
        user_id: usuario.user_id,
        tenant_id: usuario.tenant_id,
        escopos: usuario.scopes.clone(),
    });

    // Ticket novo: o anônimo é consumido e o autenticado nasce com outro
    // identificador. Reapresentar o ticket de login não devolve uma tela de
    // consentimento já autenticada.
    let _ = store::consumir_ticket(&mut redis, &form.ticket).await;
    let ticket_autenticado = store::novo_identificador();
    if store::gravar_ticket(&mut redis, &ticket_autenticado, &requisicao)
        .await
        .is_err()
    {
        return erro_de_pagina(
            "Falha temporária",
            "Não foi possível continuar a autorização. Tente de novo.",
        );
    }

    let metadata = cimd::ClientMetadata {
        client_id: requisicao.client_id.clone(),
        client_name: requisicao.client_name.clone(),
        redirect_uris: vec![requisicao.redirect_uri.clone()],
        client_uri: None,
    };

    tela_do_fluxo(
        StatusCode::OK,
        html::tela_consentimento(
            &ticket_autenticado,
            &metadata,
            &requisicao.redirect_uri,
            &escopos_ofertaveis,
            &requisicao.escopos_pedidos,
            requisicao.somente_localhost,
            estado.config.janela_revogacao_min(),
        ),
        &requisicao.redirect_uri,
    )
}

// ---------------------------------------------------------------------------
// Consentimento
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct ConsentForm {
    pub ticket: String,
    pub decisao: String,
    /// Checkboxes marcados. Ausente quando o usuário desmarcou tudo.
    ///
    /// ⚠️ Depende de [`FormComRepeticao`] no handler. Com o `axum::Form` padrão
    /// este campo falha na desserialização assim que UMA caixa vem marcada.
    #[serde(default)]
    pub escopos: Vec<String>,
}

#[tracing::instrument(skip_all, fields(client_id = tracing::field::Empty, grant_id = tracing::field::Empty))]
async fn authorize_consent(
    State(estado): State<OauthState>,
    ConnectInfo(origem): ConnectInfo<std::net::SocketAddr>,
    FormComRepeticao(form): FormComRepeticao<ConsentForm>,
) -> Response {
    let cfg = &estado.config;
    let mut redis = estado.redis.clone();

    // O ticket é consumido aqui: uma decisão por autorização.
    let Some(requisicao) = store::consumir_ticket(&mut redis, &form.ticket).await else {
        return erro_de_pagina(
            "Sessão de autorização expirada",
            "A tela ficou aberta tempo demais, ou a decisão já foi registrada. \
             Volte ao aplicativo e conecte de novo.",
        );
    };
    tracing::Span::current().record("client_id", requisicao.client_id.as_str());

    let Some(usuario) = requisicao.usuario.clone() else {
        return erro_de_pagina(
            "Autorização inválida",
            "Esta autorização não passou pelo login.",
        );
    };

    if form.decisao != "aprovar" {
        tracing::info!("consentimento negado pelo usuário");
        return erro_por_redirect(
            &requisicao.redirect_uri,
            &cfg.issuer,
            requisicao.state.as_deref(),
            "access_denied",
            "o usuário não autorizou o acesso",
        );
    }

    // Regra do subconjunto, aplicada de novo no servidor. A tela já filtrava,
    // mas a tela é HTML: qualquer um pode reenviar o formulário com escopos a
    // mais. Esta interseção é a que vale.
    let concedidos =
        scopes::interseccionar(&scopes::apenas_conhecidos(&form.escopos), &usuario.escopos);
    if concedidos.is_empty() {
        return erro_por_redirect(
            &requisicao.redirect_uri,
            &cfg.issuer,
            requisicao.state.as_deref(),
            "invalid_scope",
            "nenhuma permissão foi selecionada",
        );
    }

    // Persiste o consentimento.
    let payload = serde_json::json!({
        "client_id": requisicao.client_id,
        "client_name": requisicao.client_name,
        "redirect_uri": requisicao.redirect_uri,
        "scopes": concedidos,
        "created_ip": origem.ip().to_string(),
    });
    let resposta = match chamar_pg(
        &estado.pg,
        "RegisterMcpGrant",
        usuario.tenant_id,
        usuario.user_id,
        &usuario.escopos,
        payload,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::error!(erro = %e, "falha ao registrar consentimento MCP");
            return erro_por_redirect(
                &requisicao.redirect_uri,
                &cfg.issuer,
                requisicao.state.as_deref(),
                "server_error",
                "não foi possível registrar a autorização",
            );
        }
    };

    let grant_id = resposta
        .get("grant")
        .and_then(|g| g.get("id"))
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok());
    let Some(grant_id) = grant_id else {
        return erro_por_redirect(
            &requisicao.redirect_uri,
            &cfg.issuer,
            requisicao.state.as_deref(),
            "server_error",
            "resposta inesperada ao registrar a autorização",
        );
    };
    tracing::Span::current().record("grant_id", tracing::field::display(grant_id));

    // Código de autorização: uso único, 60s, amarrado ao desafio PKCE, ao
    // `redirect_uri` e ao `resource`.
    let codigo = store::novo_identificador();
    let dados = store::CodigoAutorizacao {
        grant_id,
        user_id: usuario.user_id,
        tenant_id: usuario.tenant_id,
        client_id: requisicao.client_id.clone(),
        redirect_uri: requisicao.redirect_uri.clone(),
        code_challenge: requisicao.code_challenge.clone(),
        resource: requisicao.resource.clone(),
        escopos: concedidos,
    };
    if store::gravar_codigo(&mut redis, &codigo, &dados)
        .await
        .is_err()
    {
        return erro_por_redirect(
            &requisicao.redirect_uri,
            &cfg.issuer,
            requisicao.state.as_deref(),
            "server_error",
            "não foi possível concluir a autorização",
        );
    }

    let mut url = match url::Url::parse(&requisicao.redirect_uri) {
        Ok(u) => u,
        Err(_) => return erro_de_pagina("Endereço de retorno inválido", "redirect_uri malformado"),
    };
    {
        let mut q = url.query_pairs_mut();
        q.append_pair("code", &codigo);
        // RFC 9207: o cliente precisa saber qual AS respondeu.
        q.append_pair("iss", &cfg.issuer);
        if let Some(s) = &requisicao.state {
            q.append_pair("state", s);
        }
    }
    Redirect::to(url.as_str()).into_response()
}

// ---------------------------------------------------------------------------
// /oauth/token
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct TokenForm {
    pub grant_type: String,
    pub code: Option<String>,
    pub code_verifier: Option<String>,
    pub redirect_uri: Option<String>,
    pub client_id: Option<String>,
    pub refresh_token: Option<String>,
    pub resource: Option<String>,
}

fn erro_token(status: StatusCode, erro: &str, descricao: &str) -> Response {
    // Toda recusa no endpoint de token fica registrada com o motivo. Sem isto
    // a renovação falhou em silêncio por semanas: o cliente só dizia que "o
    // usuário não concluiu a autenticação", e o servidor não tinha uma linha.
    tracing::warn!(
        erro,
        motivo = descricao,
        "endpoint de token recusou o pedido"
    );
    (
        status,
        // `no-store` é exigência da RFC 6749 §5.1 para respostas com token: um
        // proxy que cacheasse esta resposta serviria o token de um a outro.
        [(header::CACHE_CONTROL, "no-store")],
        Json(serde_json::json!({
            "error": erro,
            "error_description": descricao,
        })),
    )
        .into_response()
}

#[tracing::instrument(skip_all, fields(grant_type = %form.grant_type, grant_id = tracing::field::Empty))]
async fn token(State(estado): State<OauthState>, Form(form): Form<TokenForm>) -> Response {
    match form.grant_type.as_str() {
        "authorization_code" => token_por_codigo(estado, form).await,
        "refresh_token" => token_por_refresh(estado, form).await,
        _ => erro_token(
            StatusCode::BAD_REQUEST,
            "unsupported_grant_type",
            "somente authorization_code e refresh_token são aceitos",
        ),
    }
}

async fn token_por_codigo(estado: OauthState, form: TokenForm) -> Response {
    let cfg = &estado.config;
    let mut redis = estado.redis.clone();

    let Some(code) = form.code.as_deref().filter(|s| !s.is_empty()) else {
        return erro_token(StatusCode::BAD_REQUEST, "invalid_request", "code ausente");
    };
    let Some(code_verifier) = form.code_verifier.as_deref().filter(|s| !s.is_empty()) else {
        // Ausência de PKCE é recusa dura: sem ele, um código interceptado basta.
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_request",
            "code_verifier ausente (PKCE é obrigatório)",
        );
    };

    // GETDEL: o código morre aqui, dê no que der. Uma segunda troca do mesmo
    // código não encontra nada.
    let Some(dados) = store::consumir_codigo(&mut redis, code).await else {
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "código inválido, expirado ou já utilizado",
        );
    };
    tracing::Span::current().record("grant_id", tracing::field::display(dados.grant_id));

    if !tokens::pkce_confere(code_verifier, &dados.code_challenge) {
        tracing::warn!(
            grant_id = %dados.grant_id,
            "PKCE não confere na troca de código MCP"
        );
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "code_verifier não corresponde ao code_challenge",
        );
    }

    // `redirect_uri` e `client_id`, quando enviados, precisam ser os mesmos da
    // autorização. Um código emitido para um cliente não vale para outro.
    if let Some(uri) = form.redirect_uri.as_deref() {
        if uri != dados.redirect_uri {
            return erro_token(
                StatusCode::BAD_REQUEST,
                "invalid_grant",
                "redirect_uri diferente do usado na autorização",
            );
        }
    }
    if let Some(cid) = form.client_id.as_deref() {
        if cid != dados.client_id {
            return erro_token(
                StatusCode::BAD_REQUEST,
                "invalid_grant",
                "client_id diferente do usado na autorização",
            );
        }
    }
    if let Some(res) = form.resource.as_deref() {
        if res.trim_end_matches('/') != dados.resource {
            return erro_token(
                StatusCode::BAD_REQUEST,
                "invalid_target",
                "resource diferente do pedido na autorização",
            );
        }
    }

    emitir_par_de_tokens(
        &estado,
        dados.grant_id,
        dados.user_id,
        dados.tenant_id,
        &dados.client_id,
        &dados.escopos,
        cfg,
    )
    .await
}

async fn token_por_refresh(estado: OauthState, form: TokenForm) -> Response {
    let cfg = &estado.config;

    let Some(refresh) = form.refresh_token.as_deref().filter(|s| !s.is_empty()) else {
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_request",
            "refresh_token ausente",
        );
    };
    let Some((grant_id, segredo)) = tokens::partir_refresh_token(refresh) else {
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "refresh token inválido",
        );
    };
    tracing::Span::current().record("grant_id", tracing::field::display(grant_id));

    // O tenant vem do próprio grant; para buscá-lo é preciso o tenant. O
    // `data_postgres` resolve isso porque o `grant_id` é UUID e a busca leva o
    // tenant do envelope — que aqui vem do refresh token em si. Como não
    // conhecemos o tenant antes de ler o grant, a consulta usa o tenant nulo e
    // o handler do lado de lá aceita a busca por id: é rota interna, e o
    // `grant_id` é imprevisível.
    let resposta = match chamar_pg(
        &estado.pg,
        "GetMcpGrantComSegredo",
        Uuid::nil(),
        0,
        &[],
        serde_json::json!({ "grant_id": grant_id.to_string() }),
    )
    .await
    {
        Ok(v) => v,
        Err(_) => {
            return erro_token(
                StatusCode::BAD_REQUEST,
                "invalid_grant",
                "refresh token inválido ou revogado",
            )
        }
    };

    let hash_guardado = resposta
        .get("refresh_token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let grant = resposta.get("grant").cloned().unwrap_or_default();
    let tenant_id = grant
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .unwrap_or_else(Uuid::nil);
    let user_id = grant.get("user_id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let client_id = grant
        .get("client_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let concedidos: Vec<String> = grant
        .get("scopes")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();

    // Teto de vida do consentimento.
    //
    // Sem isto, um refresh token rotacionado indefinidamente vale para sempre —
    // e "para sempre" numa credencial de cliente público é o tipo de coisa que
    // ninguém nota até vazar. Não há coluna de expiração na tabela: o teto é
    // medido sobre o `created_at` do grant, que já vem na resposta. Passado o
    // prazo, o usuário reconecta pelo navegador (uma tela, dez segundos) e o
    // consentimento nasce novo.
    let criado_em_ms = grant
        .get("created_at")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let idade_s = (chrono::Utc::now().timestamp_millis() - criado_em_ms) / 1000;
    if criado_em_ms > 0 && idade_s > cfg.refresh_ttl_s {
        tracing::info!(
            %grant_id,
            idade_dias = idade_s / 86_400,
            "consentimento MCP passou do teto de vida: exigindo reconexão"
        );
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "esta autorização expirou; reconecte o aplicativo",
        );
    }

    if hash_guardado.is_empty()
        || !tokens::hash_confere(&hash_guardado, &tokens::hash_refresh(&segredo))
    {
        // Hash que não confere num grant que existe = refresh já rotacionado
        // sendo reapresentado. Duas partes têm o token; não dá para saber qual
        // é a legítima, e a única resposta segura é derrubar o consentimento.
        tracing::warn!(
            %grant_id,
            "refresh token reutilizado ou inválido: revogando o consentimento"
        );
        let _ = chamar_pg(
            &estado.pg,
            "RevokeMcpGrantPorReuso",
            tenant_id,
            user_id,
            &[],
            serde_json::json!({ "grant_id": grant_id.to_string() }),
        )
        .await;
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "refresh token inválido; a autorização foi encerrada por segurança",
        );
    }

    // Reinterseção com os escopos ATUAIS: rebaixar alguém no painel encolhe o
    // agente na renovação seguinte, sem tocar no grant.
    let escopos_atuais = match escopos_atuais_do_usuario(&estado, tenant_id, user_id).await {
        Some(e) => e,
        None => {
            return erro_token(
                StatusCode::BAD_REQUEST,
                "invalid_grant",
                "usuário não está mais ativo",
            )
        }
    };
    let efetivos = scopes::interseccionar(&concedidos, &escopos_atuais);
    if efetivos.is_empty() {
        return erro_token(
            StatusCode::BAD_REQUEST,
            "invalid_grant",
            "o usuário não possui mais nenhuma das permissões concedidas",
        );
    }

    tracing::info!(%grant_id, "token MCP renovado");
    emitir_par_de_tokens(
        &estado, grant_id, user_id, tenant_id, &client_id, &efetivos, cfg,
    )
    .await
}

/// Emite access + refresh e **rotaciona** o hash guardado no grant.
///
/// A rotação acontece em toda emissão, inclusive na primeira: o refresh anterior
/// deixa de valer no mesmo instante em que o novo é entregue.
#[allow(clippy::too_many_arguments)]
async fn emitir_par_de_tokens(
    estado: &OauthState,
    grant_id: Uuid,
    user_id: i32,
    tenant_id: Uuid,
    client_id: &str,
    escopos: &[String],
    cfg: &OauthConfig,
) -> Response {
    let (access_token, claims) = match tokens::emitir_access_token(
        &estado.chaves,
        &cfg.issuer,
        &cfg.resource,
        user_id,
        tenant_id,
        grant_id,
        client_id,
        escopos,
        cfg.access_ttl_s,
    ) {
        Ok(par) => par,
        Err(e) => {
            tracing::error!(erro = %e, "falha ao emitir access token MCP");
            return erro_token(
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                "não foi possível emitir o token",
            );
        }
    };

    let refresh = tokens::gerar_refresh_token(grant_id);
    let (_, segredo) = tokens::partir_refresh_token(&refresh).unwrap_or((grant_id, String::new()));
    let hash = tokens::hash_refresh(&segredo);

    if chamar_pg(
        &estado.pg,
        "SetMcpGrantRefreshHash",
        tenant_id,
        user_id,
        &[],
        serde_json::json!({
            "grant_id": grant_id.to_string(),
            "refresh_token_hash": hash,
        }),
    )
    .await
    .is_err()
    {
        return erro_token(
            StatusCode::INTERNAL_SERVER_ERROR,
            "server_error",
            "não foi possível concluir a emissão do token",
        );
    }

    (
        StatusCode::OK,
        [(header::CACHE_CONTROL, "no-store")],
        Json(serde_json::json!({
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": cfg.access_ttl_s,
            "refresh_token": refresh,
            "scope": escopos.join(" "),
            // Eco do `aud`: o cliente pode conferir que recebeu acesso para o
            // recurso que pediu.
            "resource": claims.aud,
        })),
    )
        .into_response()
}

// ---------------------------------------------------------------------------
// Troca interna (D8) — o token do cliente nunca vai ao runtime_api
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct TrocaInternaReq {
    /// Access token que o cliente MCP apresentou ao `mcp_server`.
    pub access_token: String,
}

/// Troca o access token do cliente por um JWT interno de vida curta.
///
/// *"The MCP server MUST NOT pass through the token it received from the MCP
/// client."* Este endpoint é a outra ponta dessa regra: o `mcp_server` entrega o
/// token que recebeu e leva de volta uma credencial **nossa**, com audiência
/// interna, que o `runtime_api` sabe validar.
///
/// Autenticação do chamador é por segredo de serviço no header
/// `X-Servico-Secreto`. Não é credencial de usuário: identifica o processo, e
/// existe para que o endpoint não fique aberto dentro da rede interna.
#[tracing::instrument(skip_all, fields(grant_id = tracing::field::Empty))]
async fn token_exchange(
    State(estado): State<OauthState>,
    headers: header::HeaderMap,
    Json(req): Json<TrocaInternaReq>,
) -> Response {
    let cfg = &estado.config;

    let apresentado = headers
        .get("x-servico-secreto")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    if cfg.servico_secreto.is_empty() || !tokens::hash_confere(&cfg.servico_secreto, apresentado) {
        return erro_token(
            StatusCode::UNAUTHORIZED,
            "invalid_client",
            "serviço não autorizado",
        );
    }

    let claims = match tokens::validar_access_token(
        &estado.chaves,
        &req.access_token,
        &cfg.issuer,
        &cfg.resource,
    ) {
        Ok(c) => c,
        Err(_) => {
            return erro_token(
                StatusCode::UNAUTHORIZED,
                "invalid_token",
                "access token inválido, expirado ou de audiência alheia",
            )
        }
    };
    tracing::Span::current().record("grant_id", claims.grant_id.as_str());

    let tenant_id = Uuid::parse_str(&claims.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let user_id: i32 = claims.sub.parse().unwrap_or(0);
    let grant_id = Uuid::parse_str(&claims.grant_id).unwrap_or_else(|_| Uuid::nil());

    // O grant precisa continuar vivo: revogar no painel corta o acesso na
    // próxima troca, e não só quando o access token expira.
    let grant_ok = chamar_pg(
        &estado.pg,
        "GetMcpGrantComSegredo",
        tenant_id,
        user_id,
        &[],
        serde_json::json!({ "grant_id": grant_id.to_string() }),
    )
    .await
    .is_ok();
    if !grant_ok {
        return erro_token(
            StatusCode::UNAUTHORIZED,
            "invalid_token",
            "a autorização foi revogada",
        );
    }

    // Reinterseção também aqui: entre a emissão do access token e esta chamada
    // podem ter passado 15 minutos, e o usuário pode ter sido rebaixado.
    let escopos_atuais = escopos_atuais_do_usuario(&estado, tenant_id, user_id)
        .await
        .unwrap_or_default();
    let efetivos = scopes::interseccionar(&claims.scopes, &escopos_atuais);
    if efetivos.is_empty() {
        return erro_token(
            StatusCode::FORBIDDEN,
            "insufficient_scope",
            "o usuário não possui mais as permissões concedidas",
        );
    }

    match tokens::emitir_token_interno(
        user_id,
        tenant_id,
        false,
        &efetivos,
        cfg.token_interno_ttl_s,
    ) {
        Ok(interno) => (
            StatusCode::OK,
            [(header::CACHE_CONTROL, "no-store")],
            Json(serde_json::json!({
                "internal_token": interno,
                "expires_in": cfg.token_interno_ttl_s,
                "tenant_id": tenant_id.to_string(),
                "user_id": user_id,
                "scopes": efetivos,
                "grant_id": claims.grant_id,
                "client_id": claims.client_id,
            })),
        )
            .into_response(),
        Err(e) => {
            tracing::error!(erro = %e, "falha ao emitir token interno");
            erro_token(
                StatusCode::INTERNAL_SERVER_ERROR,
                "server_error",
                "não foi possível emitir a credencial interna",
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Auxiliares
// ---------------------------------------------------------------------------

fn novo_traceparent() -> String {
    format!(
        "00-{}-{}-01",
        Uuid::now_v7().simple(),
        &Uuid::now_v7().simple().to_string()[..16]
    )
}

/// Chamada RPC ao `data_postgres` com o envelope de identidade preenchido.
async fn chamar_pg(
    pg: &transport::MuxClient,
    metodo: &str,
    tenant_id: Uuid,
    user_id: i32,
    escopos: &[String],
    payload: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let env = Envelope {
        tenant_id: tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: String::new(),
        traceparent: novo_traceparent(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: metodo.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        auth_user_id: user_id,
        auth_scopes: escopos.to_vec(),
        auth_is_superuser: false,
        ..Default::default()
    };

    let resp = pg
        .call(env, Duration::from_secs(5))
        .await
        .map_err(|e| format!("RPC {metodo} falhou: {e}"))?;

    if resp.kind == MessageKind::Error as i32 {
        return Err(resp
            .error
            .map(|e| e.message)
            .unwrap_or_else(|| format!("RPC {metodo} devolveu erro")));
    }

    serde_json::from_slice(&resp.payload).map_err(|e| e.to_string())
}

/// Escopos que o usuário possui **agora**, relidos do banco.
///
/// Não dá para confiar no que está no grant nem no token: é justamente essa
/// releitura que faz um rebaixamento valer sem exigir que alguém se lembre de
/// revogar consentimentos um a um.
///
/// Reusa `GetUserIdentity` (que já devolve `is_active`, `role` e
/// `module_permissions`) e `derivar_escopos` — a **mesma** função do login. Uma
/// RPC nova aqui teria criado um segundo caminho de derivação de escopo, e dois
/// caminhos divergem.
async fn escopos_atuais_do_usuario(
    estado: &OauthState,
    tenant_id: Uuid,
    user_id: i32,
) -> Option<Vec<String>> {
    let resposta = chamar_pg(
        &estado.pg,
        "GetUserIdentity",
        tenant_id,
        user_id,
        &[],
        serde_json::json!({ "id": user_id }),
    )
    .await
    .ok()?;

    // Usuário desativado perde o acesso do agente junto: `is_active` false é
    // recusa, não lista de escopos vazia.
    if !resposta
        .get("is_active")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        return None;
    }
    // Superusuário não conecta agente (D4); se a conta virou superusuária
    // depois de conectar, o grant deixa de valer.
    if resposta
        .get("is_superuser")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        return None;
    }

    // `derivar_escopos` devolve também a ORIGEM dos escopos, que é o instrumento
    // da D4 (plano `regras-do-bot-e-permissoes`). Registrá-la aqui não é enfeite:
    // um agente conectado renova token a cada 15 minutos, então este caminho tem
    // muito mais volume que o login do painel. Sem o campo, a medição de quantas
    // sessões dependem do fallback pelo `role` ficaria cega justamente onde o
    // número é maior.
    let (escopos, origem) = application::auth::login::derivar_escopos(false, &resposta);
    tracing::debug!(
        origem_escopos = origem.como_str(),
        user_id,
        "escopos atuais relidos para emissão de token MCP"
    );
    Some(escopos)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Regressão do defeito que impediu o PRIMEIRO consentimento real
    /// (12/09/2026): com o `axum::Form` (serde_urlencoded), o formulário
    /// respondia
    ///
    /// > Failed to deserialize form body: escopos: invalid type: string
    /// > "atendimentos:read", expected a sequence
    ///
    /// assim que UMA caixa vinha marcada — o caso mais comum, não um extremo.
    ///
    /// O teste exercita o mesmo desserializador que o handler usa
    /// (`serde_html_form`, via `axum_extra::extract::Form`), e não uma
    /// aproximação: é a troca desse desserializador que corrige o defeito, e um
    /// teste contra `serde_urlencoded` passaria a mentir se alguém revertesse.
    #[test]
    fn consentimento_aceita_uma_caixa_marcada_e_varias() {
        // Uma só — o caso que quebrava.
        let uma: ConsentForm =
            serde_html_form::from_str("ticket=t1&decisao=aprovar&escopos=atendimentos%3Aread")
                .expect("uma caixa marcada precisa desserializar");
        assert_eq!(uma.escopos, vec!["atendimentos:read"]);
        assert_eq!(uma.decisao, "aprovar");

        // Várias: a chave repetida tem de virar lista, e não sobrescrever. Se
        // só a última sobrevivesse, o usuário marcaria cinco permissões e
        // receberia uma — pior que o erro, porque falha em silêncio.
        let varias: ConsentForm = serde_html_form::from_str(
            "ticket=t1&decisao=aprovar\
             &escopos=atendimentos%3Aread\
             &escopos=clientes%3Aread\
             &escopos=operacional%3Aread",
        )
        .expect("varias caixas precisam desserializar");
        assert_eq!(
            varias.escopos,
            vec!["atendimentos:read", "clientes:read", "operacional:read"]
        );

        // Nenhuma: o campo some do corpo, e `#[serde(default)]` responde. O
        // handler trata isso como "nada concedido" e devolve `invalid_scope`.
        let nenhuma: ConsentForm =
            serde_html_form::from_str("ticket=t1&decisao=aprovar").expect("ausente e valido");
        assert!(nenhuma.escopos.is_empty());
    }

    #[test]
    fn config_normaliza_barra_final_do_issuer_e_do_resource() {
        // Barra final quebraria a comparação de `issuer` (que o cliente compara
        // como string) e a de `aud` no resource server.
        std::env::set_var("MCP_OAUTH_ISSUER", "https://auth.exemplo.com/");
        std::env::set_var("MCP_OAUTH_RESOURCE", "https://mcp.exemplo.com/");
        let cfg = OauthConfig::from_env();
        assert_eq!(cfg.issuer, "https://auth.exemplo.com");
        assert_eq!(cfg.resource, "https://mcp.exemplo.com");
        std::env::remove_var("MCP_OAUTH_ISSUER");
        std::env::remove_var("MCP_OAUTH_RESOURCE");
    }

    #[test]
    fn janela_de_revogacao_arredonda_para_cima() {
        let cfg = OauthConfig {
            issuer: String::new(),
            resource: String::new(),
            access_ttl_s: 900,
            refresh_ttl_s: 0,
            token_interno_ttl_s: 0,
            servico_secreto: String::new(),
        };
        assert_eq!(cfg.janela_revogacao_min(), 15);

        let cfg = OauthConfig {
            access_ttl_s: 901,
            ..cfg
        };
        // 901s são 15min e 1s: dizer "15 minutos" ao usuário seria mentir por
        // baixo. Arredonda para cima.
        assert_eq!(cfg.janela_revogacao_min(), 16);
    }

    #[test]
    fn teto_de_vida_do_consentimento_e_lido_da_configuracao() {
        // O default de 30 dias vem de MCP_REFRESH_TTL_S. O teste existe para que
        // trocar a unidade (segundos → dias, por exemplo) não passe em silêncio:
        // o número é comparado contra a idade do grant EM SEGUNDOS.
        std::env::remove_var("MCP_REFRESH_TTL_S");
        let cfg = OauthConfig::from_env();
        assert_eq!(cfg.refresh_ttl_s, 30 * 24 * 3600);
    }

    #[test]
    fn traceparent_tem_o_formato_w3c() {
        let tp = novo_traceparent();
        let partes: Vec<&str> = tp.split('-').collect();
        assert_eq!(partes.len(), 4);
        assert_eq!(partes[0], "00");
        assert_eq!(partes[1].len(), 32);
        assert_eq!(partes[2].len(), 16);
    }
}

#[cfg(test)]
mod tests_csp_do_fluxo {
    use super::{csp_do_fluxo, origem_de_retorno};

    #[test]
    fn libera_a_origem_exata_do_retorno() {
        let csp = csp_do_fluxo("https://claude.ai/api/mcp/auth_callback");
        assert!(
            csp.contains("form-action 'self' https://claude.ai;"),
            "{csp}"
        );
        assert!(csp.contains("default-src 'none'"));
        assert_eq!(
            origem_de_retorno("http://localhost:33418/callback").as_deref(),
            Some("http://localhost:33418")
        );
        assert_eq!(
            origem_de_retorno("http://127.0.0.1/callback").as_deref(),
            Some("http://127.0.0.1")
        );
        assert_eq!(
            origem_de_retorno("cursor://anysphere/mcp").as_deref(),
            Some("cursor:")
        );
    }

    #[test]
    fn endereco_invalido_fica_so_com_self() {
        assert_eq!(origem_de_retorno("nao e url"), None);
        let csp = csp_do_fluxo("nao e url");
        assert!(csp.contains("form-action 'self';"), "{csp}");
    }
}
