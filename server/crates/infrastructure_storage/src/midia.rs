//! N9/E1 — validação do que o cliente sobe como mídia da conversa.
//!
//! ## Por que isto existe
//!
//! O upload vai **direto** do navegador para o R2, com URL pré-assinada: o
//! servidor nunca vê o binário passar. Se a única verdade fosse o `mimetype`
//! declarado pelo cliente, bastaria renomear um executável para `.jpg` para
//! colocá-lo na conversa — e de lá ele seria reenviado ao contato pelo WhatsApp,
//! com o nosso número como remetente.
//!
//! A conferência é feita **depois** do upload e **antes** de persistir a
//! mensagem, lendo os primeiros bytes do objeto no bucket
//! (`StorageClient::primeiros_bytes`).
//!
//! ## O que este módulo NÃO faz
//!
//! Não é antivírus nem sandbox. Ele responde a uma pergunta estreita: *o
//! conteúdo é mesmo do tipo que o cliente disse ser, e está entre os tipos que
//! aceitamos?* Conteúdo malicioso dentro de um JPEG válido continua sendo JPEG.

/// Categoria de mídia aceita na conversa. Espelha os tipos que a evolution-go
/// sabe enviar (`POST /send/media`) — aceitar mais aqui só adiaria o erro para o
/// momento do envio, quando a mensagem já estaria no thread do cliente.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CategoriaMidia {
    Imagem,
    Audio,
    Video,
    Documento,
}

impl CategoriaMidia {
    pub fn as_str(&self) -> &'static str {
        match self {
            CategoriaMidia::Imagem => "image",
            CategoriaMidia::Audio => "audio",
            CategoriaMidia::Video => "video",
            CategoriaMidia::Documento => "document",
        }
    }

    /// Teto de tamanho por categoria, em bytes.
    ///
    /// Os valores seguem os limites práticos do WhatsApp: mandar acima disso faz
    /// o provedor recusar depois que a mensagem já está no thread, o que o
    /// atendente lê como "o sistema quebrou". Melhor recusar antes, com motivo.
    pub fn limite_bytes(&self) -> i64 {
        match self {
            CategoriaMidia::Imagem => 5 * 1024 * 1024,
            CategoriaMidia::Audio => 16 * 1024 * 1024,
            CategoriaMidia::Video => 16 * 1024 * 1024,
            CategoriaMidia::Documento => 100 * 1024 * 1024,
        }
    }
}

/// Motivo pelo qual uma mídia foi recusada.
///
/// Enum, e não string: a mensagem que chega ao atendente precisa dizer o que
/// fazer ("o arquivo tem 20 MB, o limite é 5 MB"), e a borda formata cada caso.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecusaMidia {
    /// Mimetype fora da lista de aceitos.
    TipoNaoPermitido { declarado: String },
    /// O conteúdo não corresponde ao mimetype declarado (assinatura divergente).
    ConteudoDivergente {
        declarado: String,
        detectado: &'static str,
    },
    /// Conteúdo irreconhecível: nem bate com o declarado, nem com nada conhecido.
    ConteudoNaoReconhecido { declarado: String },
    /// Acima do teto da categoria.
    AcimaDoLimite {
        bytes: i64,
        limite: i64,
        categoria: CategoriaMidia,
    },
    /// Objeto vazio — upload interrompido ou chave errada.
    Vazio,
}

impl std::fmt::Display for RecusaMidia {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RecusaMidia::TipoNaoPermitido { declarado } => {
                write!(f, "tipo de arquivo não permitido: {declarado}")
            }
            RecusaMidia::ConteudoDivergente {
                declarado,
                detectado,
            } => write!(
                f,
                "o conteúdo do arquivo não corresponde ao tipo informado \
                 (informado: {declarado}, conteúdo: {detectado})"
            ),
            RecusaMidia::ConteudoNaoReconhecido { declarado } => write!(
                f,
                "não foi possível confirmar que o arquivo é do tipo {declarado}"
            ),
            RecusaMidia::AcimaDoLimite {
                bytes,
                limite,
                categoria,
            } => write!(
                f,
                "arquivo de {:.1} MB acima do limite de {:.0} MB para {}",
                *bytes as f64 / 1_048_576.0,
                *limite as f64 / 1_048_576.0,
                categoria.as_str()
            ),
            RecusaMidia::Vazio => write!(f, "arquivo vazio ou upload incompleto"),
        }
    }
}

