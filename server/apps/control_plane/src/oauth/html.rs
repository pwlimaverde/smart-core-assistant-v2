//! As duas telas do fluxo de autorização: login e consentimento.
//!
//! HTML escrito à mão, sem motor de template. Duas razões: são duas páginas, e
//! um motor a mais é uma dependência a mais numa superfície voltada à internet.
//! O preço é que **o escape é responsabilidade nossa** — daí [`escapar`] e o
//! teste que prova que o nome do cliente não vira script.
//!
//! Tudo que vem de fora passa por [`escapar`]: `client_name` e `client_uri` vêm
//! do documento do terceiro, e `state` vem do cliente. Nenhum deles é confiável.

use super::cimd::ClientMetadata;
use super::scopes;

/// Escape de HTML para contexto de texto e de atributo entre aspas duplas.
///
/// Cobre `& < > " '`. Não serve para contexto de JavaScript nem de URL — e não
/// precisa: nenhum valor de terceiro é interpolado dentro de `<script>` ou de
/// `href` nestas páginas. Se um dia for, este comentário está errado e o escape
/// também.
pub fn escapar(bruto: &str) -> String {
    let mut saida = String::with_capacity(bruto.len());
    for c in bruto.chars() {
        match c {
            '&' => saida.push_str("&amp;"),
            '<' => saida.push_str("&lt;"),
            '>' => saida.push_str("&gt;"),
            '"' => saida.push_str("&quot;"),
            '\'' => saida.push_str("&#x27;"),
            _ => saida.push(c),
        }
    }
    saida
}

/// Tokens do `design_system_module`, transcritos.
///
/// Transcritos e não importados: o AS é Rust e serve HTML estático, sem acesso
/// ao pacote Dart. O que se copia são **tokens** (paleta, raio, espaçamento) —
/// copiar componentes é que criaria duas implementações para manter.
///
/// A paleta é a do produto: acento `gold` (#A98F71) sobre neutros `stone`, e o
/// escuro quente (#14110F) em vez do cinza-azulado genérico. Antes desta tela
/// usar a paleta, ela era a única superfície do produto que não parecia com
/// ele — logo a que pede a senha.
const ESTILO: &str = r#"<style>
:root {
  --gold: #A98F71; --gold-600: #8B7355; --gold-50: #F5EFE7;
  --stone-900: #1C1917; --stone-700: #44403C; --stone-500: #78716C;
  --stone-300: #D6D3D1; --stone-200: #E7E5E4; --stone-100: #F5F5F4;
  --surface: #FFFFFF; --fundo: var(--stone-100);
  --fg: var(--stone-900); --fg-muted: var(--stone-500); --borda: var(--stone-300);
  --aviso: #D97706; --aviso-bg: rgba(217,119,6,.10);
  --perigo: #DC2626; --perigo-bg: rgba(220,38,38,.10);
  --r-sm: 6px; --r-md: 8px; --r-card: 10px; --r-panel: 16px;
  --s-xs: 4px; --s-sm: 8px; --s-md: 16px; --s-lg: 24px; --s-xl: 32px;
  color-scheme: light dark;
}
* { box-sizing: border-box; }
body {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  margin: 0; display: flex; align-items: center; justify-content: center;
  min-height: 100vh; background: var(--fundo); color: var(--fg);
  padding: var(--s-md); line-height: 1.5;
}
.cartao {
  background: var(--surface); border: 1px solid var(--borda);
  border-radius: var(--r-panel); padding: var(--s-xl); width: 100%;
  max-width: 460px; box-shadow: 0 1px 3px rgba(28,25,23,.06);
}
/* Marca: o losango do produto + o nome. Serve para reconhecer a tela num
   piscar — que é exatamente o que distingue autorização de phishing. */
