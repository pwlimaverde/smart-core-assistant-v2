//! Contrato genérico de CANAL: o que um provedor declara sobre si mesmo.
//!
//! O descritor é DADO, não código. A borda (`runtime_api`) devolve o descritor
//! como está e o app monta a tela de configuração e conexão a partir dele: o
//! modo de conexão escolhe o fluxo (QR, token, OAuth, trecho de código) e o
//! `config_schema` vira o formulário. Um provedor novo aparece na tela sem
//! nenhuma tela escrita para ele.
//!
//! Regra de honestidade: capacidade declarada é capacidade implementada. As
//! opcionais (presença, recibos, reações, mídia, foto) não são escritas à mão —
//! [`descritor_efetivo`] as deriva da descoberta de traits da fachada
//! [`crate::MessagingProvider`], então o descritor não tem como prometer o que o
//! adaptador não faz.

use serde::{Deserialize, Serialize};

/// Tipo de canal. Hoje só WhatsApp tem adaptador; o chat de site está no
/// catálogo como planejado (o gateway de WebSocket é um serviço próprio).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ChannelKind {
    Whatsapp,
    Webchat,
    Telegram,
    Instagram,
    Messenger,
}

/// Como a conexão nasce. Escolhe o fluxo da tela, não o provedor.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    /// Lê um QR no celular (Evolution Go).
    QrPairing,
    /// Credenciais coladas num formulário (Cloud API da Meta, bot do Telegram).
    Token,
    /// Autorização por redirecionamento (Instagram/Messenger via login da Meta).
    Oauth,
    /// Cadastro embutido do provedor (Embedded Signup da Meta).
    Embedded,
    /// Trecho de código para colar no site (chat de site).
    CopySnippet,
}

/// Maturidade do provedor neste servidor.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Estagio {
    /// Em produção, comportamento coberto.
    Estavel,
    /// Adaptador existe, mas nem tudo do canal foi implementado.
    Experimental,
    /// Só o descritor: não há adaptador. Nunca habilitado.
    Planejado,
}

/// Como o adaptador endereça a conexão no provedor.
///
/// A Evolution usa o NOME da instância; a Cloud API usa o `phone_number_id`
/// (gravado em `whatsapp_instance.instance_id`, o id externo). Os handlers do
/// `data_whatsapp` passam um ou outro conforme o descritor, sem saber qual
/// provedor é.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EnderecoNoProvedor {
    Nome,
    IdExterno,
}

/// Tipo de um campo do formulário de configuração.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TipoCampo {
    Texto,
    /// Não é ecoado na tela nem devolvido pelo servidor.
    Segredo,
    Telefone,
    Url,
}

/// Um campo do formulário que o provedor pede para conectar.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CampoConfiguracao {
    pub chave: String,
    pub rotulo: String,
    pub tipo: TipoCampo,
    pub obrigatorio: bool,
    /// Onde a pessoa encontra o valor. Vai como dica embaixo do campo.
    pub ajuda: String,
}

impl CampoConfiguracao {
    pub fn novo(
        chave: &str,
        rotulo: &str,
        tipo: TipoCampo,
        obrigatorio: bool,
        ajuda: &str,
    ) -> Self {
        Self {
            chave: chave.into(),
            rotulo: rotulo.into(),
            tipo,
            obrigatorio,
            ajuda: ajuda.into(),
        }
    }
}

/// O que o canal sabe fazer. Vocabulário fechado: a tela decide o que mostrar
/// por estes nomes, e um nome novo exige mudar o app de propósito.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum Capacidade {
    /// Pareamento por QR ([`crate::QrPairing`]).
    QrPairing,
    /// Conexão por credenciais ([`crate::TokenConnect`]).
    TokenConnect,
    /// Consulta o estado da conexão no provedor.
    Health,
    /// Religa uma sessão que caiu sem novo pareamento.
    Reconexao,
    /// Encerra a sessão no provedor sem apagar a conexão.
    Desconectar,
    /// O servidor grava a URL do webhook no provedor. Sem ela, o webhook é
    /// configurado no painel do provedor (caso da Meta: um app por ambiente).
    RegistraWebhook,
    EnvioTexto,
    EnvioMidia,
    Presenca,
    Recibos,
    Reacoes,
    DownloadMidia,
    FotoPerfil,
    Templates,
}

