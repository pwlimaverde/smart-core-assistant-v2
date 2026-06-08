use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::RedisError;
use crate::keys;

/// Registro de um refresh token guardado no Redis (indexado pelo hash do token).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RegistroRefresh {
    pub user_id: i32,
    /// `None` para superusuários (sem tenant) ou enquanto o tenant não foi resolvido.
    pub tenant_id: Option<Uuid>,
    /// Identifica a família de rotação (todos os tokens derivados de um mesmo login).
    pub family_id: String,
    /// Marcado `true` quando o token já foi usado para rotacionar. Um segundo uso indica
    /// reuso (possível roubo) e dispara a revogação da família inteira.
    pub rotacionado: bool,
}

/// Store de refresh tokens com rotação e detecção de reuso por família.
///
/// O caller é responsável por gerar o token aleatório e por passar apenas o seu **hash**
/// (ex.: SHA-256) — o token em claro nunca deve tocar o Redis.
pub struct RefreshTokenStore {
    con: ConnectionManager,
}

impl RefreshTokenStore {
    pub fn new(con: ConnectionManager) -> Self {
        Self { con }
    }

    /// Armazena um novo refresh token (hash) e o associa à sua família, com TTL.
    // `token_hash` é omitido do span: é material de credencial, nunca deve ir para o log.
    #[tracing::instrument(
        skip(self, token_hash),
        fields(user_id, tenant_id = ?tenant_id, family_id = %family_id, ttl_segundos),
        err
    )]
    pub async fn armazenar(
        &mut self,
        token_hash: &str,
        user_id: i32,
        tenant_id: Option<Uuid>,
        family_id: &str,
        ttl_segundos: u64,
    ) -> Result<(), RedisError> {
        let registro = RegistroRefresh {
            user_id,
            tenant_id,
            family_id: family_id.to_string(),
            rotacionado: false,
        };
        let valor = serde_json::to_string(&registro)?;
        let _: () = redis::cmd("SET")
            .arg(keys::chave_refresh(token_hash))
            .arg(valor)
            .arg("EX")
            .arg(ttl_segundos)
            .query_async(&mut self.con)
            .await?;

        // Indexa o token na família e renova o TTL do conjunto.
        let chave_fam = keys::chave_refresh_familia(family_id);
        let _: i64 = self.con.sadd(&chave_fam, token_hash).await?;
        let _: bool = self.con.expire(&chave_fam, ttl_segundos as i64).await?;
        Ok(())
    }

    /// Valida e marca o token como rotacionado (uso único). Retorna o registro original
    /// (com `rotacionado = false`) para que o caller emita um novo par mantendo a família.
    ///
    /// - `NotFound`: token inexistente/expirado/revogado.
    /// - `TokenReuse`: token já rotacionado → a família inteira é revogada antes de retornar.
    #[tracing::instrument(skip(self, token_hash))]
    pub async fn validar_e_rotacionar(
        &mut self,
        token_hash: &str,
    ) -> Result<RegistroRefresh, RedisError> {
        let chave = keys::chave_refresh(token_hash);
        let valor: Option<String> = self.con.get(&chave).await?;
        let Some(serializado) = valor else {
            tracing::debug!("refresh token inexistente, expirado ou já revogado");
            return Err(RedisError::NotFound);
        };
        let registro: RegistroRefresh = serde_json::from_str(&serializado)?;

        if registro.rotacionado {
            // Evento de segurança: reuso de token rotacionado indica possível roubo.
            tracing::warn!(
                user_id = registro.user_id,
                tenant_id = ?registro.tenant_id,
                family_id = %registro.family_id,
                "reuso de refresh token detectado — revogando a família inteira"
            );
            self.revogar_familia(&registro.family_id).await?;
            return Err(RedisError::TokenReuse);
        }

        // Marca como rotacionado preservando o TTL restante (KEEPTTL, Redis 6+),
        // para que um reuso futuro seja detectável até a expiração natural.
        let mut atualizado = registro.clone();
        atualizado.rotacionado = true;
        let valor_atualizado = serde_json::to_string(&atualizado)?;
        let _: () = redis::cmd("SET")
            .arg(&chave)
            .arg(valor_atualizado)
            .arg("KEEPTTL")
            .query_async(&mut self.con)
            .await?;

        Ok(registro)
    }

    /// Revoga um refresh token específico (remove o registro).
    #[tracing::instrument(skip(self, token_hash), err)]
    pub async fn revogar(&mut self, token_hash: &str) -> Result<(), RedisError> {
        let _: i64 = self.con.del(keys::chave_refresh(token_hash)).await?;
        Ok(())
    }

    /// Revoga todos os refresh tokens de uma família (logout global / resposta a reuso).
    #[tracing::instrument(skip(self), fields(family_id = %family_id), err)]
    pub async fn revogar_familia(&mut self, family_id: &str) -> Result<(), RedisError> {
        let chave_fam = keys::chave_refresh_familia(family_id);
        let membros: Vec<String> = self.con.smembers(&chave_fam).await?;
        for hash in &membros {
            let _: i64 = self.con.del(keys::chave_refresh(hash)).await?;
        }
        let _: i64 = self.con.del(&chave_fam).await?;
        tracing::info!(
            tokens_revogados = membros.len(),
            "família de refresh tokens revogada"
        );
        Ok(())
    }
}

/// Blocklist de access tokens (JWT) revogados, indexada pelo `jti`.
pub struct TokenBlocklist {
    con: ConnectionManager,
}

impl TokenBlocklist {
    pub fn new(con: ConnectionManager) -> Self {
        Self { con }
    }

    /// Bloqueia um `jti` por `ttl_segundos` (deve ser o tempo restante de vida do access token).
    // `jti` identifica um token específico; é omitido do span por prudência.
    #[tracing::instrument(skip(self, jti), fields(ttl_segundos), err)]
    pub async fn bloquear(&mut self, jti: &str, ttl_segundos: u64) -> Result<(), RedisError> {
        let _: () = redis::cmd("SET")
            .arg(keys::chave_blocklist(jti))
            .arg("1")
            .arg("EX")
            .arg(ttl_segundos)
            .query_async(&mut self.con)
            .await?;
        Ok(())
    }

    /// Indica se o `jti` está na blocklist.
    #[tracing::instrument(level = "debug", skip(self, jti), err)]
    pub async fn esta_bloqueado(&mut self, jti: &str) -> Result<bool, RedisError> {
        let existe: bool = self.con.exists(keys::chave_blocklist(jti)).await?;
        Ok(existe)
    }
}