.marca {
  display: flex; align-items: center; gap: var(--s-sm);
  margin-bottom: var(--s-lg); padding-bottom: var(--s-md);
  border-bottom: 1px solid var(--stone-200);
}
.marca svg { flex: 0 0 auto; }
.marca span { font-size: 14px; font-weight: 600; letter-spacing: .01em; }
h1 { font-size: 20px; line-height: 1.3; margin: 0 0 var(--s-xs); font-weight: 650; }
p.sub { color: var(--fg-muted); font-size: 14px; margin: 0 0 var(--s-lg); }
label { display: block; font-size: 13px; font-weight: 600; margin: var(--s-md) 0 var(--s-xs); }
input[type=email], input[type=password] {
  width: 100%; padding: 11px 12px; border: 1px solid var(--borda);
  border-radius: var(--r-md); font-size: 15px; background: var(--surface);
  color: var(--fg);
}
input[type=email]:focus, input[type=password]:focus {
  outline: none; border-color: var(--gold);
  box-shadow: 0 0 0 3px rgba(169,143,113,.20);
}
button {
  width: 100%; margin-top: var(--s-lg); padding: 12px; border: 0;
  border-radius: var(--r-md); background: var(--gold-600); color: #fff;
  font-size: 15px; font-weight: 600; cursor: pointer;
}
button:hover { background: var(--gold); }
button:focus-visible { outline: 2px solid var(--gold); outline-offset: 2px; }
button.secundario {
  background: transparent; color: var(--fg-muted); margin-top: var(--s-sm);
  border: 1px solid var(--borda);
}
button.secundario:hover { background: var(--stone-100); color: var(--fg); }
.escopos {
  list-style: none; padding: 0; margin: 0; border: 1px solid var(--borda);
  border-radius: var(--r-card);
}
.escopos li {
  padding: 11px 14px; border-bottom: 1px solid var(--stone-200); font-size: 14px;
  display: flex; gap: var(--s-sm); align-items: flex-start;
}
.escopos li:last-child { border-bottom: 0; }
.escopos input { margin-top: 3px; accent-color: var(--gold-600); }
.tag {
  font-size: 11px; font-weight: 700; color: var(--aviso);
  background: var(--aviso-bg); border-radius: var(--r-sm); padding: 1px 6px;
  margin-left: var(--s-xs);
}
.alerta {
  background: var(--aviso-bg); border: 1px solid rgba(217,119,6,.30);
  color: var(--aviso); border-radius: var(--r-md); padding: 12px 14px;
  font-size: 13px; margin-bottom: var(--s-md);
}
.erro {
  background: var(--perigo-bg); border: 1px solid rgba(220,38,38,.30);
  color: var(--perigo); border-radius: var(--r-md); padding: 11px 14px;
  font-size: 13px; margin-bottom: var(--s-md);
}
.destino {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px;
  background: var(--gold-50); border-radius: var(--r-sm); padding: 2px 6px;
  word-break: break-all;
}
.rodape {
  margin-top: var(--s-lg); padding-top: var(--s-md);
  border-top: 1px solid var(--stone-200);
  font-size: 12px; color: var(--fg-muted);
}
/* O fluxo do Claude no celular abre esta página num navegador pequeno. */
@media (max-width: 420px) {
  body { padding: var(--s-sm); align-items: flex-start; }
  .cartao { padding: var(--s-lg) var(--s-md); border-radius: var(--r-card); }
  h1 { font-size: 18px; }
}
@media (prefers-color-scheme: dark) {
  :root {
    --surface: #1F1B18; --fundo: #14110F;
    --fg: #F5EFE7; --fg-muted: #8B8175;
    --borda: #3A342E; --stone-100: #25201C; --stone-200: #2B2622;
    --gold-50: #25201C;
  }
  .cartao { box-shadow: none; }
  button.secundario:hover { background: #25201C; }
}
</style>"#;

/// Losango do produto, em SVG inline.
///
/// Inline, e não `<img src>`: o CSP é `default-src 'none'`, e afrouxá-lo por um
/// logotipo seria mau negócio. SVG inline é parte do documento — não é recurso
/// buscado, e não abre porta nenhuma.
const MARCA: &str = r##"<div class="marca">
<svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
  <path d="M10 1.5 18.5 10 10 18.5 1.5 10Z" fill="none" stroke="#A98F71" stroke-width="1.6" stroke-linejoin="round"/>
  <path d="M10 6.2 13.8 10 10 13.8 6.2 10Z" fill="#A98F71"/>
</svg>
<span>Smart Core Assistant</span>
</div>"##;

fn pagina(titulo: &str, corpo: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{titulo}</title>
{ESTILO}
</head>
<body><div class="cartao">{MARCA}{corpo}</div></body>
</html>"#
    )
}

