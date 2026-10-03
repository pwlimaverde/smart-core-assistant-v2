//! Ticket de download de release (instalador Windows).
//!
//! Formato: `base64url(claims_json) "." base64url(hmac_sha256(segredo, parte_1))`,
//! ambos sem padding. As claims viajam DENTRO do ticket — o verificador não
//! precisa adivinhar `jti`/`iat`; ele recalcula a assinatura sobre os bytes
//! recebidos (comparação em tempo constante via `Mac::verify_slice`) e só então
//! confia no conteúdo.
//!
//! Quem assina: `control_plane` (RPC `IssueReleaseDownloadTicket`).
//! Quem verifica: `releases_server` (`GET /download/{versao}/{arquivo}?t=`).
//! O segredo compartilhado é `RELEASES_DOWNLOAD_SECRET`.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub mod manifesto {
    //! `installers.json` de um canal: gravado pelo `releases_server` a cada
    //! publicação e lido pelo `control_plane` antes de assinar um ticket.
    use serde::{Deserialize, Serialize};

    /// Um instalador publicado.
    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
    pub struct Instalador {
        pub version: String,
        pub file_name: String,
        pub sha256: String,
        pub size_bytes: i64,
        #[serde(default)]
        pub release_notes_md: String,
        pub published_at_ms: i64,
    }

    /// Manifesto de um canal.
    #[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
    pub struct ManifestoInstaladores {
        pub installers: Vec<Instalador>,
    }

    impl ManifestoInstaladores {
        /// Versão pedida; vazia = a publicada por último.
        pub fn escolher(&self, versao: &str) -> Option<&Instalador> {
            if versao.is_empty() {
                self.installers.iter().max_by_key(|i| i.published_at_ms)
            } else {
                self.installers.iter().find(|i| i.version == versao)
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        fn inst(v: &str, em: i64) -> Instalador {
            Instalador {
                version: v.into(),
                file_name: format!("{v}-Setup.exe"),
                sha256: String::new(),
                size_bytes: 1,
                release_notes_md: String::new(),
                published_at_ms: em,
            }
        }

        #[test]
        fn escolhe_pela_versao_ou_a_mais_recente() {
            let m = ManifestoInstaladores {
                installers: vec![inst("0.2.0", 20), inst("0.1.0", 10)],
            };
            assert_eq!(m.escolher("").unwrap().version, "0.2.0");
            assert_eq!(m.escolher("0.1.0").unwrap().version, "0.1.0");
            assert!(m.escolher("9.9.9").is_none());
            assert!(ManifestoInstaladores::default().escolher("").is_none());
        }
    }
}

/// Versão do formato das claims.
pub const VERSAO_FORMATO: u8 = 1;

/// Validade do ticket: 5 minutos (decisão D3 — reutilizável dentro do TTL).
pub const TTL_SEGUNDOS: i64 = 300;

/// Tolerância de relógio entre quem assina e quem verifica.
pub const TOLERANCIA_RELOGIO_SEGUNDOS: i64 = 60;

/// Tamanho máximo aceito para um ticket (defesa contra entrada gigante).
const TAMANHO_MAXIMO: usize = 2048;

/// Claims do ticket. Só identificadores — nunca segredo, JWT ou dado pessoal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Claims {
    /// Versão do formato (sempre [`VERSAO_FORMATO`]).
    pub v: u8,
    /// Identificador da chave (permite rotação futura do segredo).
    pub kid: String,
    /// Id único do ticket (vai para os logs no lugar do ticket inteiro).
    pub jti: String,
    /// Id do superusuário que pediu o link.
    pub sub: i32,
    /// Versão da release.
    pub ver: String,
    /// Nome do arquivo autorizado.
    pub file: String,
    /// Canal (`beta`/`stable`).
    pub ch: String,
    /// Emitido em (unix, segundos).
    pub iat: i64,
    /// Expira em (unix, segundos).
    pub exp: i64,
}

/// Motivos de recusa. Fechado de propósito: quem chama decide o que logar.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum TicketError {
    #[error("segredo de assinatura vazio")]
    SegredoVazio,
    #[error("ticket malformado")]
    Malformado,
    #[error("assinatura inválida")]
    AssinaturaInvalida,
    #[error("ticket expirado")]
    Expirado,
    #[error("ticket emitido no futuro")]
    EmitidoNoFuturo,
    #[error("versão de formato não suportada")]
    FormatoNaoSuportado,
}

fn mac(segredo: &[u8]) -> Result<HmacSha256, TicketError> {
    if segredo.is_empty() {
        return Err(TicketError::SegredoVazio);
    }
    // HMAC aceita chave de qualquer tamanho; o erro só existe na assinatura do trait.
    HmacSha256::new_from_slice(segredo).map_err(|_| TicketError::SegredoVazio)
}

/// Assina as claims e devolve o ticket.
pub fn assinar(claims: &Claims, segredo: &[u8]) -> Result<String, TicketError> {
    let json = serde_json::to_vec(claims).map_err(|_| TicketError::Malformado)?;
    let corpo = URL_SAFE_NO_PAD.encode(json);
    let mut m = mac(segredo)?;
    m.update(corpo.as_bytes());
    let assinatura = URL_SAFE_NO_PAD.encode(m.finalize().into_bytes());
    Ok(format!("{corpo}.{assinatura}"))
}