/// Tudo que um provedor declara: identidade, modo de conexão, formulário e
/// capacidades.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChannelDescriptor {
    /// Chave do registro e de `whatsapp_instance.provider` (`evolution`,
    /// `meta_cloud`, `webchat`).
    pub provider: String,
    pub kind: ChannelKind,
    pub nome: String,
    pub descricao: String,
    pub estagio: Estagio,
    pub connection_mode: ConnectionMode,
    pub endereco: EnderecoNoProvedor,
    pub config_schema: Vec<CampoConfiguracao>,
    pub capacidades: Vec<Capacidade>,
    /// Eventos que o servidor assina ao registrar o webhook (vocabulário do
    /// provedor). Vazio quando o provedor não aceita registro pelo servidor.
    pub eventos_webhook: Vec<String>,
}

impl ChannelDescriptor {
    pub fn suporta(&self, c: Capacidade) -> bool {
        self.capacidades.contains(&c)
    }
}

/// O descritor com as capacidades OPCIONAIS derivadas dos traits que o
/// adaptador realmente implementa. É este que sai para a borda.
///
/// As capacidades do núcleo (QR, token, health, reconexão…) vêm do descritor
/// declarado; as opcionais, quando declaradas à mão, são descartadas e
/// recalculadas — prometer presença sem implementar `PresenceControl` não
/// sobrevive a esta função.
pub fn descritor_efetivo(p: &dyn crate::MessagingProvider) -> ChannelDescriptor {
    let mut d = p.descritor();
    let derivadas = [
        Capacidade::Presenca,
        Capacidade::Recibos,
        Capacidade::Reacoes,
        Capacidade::DownloadMidia,
        Capacidade::FotoPerfil,
        Capacidade::QrPairing,
        Capacidade::TokenConnect,
    ];
    d.capacidades.retain(|c| !derivadas.contains(c));
    let presentes = [
        (Capacidade::Presenca, p.presence().is_some()),
        (Capacidade::Recibos, p.read_receipts().is_some()),
        (Capacidade::Reacoes, p.reactions().is_some()),
        (Capacidade::DownloadMidia, p.media_downloader().is_some()),
        (Capacidade::FotoPerfil, p.profiles().is_some()),
        (Capacidade::QrPairing, p.qr_pairing().is_some()),
        (Capacidade::TokenConnect, p.token_connect().is_some()),
    ];
    for (c, tem) in presentes {
        if tem {
            d.capacidades.push(c);
        }
    }
    d.capacidades.sort();
    d.capacidades.dedup();
    d
}

