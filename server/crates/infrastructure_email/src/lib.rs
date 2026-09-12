//! Envio de e-mail transacional por SMTP.
//!
//! Existe por um motivo só, por enquanto: o convite de equipe. A v1 mandava o
//! e-mail e a v2 nunca mandou — o convite era criado, o link ficava na tela de
//! quem convidou, e o convidado não recebia nada. Quem convida precisava
//! copiar o link e mandar por fora, o que só funciona se você souber que é
//! isso que se espera.
//!
//! # Falha aberta, de propósito
//!
//! Nada aqui pode derrubar a operação que o chamou. O convite **já está
//! gravado** quando o e-mail sai; se o SMTP estiver fora, o link continua
//! válido e visível na tela. Falhar a criação do convite porque o servidor de
//! e-mail engasgou trocaria um problema pequeno (avisar por outro caminho) por
//! um grande (não conseguir convidar ninguém).
//!
//! # Sem configuração, não é erro
//!
//! Um ambiente sem SMTP configurado (desenvolvimento local, um CI) não deve
//! quebrar nem encher o log de falha. [`Enviador::do_ambiente`] devolve o modo
//! desligado, que registra o que teria mandado e segue.

use lettre::{
    message::{header::ContentType, Mailbox, MultiPart, SinglePart},
    transport::smtp::authentication::Credentials,
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
};
use secrecy::{ExposeSecret, SecretString};

#[derive(Debug, thiserror::Error)]
pub enum EmailError {
    #[error("endereço inválido: {0}")]
    Endereco(String),
    #[error("falha ao montar a mensagem: {0}")]
    Mensagem(String),
    #[error("o servidor de e-mail recusou: {0}")]
    Envio(String),
}

/// De onde sai o e-mail e por onde.
#[derive(Clone)]
pub struct ConfigEmail {
    pub host: String,
    pub porta: u16,
    pub usuario: String,
    pub senha: SecretString,
    /// Endereço no `From`. Precisa ser um remetente que o provedor aceite —
    /// no Brevo, um domínio verificado; caso contrário a mensagem é recusada
    /// ou cai em spam.
    pub remetente: String,
    pub nome_remetente: String,
}

impl ConfigEmail {
    /// Lê do ambiente. `None` quando falta o essencial — ver a nota do módulo
    /// sobre ambiente sem SMTP.
    ///
    /// Os nomes são os mesmos da v1 (`EMAIL_HOST`, `EMAIL_PORT`, …): as
    /// credenciais que já existem continuam servindo, sem ninguém ter de
    /// descobrir um vocabulário novo para o mesmo relay.
    pub fn do_ambiente() -> Option<Self> {
        let usuario = std::env::var("EMAIL_HOST_USER").ok()?;
        let senha = std::env::var("EMAIL_HOST_PASSWORD").ok()?;
        if usuario.is_empty() || senha.is_empty() {
            return None;
        }
        let remetente = std::env::var("EMAIL_FROM").unwrap_or_else(|_| usuario.clone());
        Some(Self {
            host: std::env::var("EMAIL_HOST")
                .unwrap_or_else(|_| "smtp-relay.brevo.com".to_string()),
            porta: std::env::var("EMAIL_PORT")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(587),
            usuario,
            senha: SecretString::from(senha),
            remetente,
            nome_remetente: std::env::var("EMAIL_FROM_NAME")
                .unwrap_or_else(|_| "Smart Core Assistant".to_string()),
        })
    }
}

/// O que manda o e-mail — ou finge que manda, quando não há SMTP configurado.
#[derive(Clone)]
pub enum Enviador {
    Smtp {
        // `Box` porque o transporte tem ~240 bytes e a outra variante não tem
        // nenhum: sem indireção, todo `Enviador::Desligado` — que é o caso de
        // desenvolvimento e do CI — carregaria o tamanho do que não usa.
        transporte: Box<AsyncSmtpTransport<Tokio1Executor>>,
        de: Mailbox,
    },
    /// Sem SMTP no ambiente: registra e segue. Ver a nota do módulo.
    Desligado,
}

impl Enviador {
    pub fn do_ambiente() -> Self {
        match ConfigEmail::do_ambiente() {
            Some(cfg) => match Self::com(cfg) {
                Ok(e) => e,
                Err(erro) => {
                    tracing::error!(%erro, "SMTP configurado mas inválido; e-mails não sairão");
                    Self::Desligado
                }
            },
            None => {
                tracing::info!(
                    "sem EMAIL_HOST_USER/EMAIL_HOST_PASSWORD: e-mails apenas registrados em log"
                );
                Self::Desligado
            }
        }
    }

    pub fn com(cfg: ConfigEmail) -> Result<Self, EmailError> {
        let de: Mailbox = format!("{} <{}>", cfg.nome_remetente, cfg.remetente)
            .parse()
            .map_err(|e| EmailError::Endereco(format!("remetente: {e}")))?;

        // `starttls_relay` e não `relay`: 587 abre em claro e sobe para TLS.
        // `relay` (465) usa TLS implícito, e o Brevo — como a maioria dos
        // relays — atende 587.
        let construtor = if cfg.porta == 465 {
            AsyncSmtpTransport::<Tokio1Executor>::relay(&cfg.host)
        } else {
            AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&cfg.host)
        };

        let transporte = construtor
            .map_err(|e| EmailError::Envio(e.to_string()))?
            .port(cfg.porta)
            .credentials(Credentials::new(
                cfg.usuario.clone(),
                cfg.senha.expose_secret().to_string(),
            ))
            .build();

        Ok(Self::Smtp {
            transporte: Box::new(transporte),
            de,
        })
    }

    pub fn ativo(&self) -> bool {
        matches!(self, Self::Smtp { .. })
    }

    /// Manda uma mensagem com corpo em texto e em HTML.
    ///
    /// As duas versões, sempre: cliente que não renderiza HTML mostra o texto,
    /// e um e-mail só-HTML tem mais chance de ser marcado como spam.
    pub async fn enviar(
        &self,
        para: &str,
        assunto: &str,
        texto: String,
        html: String,
    ) -> Result<(), EmailError> {
        let (transporte, de) = match self {
            Self::Smtp { transporte, de } => (transporte, de),
            Self::Desligado => {
                tracing::info!(para, assunto, "e-mail não enviado: SMTP desligado");
                return Ok(());
            }
        };

        let destino: Mailbox = para
            .parse()
            .map_err(|e| EmailError::Endereco(format!("{para}: {e}")))?;

        let mensagem = Message::builder()
            .from(de.clone())
            .to(destino)
            .subject(assunto)
            .multipart(
                MultiPart::alternative()
                    .singlepart(
                        SinglePart::builder()
                            .header(ContentType::TEXT_PLAIN)
                            .body(texto),
                    )
                    .singlepart(
                        SinglePart::builder()
                            .header(ContentType::TEXT_HTML)
                            .body(html),
                    ),
            )
            .map_err(|e| EmailError::Mensagem(e.to_string()))?;

        transporte
            .send(mensagem)
            .await
            .map_err(|e| EmailError::Envio(e.to_string()))?;
        Ok(())
    }
}

pub mod convite;