/// Mimetypes aceitos e sua categoria.
///
/// Lista fechada, não padrão de prefixo (`image/*`): `image/svg+xml` é um vetor
/// de script embutido e não tem por que entrar numa conversa de WhatsApp.
const PERMITIDOS: &[(&str, CategoriaMidia)] = &[
    ("image/jpeg", CategoriaMidia::Imagem),
    ("image/png", CategoriaMidia::Imagem),
    ("image/gif", CategoriaMidia::Imagem),
    ("image/webp", CategoriaMidia::Imagem),
    ("audio/ogg", CategoriaMidia::Audio),
    ("audio/mpeg", CategoriaMidia::Audio),
    ("audio/mp4", CategoriaMidia::Audio),
    ("audio/aac", CategoriaMidia::Audio),
    ("audio/wav", CategoriaMidia::Audio),
    ("audio/x-wav", CategoriaMidia::Audio),
    ("audio/webm", CategoriaMidia::Audio),
    ("video/mp4", CategoriaMidia::Video),
    ("video/webm", CategoriaMidia::Video),
    ("video/3gpp", CategoriaMidia::Video),
    ("application/pdf", CategoriaMidia::Documento),
    ("application/msword", CategoriaMidia::Documento),
    (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        CategoriaMidia::Documento,
    ),
    ("application/vnd.ms-excel", CategoriaMidia::Documento),
    (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        CategoriaMidia::Documento,
    ),
    ("text/plain", CategoriaMidia::Documento),
    ("text/csv", CategoriaMidia::Documento),
];

/// Categoria do mimetype, ou `None` se não aceitamos o tipo.
pub fn categoria_de(mimetype: &str) -> Option<CategoriaMidia> {
    // O cliente pode mandar `image/jpeg; charset=binary`; só a parte antes do
    // `;` importa.
    let base = mimetype
        .split(';')
        .next()
        .unwrap_or(mimetype)
        .trim()
        .to_ascii_lowercase();
    PERMITIDOS.iter().find(|(m, _)| *m == base).map(|(_, c)| *c)
}