/// Canais que estão no contrato mas ainda não têm adaptador. Entram na tela
/// como "planejado", nunca habilitados: mostram ao tenant o que vem e provam
/// que o contrato comporta o canal.
pub fn catalogo_planejado() -> Vec<ChannelDescriptor> {
    vec![ChannelDescriptor {
        provider: "webchat".into(),
        kind: ChannelKind::Webchat,
        nome: "Chat do site".into(),
        descricao: "Widget de conversa para colar no seu site. Depende do serviço \
                    webchat_gateway (WebSocket), ainda não implantado."
            .into(),
        estagio: Estagio::Planejado,
        connection_mode: ConnectionMode::CopySnippet,
        endereco: EnderecoNoProvedor::IdExterno,
        config_schema: vec![CampoConfiguracao::novo(
            "dominio_permitido",
            "Domínio do site",
            TipoCampo::Url,
            true,
            "Só páginas deste domínio podem abrir o chat (ex.: https://loja.com.br).",
        )],
        capacidades: vec![Capacidade::EnvioTexto],
        eventos_webhook: vec![],
    }]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::*;
    use async_trait::async_trait;
    use secrecy::SecretString;

    /// Provedor de teste que DECLARA presença e QR sem implementar nenhum dos
    /// dois — o descritor efetivo tem que desmenti-lo.
    struct Mentiroso {
        com_qr: bool,
    }

    #[async_trait]
    impl InstanceManager for Mentiroso {
        fn provider_name(&self) -> &'static str {
            "mentiroso"
        }
        async fn create_instance(
            &self,
            _: &str,
            _: Option<&SecretString>,
        ) -> Result<CreateInstanceResult, MessagingProviderError> {
            Err(MessagingProviderError::Unsupported("create"))
        }
        async fn delete_instance(&self, _: &str) -> Result<(), MessagingProviderError> {
            Ok(())
        }
        async fn connect_instance(
            &self,
            _: &str,
            _: &SecretString,
            _: &WebhookConfig,
        ) -> Result<(), MessagingProviderError> {
            Ok(())
        }
        async fn disconnect_instance(
            &self,
            _: &str,
            _: &SecretString,
        ) -> Result<(), MessagingProviderError> {
            Ok(())
        }
        async fn reconnect_instance(
            &self,
            _: &str,
            _: &SecretString,
        ) -> Result<(), MessagingProviderError> {
            Ok(())
        }
        async fn get_connection_state(
            &self,
            _: &str,
            _: &SecretString,
        ) -> Result<ConnectionState, MessagingProviderError> {
            Ok(ConnectionState::Unknown)
        }
        async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError> {
            Ok(vec![])
        }
    }

    #[async_trait]
    impl MessageSender for Mentiroso {
        async fn send_text(
            &self,
            _: &str,
            _: &SecretString,
            _: &str,
            _: &str,
        ) -> Result<SendMessageResult, MessagingProviderError> {
            Err(MessagingProviderError::Unsupported("send_text"))
        }
        async fn send_media(
            &self,
            _: &str,
            _: &SecretString,
            _: &str,
            _: MediaType,
            _: &str,
            _: Option<&str>,
            _: Option<&str>,
        ) -> Result<SendMessageResult, MessagingProviderError> {
            Err(MessagingProviderError::Unsupported("send_media"))
        }
    }

    #[async_trait]
    impl QrPairing for Mentiroso {
        async fn get_qr_code(
            &self,
            _: &str,
            _: &SecretString,
        ) -> Result<String, MessagingProviderError> {
            Ok("qr".into())
        }
    }

    impl MessagingProvider for Mentiroso {
        fn descritor(&self) -> ChannelDescriptor {
            ChannelDescriptor {
                provider: "mentiroso".into(),
                kind: ChannelKind::Whatsapp,
                nome: "x".into(),
                descricao: "x".into(),
                estagio: Estagio::Experimental,
                connection_mode: ConnectionMode::QrPairing,
                endereco: EnderecoNoProvedor::Nome,
                config_schema: vec![],
                capacidades: vec![
                    Capacidade::Presenca,
                    Capacidade::QrPairing,
                    Capacidade::EnvioTexto,
                ],
                eventos_webhook: vec![],
            }
        }
        fn qr_pairing(&self) -> Option<&dyn QrPairing> {
            self.com_qr.then_some(self as &dyn QrPairing)
        }
    }

    #[test]
    fn capacidade_opcional_declarada_sem_trait_e_descartada() {
        let d = descritor_efetivo(&Mentiroso { com_qr: true });
        assert!(
            !d.suporta(Capacidade::Presenca),
            "presença sem PresenceControl"
        );
        assert!(d.suporta(Capacidade::QrPairing));
        // Núcleo declarado continua.
        assert!(d.suporta(Capacidade::EnvioTexto));
    }

    #[test]
    fn qr_declarado_sem_implementacao_some_do_descritor() {
        let d = descritor_efetivo(&Mentiroso { com_qr: false });
        assert!(!d.suporta(Capacidade::QrPairing));
    }

    #[test]
    fn vocabulario_do_descritor_sai_em_snake_case() {
        // A tela compara por estes textos: mudar a serialização quebra o app.
        let v = serde_json::to_value(descritor_efetivo(&Mentiroso { com_qr: true })).unwrap();
        assert_eq!(v["connection_mode"], "qr_pairing");
        assert_eq!(v["kind"], "whatsapp");
        assert_eq!(v["estagio"], "experimental");
        assert_eq!(v["endereco"], "nome");
        let caps: Vec<&str> = v["capacidades"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c.as_str().unwrap())
            .collect();
        assert!(caps.contains(&"qr_pairing"));
        assert!(caps.contains(&"envio_texto"));
    }

    #[test]
    fn catalogo_planejado_nunca_promete_conexao() {
        for d in catalogo_planejado() {
            assert_eq!(d.estagio, Estagio::Planejado, "{}", d.provider);
            assert!(!d.suporta(Capacidade::QrPairing));
            assert!(!d.suporta(Capacidade::TokenConnect));
        }
    }

    #[test]
    fn registro_lista_em_ordem_estavel() {
        let reg = ProviderRegistry::builder()
            .register(std::sync::Arc::new(Mentiroso { com_qr: true }))
            .build();
        let nomes: Vec<&str> = reg.listar().iter().map(|p| p.provider_name()).collect();
        assert_eq!(nomes, vec!["mentiroso"]);
    }
}
