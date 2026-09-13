//! O e-mail de redefinição de senha (N11 E8).

use crate::{convite::escapar, EmailError, Enviador};

pub struct DadosDaRedefinicao<'a> {
    pub para: &'a str,
    /// Como a pessoa é chamada no e-mail; vazio vira um "Olá." sem nome.
    pub nome: &'a str,
    /// Link absoluto, com o token. Nunca vai para log.
    pub link: &'a str,
    pub validade_min: i64,
}

/// Manda o link de redefinição. Falha aberta — ver a nota do módulo `lib`.
pub async fn enviar(enviador: &Enviador, dados: DadosDaRedefinicao<'_>) -> Result<(), EmailError> {
    let DadosDaRedefinicao {
        para,
        nome,
        link,
        validade_min,
    } = dados;

    let saudacao = if nome.trim().is_empty() {
        "Olá.".to_string()
    } else {
        format!("Olá, {nome}.")
    };
    let assunto = "Redefinição de senha do Smart Core Assistant";

    // A última frase importa mais que a primeira: quem recebe isto sem ter
    // pedido precisa saber, sem clicar em nada, que a senha dele continua a
    // mesma.
    let texto = format!(
        "{saudacao}\n\n\
         Recebemos um pedido para redefinir a senha da sua conta no Smart Core \
         Assistant.\n\n\
         Para escolher uma senha nova, abra este endereço:\n\n\
         {link}\n\n\
         O link vale uma vez e expira em {validade_min} minutos. Ao trocar a \
         senha, as sessões abertas em outros aparelhos são encerradas.\n\n\
         Se não foi você, ignore esta mensagem — sua senha continua a mesma.\n"
    );

    let html = format!(
        r#"<!doctype html>
<html lang="pt-BR"><body style="margin:0;padding:24px;background:#F5F5F4;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;color:#1C1917;">
<div style="max-width:520px;margin:0 auto;background:#FFFFFF;border:1px solid #D6D3D1;border-radius:16px;padding:32px;">
  <p style="margin:0 0 24px;font-size:14px;font-weight:600;color:#8B7355;">Smart Core Assistant</p>
  <h1 style="margin:0 0 8px;font-size:20px;line-height:1.3;">{saudacao}</h1>
  <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#44403C;">
    Recebemos um pedido para redefinir a senha da sua conta. Abra o endereço
    abaixo para escolher uma senha nova.
  </p>
  <p style="margin:0 0 24px;">
    <a href="{link}" style="display:inline-block;background:#8B7355;color:#FFFFFF;text-decoration:none;padding:12px 20px;border-radius:8px;font-size:15px;font-weight:600;">Escolher nova senha</a>
  </p>
  <p style="margin:0 0 24px;font-size:13px;color:#78716C;line-height:1.6;">
    Se o botão não abrir, copie este endereço:<br>
    <span style="font-family:ui-monospace,Menlo,monospace;font-size:12px;word-break:break-all;">{link}</span>
  </p>
  <p style="margin:0;padding-top:16px;border-top:1px solid #E7E5E4;font-size:12px;color:#78716C;line-height:1.6;">
    O link vale uma vez e expira em {validade_min} minutos. Ao trocar a senha,
    as sessões abertas em outros aparelhos são encerradas. Se não foi você,
    ignore esta mensagem — sua senha continua a mesma.
  </p>
</div>
</body></html>"#,
        saudacao = escapar(&saudacao),
        link = escapar(link),
        validade_min = validade_min,
    );

    enviador.enviar(para, assunto, texto, html).await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Sem SMTP configurado o envio não é erro — ver a nota do módulo `lib`.
    #[tokio::test]
    async fn desligado_nao_falha() {
        let r = enviar(
            &Enviador::Desligado,
            DadosDaRedefinicao {
                para: "maria@exemplo.com",
                nome: "Maria",
                link: "https://dev.exemplo.com.br/redefinir-senha?token=abc",
                validade_min: 60,
            },
        )
        .await;
        assert!(r.is_ok());
    }
}