/// Verifica assinatura, formato e janela de validade. `agora` em unix segundos.
///
/// Conferir se `ver`/`file` batem com o recurso pedido é responsabilidade de
/// quem chama (depende da rota).
pub fn verificar(ticket: &str, segredo: &[u8], agora: i64) -> Result<Claims, TicketError> {
    if ticket.is_empty() || ticket.len() > TAMANHO_MAXIMO {
        return Err(TicketError::Malformado);
    }
    let (corpo, assinatura) = ticket.split_once('.').ok_or(TicketError::Malformado)?;
    let assinatura = URL_SAFE_NO_PAD
        .decode(assinatura)
        .map_err(|_| TicketError::Malformado)?;

    let mut m = mac(segredo)?;
    m.update(corpo.as_bytes());
    m.verify_slice(&assinatura)
        .map_err(|_| TicketError::AssinaturaInvalida)?;

    let json = URL_SAFE_NO_PAD
        .decode(corpo)
        .map_err(|_| TicketError::Malformado)?;
    let claims: Claims = serde_json::from_slice(&json).map_err(|_| TicketError::Malformado)?;

    if claims.v != VERSAO_FORMATO {
        return Err(TicketError::FormatoNaoSuportado);
    }
    if claims.iat > agora + TOLERANCIA_RELOGIO_SEGUNDOS {
        return Err(TicketError::EmitidoNoFuturo);
    }
    // Recusa também ticket com validade maior que o TTL, mesmo bem assinado.
    if agora >= claims.exp || claims.exp - claims.iat > TTL_SEGUNDOS {
        return Err(TicketError::Expirado);
    }
    Ok(claims)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SEGREDO: &[u8] = b"segredo-de-teste-com-32-bytes-ok!";

    fn claims(iat: i64) -> Claims {
        Claims {
            v: VERSAO_FORMATO,
            kid: "rel-1".into(),
            jti: "0190-teste".into(),
            sub: 7,
            ver: "0.2.0-beta.1".into(),
            file: "SmartCoreTenant-beta-Setup.exe".into(),
            ch: "beta".into(),
            iat,
            exp: iat + TTL_SEGUNDOS,
        }
    }

    #[test]
    fn ida_e_volta_preserva_claims() {
        let c = claims(1_000);
        let t = assinar(&c, SEGREDO).unwrap();
        assert_eq!(verificar(&t, SEGREDO, 1_010).unwrap(), c);
    }

    #[test]
    fn segredo_errado_recusa() {
        let t = assinar(&claims(1_000), SEGREDO).unwrap();
        assert_eq!(
            verificar(&t, b"outro-segredo", 1_010),
            Err(TicketError::AssinaturaInvalida)
        );
    }

    #[test]
    fn claims_adulteradas_recusam() {
        let t = assinar(&claims(1_000), SEGREDO).unwrap();
        let (_, assinatura) = t.split_once('.').unwrap();
        let mut outra = claims(1_000);
        outra.file = "outro.exe".into();
        let corpo = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&outra).unwrap());
        assert_eq!(
            verificar(&format!("{corpo}.{assinatura}"), SEGREDO, 1_010),
            Err(TicketError::AssinaturaInvalida)
        );
    }

    #[test]
    fn expirado_recusa() {
        let t = assinar(&claims(1_000), SEGREDO).unwrap();
        assert_eq!(
            verificar(&t, SEGREDO, 1_000 + TTL_SEGUNDOS),
            Err(TicketError::Expirado)
        );
    }

    #[test]
    fn ttl_maior_que_o_permitido_recusa() {
        let mut c = claims(1_000);
        c.exp = c.iat + TTL_SEGUNDOS * 10;
        let t = assinar(&c, SEGREDO).unwrap();
        assert_eq!(verificar(&t, SEGREDO, 1_010), Err(TicketError::Expirado));
    }

    #[test]
    fn emitido_no_futuro_recusa() {
        let t = assinar(&claims(10_000), SEGREDO).unwrap();
        assert_eq!(
            verificar(&t, SEGREDO, 1_000),
            Err(TicketError::EmitidoNoFuturo)
        );
    }

    #[test]
    fn formato_diferente_recusa() {
        let mut c = claims(1_000);
        c.v = 9;
        let t = assinar(&c, SEGREDO).unwrap();
        assert_eq!(
            verificar(&t, SEGREDO, 1_010),
            Err(TicketError::FormatoNaoSuportado)
        );
    }

    #[test]
    fn entradas_malformadas_recusam() {
        for t in ["", "sem-ponto", "a.b", "!!!.???", &"x".repeat(5000)] {
            assert!(verificar(t, SEGREDO, 0).is_err(), "aceitou {t:?}");
        }
    }

    #[test]
    fn segredo_vazio_recusa_dos_dois_lados() {
        assert_eq!(assinar(&claims(0), b""), Err(TicketError::SegredoVazio));
        let t = assinar(&claims(0), SEGREDO).unwrap();
        assert_eq!(verificar(&t, b"", 1), Err(TicketError::SegredoVazio));
    }
}
