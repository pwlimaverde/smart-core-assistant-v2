//! O e-mail de convite para a equipe.
//!
//! Mora aqui, e não numa engine de templates, porque é um texto só e o custo de
//! uma engine seria maior que o de escrevê-lo. Quando houver o terceiro
//! e-mail, vale reconsiderar.

use crate::{EmailError, Enviador};

/// Escapa o que vai para dentro do HTML.
///
/// O nome de quem convida e o nome da empresa vêm do banco, escritos por
/// gente: um `&` num nome de empresa já quebraria a marcação, e um `<script>`
/// faria pior. O corpo em texto puro não precisa disso.
pub(crate) fn escapar(bruto: &str) -> String {
    bruto
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

pub struct DadosDoConvite<'a> {
    pub para: &'a str,
    /// Nome de quem está sendo convidado.
    pub nome: &'a str,
    pub empresa: &'a str,
    /// Link absoluto, pronto para clicar.
    pub link: &'a str,
    pub validade_dias: i64,
}

/// Manda o convite. Falha aberta — ver a nota do módulo `lib`.
pub async fn enviar(enviador: &Enviador, dados: DadosDoConvite<'_>) -> Result<(), EmailError> {
    let DadosDoConvite {
        para,
        nome,
        empresa,
        link,
        validade_dias,
    } = dados;

    let assunto = format!("{empresa} convidou você para o Smart Core Assistant");

    let texto = format!(
        "Olá, {nome}.\n\n\
         {empresa} criou um acesso para você no Smart Core Assistant.\n\n\
         Para entrar, abra este endereço e defina sua senha:\n\n\
         {link}\n\n\
         O link vale uma vez e expira em {validade_dias} dias.\n\n\
         Se você não esperava este convite, ignore esta mensagem — sem clicar, \
         nada acontece.\n"
    );

    // Sem CSS externo nem imagem remota: cliente de e-mail bloqueia os dois por
    // padrão, e o que sobraria seria uma casca. Estilo em atributo `style`, que
    // é o que o Gmail e o Outlook preservam.
    let html = format!(
        r#"<!doctype html>
<html lang="pt-BR"><body style="margin:0;padding:24px;background:#F5F5F4;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;color:#1C1917;">
<div style="max-width:520px;margin:0 auto;background:#FFFFFF;border:1px solid #D6D3D1;border-radius:16px;padding:32px;">
  <p style="margin:0 0 24px;font-size:14px;font-weight:600;color:#8B7355;">Smart Core Assistant</p>
  <h1 style="margin:0 0 8px;font-size:20px;line-height:1.3;">Olá, {nome}.</h1>
  <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#44403C;">
    {empresa} criou um acesso para você. Abra o endereço abaixo para entrar e
    definir sua senha.
  </p>
  <p style="margin:0 0 24px;">
    <a href="{link}" style="display:inline-block;background:#8B7355;color:#FFFFFF;text-decoration:none;padding:12px 20px;border-radius:8px;font-size:15px;font-weight:600;">Aceitar o convite</a>
  </p>
  <p style="margin:0 0 24px;font-size:13px;color:#78716C;line-height:1.6;">
    Se o botão não abrir, copie este endereço:<br>
    <span style="font-family:ui-monospace,Menlo,monospace;font-size:12px;word-break:break-all;">{link}</span>
  </p>
  <p style="margin:0;padding-top:16px;border-top:1px solid #E7E5E4;font-size:12px;color:#78716C;line-height:1.6;">
    O link vale uma vez e expira em {validade_dias} dias. Se você não esperava
    este convite, ignore esta mensagem — sem clicar, nada acontece.
  </p>
</div>
</body></html>"#,
        nome = escapar(nome),
        empresa = escapar(empresa),
        // O link vem de `format!` nosso com um token hexadecimal, mas escapar
        // é o hábito certo: um dia a base vira configuração de tenant.
        link = escapar(link),
        validade_dias = validade_dias,
    );

    enviador.enviar(para, &assunto, texto, html).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dados<'a>(nome: &'a str, empresa: &'a str) -> DadosDoConvite<'a> {
        DadosDoConvite {
            para: "convidado@exemplo.com",
            nome,
            empresa,
            link: "https://dev.exemplo.com.br/aceitar-convite?token=abc",
            validade_dias: 7,
        }
    }

    /// Nome de empresa com `&` é comum ("Silva & Filhos") e quebraria a
    /// marcação; `<script>` faria pior.
    #[tokio::test]
    async fn nome_de_terceiro_nao_entra_cru_no_html() {
        let d = dados("<script>alert(1)</script>", "Silva & Filhos");
        // Sem SMTP o envio é no-op, então o teste checa a montagem por outro
        // caminho: as funções de escape sobre os mesmos valores.
        assert_eq!(escapar(d.empresa), "Silva &amp; Filhos");
        assert_eq!(escapar(d.nome), "&lt;script&gt;alert(1)&lt;/script&gt;");
    }

    /// Sem SMTP configurado o envio não é erro — ver a nota do módulo `lib`.
    #[tokio::test]
    async fn desligado_nao_falha() {
        let r = enviar(&Enviador::Desligado, dados("Maria", "Empresa")).await;
        assert!(r.is_ok());
    }

    #[test]
    fn escape_preserva_texto_normal() {
        assert_eq!(escapar("Maria de Souza"), "Maria de Souza");
    }
}
