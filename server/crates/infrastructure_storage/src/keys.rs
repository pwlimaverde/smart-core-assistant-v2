//! Layout das chaves de objeto no bucket (namespacing multi-tenant por hash).
//!
//! O endereçamento por conteúdo (`hash`) garante idempotência de upload e casa
//! com a verificação de cache por hash do cliente. Este módulo já entrega o
//! utilitário; o consumo real ocorre quando o `worker` fizer upload de mídia (F4).

use std::fmt;
use uuid::Uuid;

/// Tipo de mídia, usado como segmento da chave para organização por MIME.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaType {
    Audio,
    Image,
    Video,
    Document,
    Sticker,
    Thumb,
}

impl MediaType {
    /// Segmento textual usado na chave do objeto.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Audio => "audio",
            Self::Image => "image",
            Self::Video => "video",
            Self::Document => "document",
            Self::Sticker => "sticker",
            Self::Thumb => "thumb",
        }
    }
}

impl fmt::Display for MediaType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Monta a chave do objeto no layout `media/{tenant}/{instance}/{media_type}/{hash}[.ext]`.
///
/// A raiz `media/` permite aplicar regra de expiração (lifecycle/TTL ≤ 30 dias)
/// ao prefixo; `{tenant}` isola por inquilino; `{instance}` facilita purga em
/// massa de um canal; `{hash}` é o SHA-256 do binário (idempotência).
pub fn chave_midia(
    tenant_id: Uuid,
    instance_id: Uuid,
    media_type: MediaType,
    hash: &str,
    ext: Option<&str>,
) -> String {
    let base = format!("media/{tenant_id}/{instance_id}/{media_type}/{hash}");
    match ext {
        Some(ext) if !ext.is_empty() => format!("{base}.{ext}"),
        _ => base,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn monta_chave_com_extensao() {
        let tenant = Uuid::nil();
        let instance = Uuid::nil();
        let chave = chave_midia(tenant, instance, MediaType::Image, "abc123", Some("jpg"));
        assert_eq!(
            chave,
            "media/00000000-0000-0000-0000-000000000000/00000000-0000-0000-0000-000000000000/image/abc123.jpg"
        );
    }

    #[test]
    fn monta_chave_sem_extensao() {
        let tenant = Uuid::nil();
        let instance = Uuid::nil();
        let chave = chave_midia(tenant, instance, MediaType::Audio, "deadbeef", None);
        assert!(chave.ends_with("/audio/deadbeef"));
        assert!(chave.starts_with("media/"));
    }

    #[test]
    fn media_type_em_texto() {
        assert_eq!(MediaType::Document.as_str(), "document");
        assert_eq!(MediaType::Thumb.to_string(), "thumb");
    }
}
