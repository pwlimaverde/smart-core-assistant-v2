//! Cache de mídia em disco, endereçado por hash (sha256).
//!
//! Baixa uma única vez a partir de uma URL pré-assinada (GET HTTP puro na URL já
//! pronta — este crate NÃO fala S3/R2 nem linka `aws-sdk-s3`), nomeia o arquivo
//! pelo hash e nunca rebaixa se ele já existe íntegro. O diretório base é
//! parâmetro de inicialização (ex.: `%APPDATA%/SmartCoreAssistant/media_cache`),
//! nunca hardcode.
//!
//! **Sanitização:** o cache não guarda segredo/PII em claro — só o binário da
//! mídia, nomeado pelo próprio hash. A URL pré-assinada (credencial temporária)
//! não é persistida.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::error::{LocalEngineError, LocalResult};

/// Cache de mídia local endereçado por conteúdo.
pub struct MediaCache {
    base_dir: PathBuf,
    http: reqwest::Client,
}

impl MediaCache {
    /// Cria o cache sobre um diretório base, com um cliente HTTP próprio.
    pub fn new(base_dir: impl Into<PathBuf>) -> Self {
        Self {
            base_dir: base_dir.into(),
            http: reqwest::Client::new(),
        }
    }

    /// Cria o cache reaproveitando um `reqwest::Client` externo.
    pub fn with_client(base_dir: impl Into<PathBuf>, http: reqwest::Client) -> Self {
        Self {
            base_dir: base_dir.into(),
            http,
        }
    }

    /// Caminho local de uma mídia identificada pelo seu sha256 (hex).
    pub fn caminho_para(&self, sha256_hex: &str) -> PathBuf {
        self.base_dir.join(sha256_hex)
    }

    /// Garante a mídia em disco e devolve seu caminho.
    ///
    /// Se já existir com o hash correto, retorna sem rede. Caso contrário baixa
    /// da URL pré-assinada, **valida o sha256** e só então persiste (grava em
    /// `.tmp` e renomeia — evita deixar lixo corrompido no cache). Hash divergente
    /// aborta com erro.
    pub async fn ensure(&self, url: &str, sha256_esperado: &str) -> LocalResult<PathBuf> {
        let destino = self.caminho_para(sha256_esperado);

        if destino.exists() {
            if Self::hash_arquivo(&destino).await? == sha256_esperado {
                return Ok(destino);
            }
            // Arquivo presente mas corrompido: descarta antes de rebaixar.
            tokio::fs::remove_file(&destino).await.ok();
        }

        tokio::fs::create_dir_all(&self.base_dir).await?;

        let bytes = self
            .http
            .get(url)
            .send()
            .await
            .map_err(|e| LocalEngineError::Media(e.to_string()))?
            .error_for_status()
            .map_err(|e| LocalEngineError::Media(e.to_string()))?
            .bytes()
            .await
            .map_err(|e| LocalEngineError::Media(e.to_string()))?;

        let hash = Self::hash_bytes(&bytes);
        if hash != sha256_esperado {
            return Err(LocalEngineError::Media(format!(
                "hash divergente: esperado {sha256_esperado}, obtido {hash}"
            )));
        }

        let tmp = self.base_dir.join(format!("{sha256_esperado}.tmp"));
        tokio::fs::write(&tmp, &bytes).await?;
        tokio::fs::rename(&tmp, &destino).await?;
        Ok(destino)
    }

    /// sha256 (hex) de um buffer.
    pub fn hash_bytes(bytes: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(bytes);
        let digest = hasher.finalize();
        let mut hex = String::with_capacity(digest.len() * 2);
        for b in digest {
            let _ = write!(hex, "{b:02x}");
        }
        hex
    }

    async fn hash_arquivo(path: &Path) -> LocalResult<String> {
        let bytes = tokio::fs::read(path).await?;
        Ok(Self::hash_bytes(&bytes))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_bytes_confere_com_vetor_conhecido() {
        // sha256("abc")
        assert_eq!(
            MediaCache::hash_bytes(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[tokio::test]
    async fn ensure_retorna_do_cache_sem_rede_quando_ja_integro() {
        let sufixo = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!("le_media_{sufixo}"));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let cache = MediaCache::new(&dir);

        let conteudo = b"conteudo de midia";
        let hash = MediaCache::hash_bytes(conteudo);
        tokio::fs::write(cache.caminho_para(&hash), conteudo)
            .await
            .unwrap();

        // URL inválida de propósito: se tocar a rede, falha; deve vir do cache.
        let caminho = cache
            .ensure("http://127.0.0.1:0/inexistente", &hash)
            .await
            .unwrap();
        assert_eq!(caminho, cache.caminho_para(&hash));

        tokio::fs::remove_dir_all(&dir).await.ok();
    }

    fn dir_temp_unico(prefixo: &str) -> PathBuf {
        let sufixo = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!("{prefixo}_{sufixo}"))
    }

    #[tokio::test]
    async fn ensure_sem_cache_e_com_rede_indisponivel_retorna_erro_de_midia() {
        let dir = dir_temp_unico("le_media_miss");
        let cache = MediaCache::new(&dir);

        // Porta `0` nunca aceita conexão — falha de rede imediata e determinística.
        let resultado = cache
            .ensure("http://127.0.0.1:0/arquivo", "hash-qualquer")
            .await;

        assert!(matches!(resultado, Err(LocalEngineError::Media(_))));
        tokio::fs::remove_dir_all(&dir).await.ok();
    }

    #[tokio::test]
    async fn ensure_com_arquivo_cacheado_corrompido_descarta_antes_de_tentar_rebaixar() {
        let dir = dir_temp_unico("le_media_corrupt");
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let cache = MediaCache::new(&dir);

        let hash_esperado = MediaCache::hash_bytes(b"conteudo correto");
        // Grava um arquivo cujo conteúdo NÃO bate com o hash esperado.
        let destino = cache.caminho_para(&hash_esperado);
        tokio::fs::write(&destino, b"conteudo errado")
            .await
            .unwrap();
        assert!(destino.exists());

        let resultado = cache
            .ensure("http://127.0.0.1:0/inexistente", &hash_esperado)
            .await;

        // A rede está indisponível, então o rebaixamento falha — mas o arquivo
        // corrompido já deve ter sido removido antes da tentativa.
        assert!(resultado.is_err());
        assert!(
            !destino.exists(),
            "arquivo corrompido deveria ter sido descartado do cache"
        );

        tokio::fs::remove_dir_all(&dir).await.ok();
    }

    #[test]
    fn caminho_para_junta_o_diretorio_base_com_o_hash() {
        let cache = MediaCache::new(PathBuf::from("/tmp/media"));
        let caminho = cache.caminho_para("abc123");
        assert_eq!(caminho, PathBuf::from("/tmp/media").join("abc123"));
    }

    #[test]
    fn with_client_reaproveita_um_cliente_http_externo() {
        let http = reqwest::Client::new();
        let cache = MediaCache::with_client("/tmp/media", http);
        assert_eq!(
            cache.caminho_para("x"),
            PathBuf::from("/tmp/media").join("x")
        );
    }
}