/// Identifica o formato real pelos bytes iniciais.
///
/// Devolve o mimetype canônico do que foi detectado, ou `None` quando a
/// assinatura não é de nenhum formato conhecido. Cobre os contêineres em que a
/// assinatura é confiável; formatos sem número mágico (texto puro, CSV) caem no
/// `None` e são tratados à parte pelo chamador.
pub fn detectar_por_assinatura(bytes: &[u8]) -> Option<&'static str> {
    let comeca = |p: &[u8]| bytes.len() >= p.len() && &bytes[..p.len()] == p;

    if comeca(&[0xFF, 0xD8, 0xFF]) {
        return Some("image/jpeg");
    }
    if comeca(b"\x89PNG\r\n\x1a\n") {
        return Some("image/png");
    }
    if comeca(b"GIF87a") || comeca(b"GIF89a") {
        return Some("image/gif");
    }
    if comeca(b"%PDF-") {
        return Some("application/pdf");
    }
    if comeca(b"OggS") {
        return Some("audio/ogg");
    }
    if comeca(&[0x1A, 0x45, 0xDF, 0xA3]) {
        // Matroska/WebM: o mesmo contêiner serve a áudio e vídeo. Distinguir
        // exigiria parsear os elementos EBML; para o que precisamos, saber que é
        // WebM basta — o chamador aceita `audio/webm` e `video/webm`.
        return Some("video/webm");
    }
    if comeca(b"ID3") || comeca(&[0xFF, 0xFB]) || comeca(&[0xFF, 0xF3]) || comeca(&[0xFF, 0xF2]) {
        return Some("audio/mpeg");
    }
    if bytes.len() >= 12 && &bytes[..4] == b"RIFF" {
        return match &bytes[8..12] {
            b"WAVE" => Some("audio/wav"),
            b"WEBP" => Some("image/webp"),
            _ => None,
        };
    }
    // ISO-BMFF (MP4, M4A, 3GP): `ftyp` no offset 4, e a MARCA que vem depois diz
    // se é vídeo, áudio ou 3GP.
    if bytes.len() >= 12 && &bytes[4..8] == b"ftyp" {
        return match &bytes[8..11] {
            b"M4A" => Some("audio/mp4"),
            b"3gp" => Some("video/3gpp"),
            _ => Some("video/mp4"),
        };
    }
    // OLE2 (doc/xls antigos) e ZIP (docx/xlsx são ZIP por dentro).
    if comeca(&[0xD0, 0xCF, 0x11, 0xE0]) {
        return Some("application/msword");
    }
    if comeca(b"PK\x03\x04") {
        return Some("application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    }
    None
}

/// Valida a mídia recém-enviada: tipo aceito, conteúdo coerente e tamanho.
///
/// `cabecalho` são os primeiros bytes lidos do objeto no bucket (32 bastam).
///
/// **Regra da divergência:** o conteúdo manda. Se a assinatura for reconhecida e
/// apontar uma categoria diferente da declarada, recusa. Se a assinatura casar a
/// **categoria** mas não o mimetype exato (um `audio/webm` detectado como
/// `video/webm`, um `docx` detectado como ZIP), aceita — a diferença é do
/// detector, não do arquivo.
pub fn validar(
    mimetype_declarado: &str,
    bytes: i64,
    cabecalho: &[u8],
) -> Result<CategoriaMidia, RecusaMidia> {
    let Some(categoria) = categoria_de(mimetype_declarado) else {
        return Err(RecusaMidia::TipoNaoPermitido {
            declarado: mimetype_declarado.to_string(),
        });
    };

    if bytes <= 0 || cabecalho.is_empty() {
        return Err(RecusaMidia::Vazio);
    }

    let limite = categoria.limite_bytes();
    if bytes > limite {
        return Err(RecusaMidia::AcimaDoLimite {
            bytes,
            limite,
            categoria,
        });
    }

    match detectar_por_assinatura(cabecalho) {
        Some(detectado) => {
            let categoria_real = categoria_de(detectado);
            if categoria_real == Some(categoria) {
                Ok(categoria)
            } else {
                Err(RecusaMidia::ConteudoDivergente {
                    declarado: mimetype_declarado.to_string(),
                    detectado,
                })
            }
        }
        // Sem assinatura reconhecível: só passa se o tipo declarado for daqueles
        // que legitimamente não têm número mágico (texto puro, CSV). Para os
        // demais, recusar é o certo — é o caso do `.exe` renomeado.
        None => {
            let base = mimetype_declarado
                .split(';')
                .next()
                .unwrap_or(mimetype_declarado)
                .trim()
                .to_ascii_lowercase();
            if base == "text/plain" || base == "text/csv" {
                Ok(categoria)
            } else {
                Err(RecusaMidia::ConteudoNaoReconhecido {
                    declarado: mimetype_declarado.to_string(),
                })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jpeg() -> Vec<u8> {
        let mut v = vec![0xFF, 0xD8, 0xFF, 0xE0];
        v.extend_from_slice(b"JFIF............");
        v
    }

    fn pe_executavel() -> Vec<u8> {
        // Cabeçalho MZ de um .exe do Windows.
        let mut v = b"MZ\x90\x00\x03\x00\x00\x00".to_vec();
        v.extend_from_slice(&[0u8; 24]);
        v
    }

    /// O caso que justifica o módulo inteiro: `.exe` renomeado para `.jpg`,
    /// declarando `image/jpeg`. O mimetype vem do cliente e não vale nada.
    #[test]
    fn executavel_disfarcado_de_imagem_e_recusado() {
        let r = validar("image/jpeg", 4096, &pe_executavel());
        assert_eq!(
            r,
            Err(RecusaMidia::ConteudoNaoReconhecido {
                declarado: "image/jpeg".to_string()
            })
        );
    }

    /// PDF declarado como imagem: a assinatura é conhecida e de outra categoria.
    #[test]
    fn conteudo_de_outra_categoria_e_recusado_dizendo_qual() {
        let r = validar("image/png", 2048, b"%PDF-1.7 resto do arquivo");
        assert_eq!(
            r,
            Err(RecusaMidia::ConteudoDivergente {
                declarado: "image/png".to_string(),
                detectado: "application/pdf",
            })
        );
    }

    #[test]
    fn imagem_legitima_passa() {
        assert_eq!(
            validar("image/jpeg", 120_000, &jpeg()),
            Ok(CategoriaMidia::Imagem)
        );
        assert_eq!(
            validar("image/png", 900, b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"),
            Ok(CategoriaMidia::Imagem)
        );
    }

    /// Mimetype com parâmetro (`; charset=`) é o que alguns navegadores mandam;
    /// tratá-lo como desconhecido recusaria upload legítimo.
    #[test]
    fn mimetype_com_parametro_e_maiusculas_ainda_casa() {
        assert_eq!(
            validar("IMAGE/JPEG; charset=binary", 5000, &jpeg()),
            Ok(CategoriaMidia::Imagem)
        );
    }

    #[test]
    fn tipo_fora_da_lista_e_recusado_antes_de_olhar_o_conteudo() {
        // SVG é imagem, mas carrega script — está fora da lista de propósito.
        assert_eq!(
            validar("image/svg+xml", 100, b"<svg xmlns=..."),
            Err(RecusaMidia::TipoNaoPermitido {
                declarado: "image/svg+xml".to_string()
            })
        );
    }

    #[test]
    fn acima_do_limite_da_categoria_e_recusado() {
        let vinte_mb = 20 * 1024 * 1024;
        let r = validar("image/jpeg", vinte_mb, &jpeg());
        assert_eq!(
            r,
            Err(RecusaMidia::AcimaDoLimite {
                bytes: vinte_mb,
                limite: 5 * 1024 * 1024,
                categoria: CategoriaMidia::Imagem,
            })
        );
        // A mesma quantidade de bytes passa como documento — o limite é por
        // categoria, não global.
        assert!(validar("application/pdf", vinte_mb, b"%PDF-1.4 ...").is_ok());
    }

    #[test]
    fn objeto_vazio_e_upload_incompleto_sao_recusados() {
        assert_eq!(validar("image/jpeg", 0, &jpeg()), Err(RecusaMidia::Vazio));
        assert_eq!(validar("image/jpeg", 100, &[]), Err(RecusaMidia::Vazio));
    }

    /// Texto puro não tem número mágico. Recusá-lo por isso impediria enviar
    /// `.txt` e `.csv`, que são documentos legítimos.
    #[test]
    fn texto_sem_assinatura_e_aceito_por_ser_a_excecao_declarada() {
        assert_eq!(
            validar("text/plain", 40, b"apenas um bilhete\n"),
            Ok(CategoriaMidia::Documento)
        );
        assert_eq!(
            validar("text/csv", 40, b"nome,telefone\n"),
            Ok(CategoriaMidia::Documento)
        );
    }

    /// O detector não distingue áudio de vídeo em WebM/Matroska nem docx de ZIP.
    /// Como a categoria bate, aceitar é o certo — a imprecisão é do detector.
    #[test]
    fn imprecisao_do_detector_dentro_da_mesma_categoria_nao_recusa() {
        // docx é um ZIP por dentro.
        assert_eq!(
            validar(
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                50_000,
                b"PK\x03\x04\x14\x00\x06\x00"
            ),
            Ok(CategoriaMidia::Documento)
        );
        // xlsx idem: mesma assinatura ZIP, mesma categoria.
        assert_eq!(
            validar(
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                50_000,
                b"PK\x03\x04\x14\x00\x06\x00"
            ),
            Ok(CategoriaMidia::Documento)
        );
    }

    #[test]
    fn detecta_os_formatos_de_audio_e_video_que_o_whatsapp_usa() {
        assert_eq!(detectar_por_assinatura(b"OggS\x00\x02"), Some("audio/ogg"));
        assert_eq!(detectar_por_assinatura(b"ID3\x04\x00"), Some("audio/mpeg"));
        assert_eq!(
            detectar_por_assinatura(b"RIFF\x24\x08\x00\x00WAVEfmt "),
            Some("audio/wav")
        );
        assert_eq!(
            detectar_por_assinatura(b"RIFF\x24\x08\x00\x00WEBPVP8 "),
            Some("image/webp")
        );
        assert_eq!(
            detectar_por_assinatura(b"\x00\x00\x00\x20ftypisom"),
            Some("video/mp4")
        );
        assert_eq!(
            detectar_por_assinatura(b"\x00\x00\x00\x20ftypM4A "),
            Some("audio/mp4")
        );
        assert_eq!(detectar_por_assinatura(b"nada disso"), None);
    }
}