/// Tela 1: login. O ticket carrega a requisição de autorização já validada — o
/// formulário não reenvia `redirect_uri`, `scope` nem `state`, justamente para
/// que não possam ser trocados entre a validação e o consentimento.
pub fn tela_login(ticket: &str, client_name: &str, erro: Option<&str>) -> String {
    let bloco_erro = erro
        .map(|e| format!(r#"<div class="erro">{}</div>"#, escapar(e)))
        .unwrap_or_default();

    pagina(
        "Entrar — Smart Core Assistant",
        &format!(
            r#"<h1>Entrar na sua conta</h1>
<p class="sub"><strong>{nome}</strong> quer acesso ao seu Smart Core Assistant.
Entre para ver exatamente o que ele está pedindo.</p>
{bloco_erro}
<form method="post" action="/oauth/authorize/login" autocomplete="on">
  <input type="hidden" name="ticket" value="{ticket}">
  <label for="email">E-mail</label>
  <input id="email" type="email" name="email" required autocomplete="username" autofocus>
  <label for="senha">Senha</label>
  <input id="senha" type="password" name="senha" required autocomplete="current-password">
  <button type="submit">Entrar</button>
</form>
<p class="rodape">Você ainda não autorizou nada. A próxima tela mostra o que será
concedido, e nada acontece sem a sua aprovação.</p>"#,
            nome = escapar(client_name),
            ticket = escapar(ticket),
        ),
    )
}

/// Tela 2: consentimento.
///
/// Três coisas obrigatórias por spec estão aqui: o **nome do cliente**, o
/// **hostname do `redirect_uri`** (que é o que o usuário consegue reconhecer — o
/// nome é escolhido pelo próprio cliente e pode mentir) e um **aviso reforçado**
/// quando o cliente só declara redirect para a própria máquina.
///
/// A quarta, e a que o plano chama de regra do subconjunto, não é um aviso: é o
/// fato de `escopos_ofertaveis` já ter recebido apenas o que este usuário possui.
/// Não existe caixa a marcar para algo que ele não tem.
pub fn tela_consentimento(
    ticket: &str,
    metadata: &ClientMetadata,
    redirect_uri: &str,
    escopos_ofertaveis: &[&str],
    escopos_pre_marcados: &[String],
    somente_localhost: bool,
    janela_revogacao_min: i64,
) -> String {
    let host_destino = url::Url::parse(redirect_uri)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .unwrap_or_else(|| redirect_uri.to_string());

    let aviso_localhost = if somente_localhost {
        r#"<div class="alerta"><strong>Atenção.</strong> Este aplicativo devolve o
acesso para um endereço na sua própria máquina. Isso é normal em programas de
computador instalados, mas se você não iniciou esta conexão a partir de um
programa que abriu agora, <strong>cancele</strong>.</div>"#
    } else {
        ""
    };

    let itens: String = escopos_ofertaveis
        .iter()
        .map(|escopo| {
            let desc = scopes::descricao(escopo);
            let rotulo = desc.map(|d| d.rotulo).unwrap_or(escopo);
            let tag = if desc.map(|d| d.escrita).unwrap_or(false) {
                r#"<span class="tag">altera dados</span>"#
            } else {
                ""
            };
            let marcado = if escopos_pre_marcados.is_empty()
                || escopos_pre_marcados.iter().any(|e| e == escopo)
            {
                " checked"
            } else {
                ""
            };
            format!(
                r#"<li><input type="checkbox" id="e_{id}" name="escopos" value="{val}"{marcado}>
<label for="e_{id}" style="margin:0;font-weight:400">{rotulo}{tag}</label></li>"#,
                id = escapar(&escopo.replace([':', '.'], "_")),
                val = escapar(escopo),
                rotulo = escapar(rotulo),
            )
        })
        .collect();

    pagina(
        "Autorizar acesso — Smart Core Assistant",
        &format!(
            r#"<h1>Autorizar {nome}</h1>
<p class="sub">Depois de autorizar, <strong>{nome}</strong> poderá fazer no seu
Smart Core Assistant tudo o que estiver marcado abaixo — e só isso. O acesso é
devolvido para <span class="destino">{host}</span>.</p>
{aviso_localhost}
<form method="post" action="/oauth/authorize/consent">
  <input type="hidden" name="ticket" value="{ticket}">
  <ul class="escopos">{itens}</ul>
  <button type="submit" name="decisao" value="aprovar">Autorizar</button>
  <button type="submit" name="decisao" value="negar" class="secundario">Cancelar</button>
</form>
<p class="rodape">Você pode desconectar este aplicativo a qualquer momento em
<strong>Configurações → Aplicativos conectados</strong>. Ao desconectar, o acesso
já em andamento termina em até {janela} minutos.</p>"#,
            nome = escapar(&metadata.client_name),
            host = escapar(&host_destino),
            ticket = escapar(ticket),
            janela = janela_revogacao_min,
        ),
    )
}

/// Página de erro do fluxo — usada quando não há `redirect_uri` confiável para
/// onde devolver o erro (a spec proíbe redirecionar para uma URI não validada).
pub fn tela_erro(titulo: &str, detalhe: &str) -> String {
    pagina(
        "Não foi possível autorizar",
        &format!(
            r#"<h1>{titulo}</h1>
<div class="erro">{detalhe}</div>
<p class="rodape">Nada foi autorizado. Volte ao aplicativo e tente conectar de
novo; se o erro se repetir, o problema está na configuração dele.</p>"#,
            titulo = escapar(titulo),
            detalhe = escapar(detalhe),
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata_maliciosa() -> ClientMetadata {
        ClientMetadata {
            client_id: "https://mau.example/c".to_string(),
            client_name: r#"<script>alert(1)</script>"#.to_string(),
            redirect_uris: vec!["https://mau.example/cb".to_string()],
            client_uri: None,
        }
    }

    #[test]
    fn escapar_cobre_os_cinco_caracteres_perigosos() {
        assert_eq!(
            escapar(r#"<a href="x">&'"#),
            "&lt;a href=&quot;x&quot;&gt;&amp;&#x27;"
        );
    }

    #[test]
    fn nome_do_cliente_nao_vira_script_na_tela_de_consentimento() {
        // `client_name` vem do documento do terceiro. É o vetor de XSS mais
        // direto do fluxo inteiro.
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "https://mau.example/cb",
            &["atendimentos:read"],
            &[],
            false,
            15,
        );
        assert!(!html.contains("<script>"));
        assert!(html.contains("&lt;script&gt;"));
    }

    #[test]
    fn nome_do_cliente_nao_vira_script_na_tela_de_login() {
        let html = tela_login("t", r#"<img src=x onerror=alert(1)>"#, None);
        assert!(!html.contains("<img"));
    }

    #[test]
    fn consentimento_mostra_o_host_do_redirect_e_nao_so_o_nome() {
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "https://mau.example/cb",
            &["atendimentos:read"],
            &[],
            false,
            15,
        );
        // O usuário precisa poder desconfiar do destino mesmo quando o nome é
        // convincente.
        assert!(html.contains("mau.example"));
    }

    #[test]
    fn consentimento_avisa_quando_o_cliente_e_so_localhost() {
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "http://localhost:33418/cb",
            &["atendimentos:read"],
            &[],
            true,
            15,
        );
        assert!(html.contains("própria máquina"));
    }

    #[test]
    fn consentimento_so_lista_os_escopos_ofertaveis() {
        // A regra do subconjunto: quem chama já filtrou, e a tela não inventa.
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "https://mau.example/cb",
            &["atendimentos:read"],
            &[],
            false,
            15,
        );
        assert!(html.contains("Ver atendimentos e mensagens"));
        assert!(!html.contains("tenant:admin"));
        assert!(!html.contains("Administrar tudo"));
    }

    #[test]
    fn consentimento_marca_escrita_de_forma_visivel() {
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "https://mau.example/cb",
            &["atendimentos:write"],
            &[],
            false,
            15,
        );
        assert!(html.contains("altera dados"));
    }

    #[test]
    fn consentimento_diz_a_janela_de_revogacao_em_numero() {
        // "termina em até 15 minutos" é honestidade contratual, não texto de
        // enfeite: é a janela real do access token.
        let html = tela_consentimento(
            "t",
            &metadata_maliciosa(),
            "https://mau.example/cb",
            &["atendimentos:read"],
            &[],
            false,
            15,
        );
        assert!(html.contains("15 minutos"));
    }

    #[test]
    fn tela_de_erro_nao_reflete_html_do_atacante() {
        let html = tela_erro("Erro", "<script>roubar()</script>");
        assert!(!html.contains("<script>roubar"));
    }
}
