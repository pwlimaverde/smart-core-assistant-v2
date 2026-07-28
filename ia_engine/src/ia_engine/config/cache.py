"""Cache em RAM da config de tenant, com o Redis como fonte.

O `ia_engine` não fala com o Postgres: quem resolve a cascata
`TenantConfig > CoreSettings` é o Rust, que publica o resultado em
`tenant:config:<uuid>`. Aqui só há leitura, cache local e invalidação —
ver `doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`, seção 3.2.

O documento esboça a versão síncrona (`redis.Redis` + `threading.Lock`); esta
implementação usa `redis.asyncio` porque o servidor é `grpc.aio` — um `GET`
bloqueante travaria o event loop e, com ele, todos os RPCs em andamento.
"""

from __future__ import annotations

import asyncio

from loguru import logger
from redis.asyncio import Redis

from ia_engine.config.models import RuntimeConfig


class ConfigIndisponivelError(Exception):
    """Não há config publicada para o tenant (ou o Redis está fora).

    Traduzido para `FAILED_PRECONDITION` no `servicer`: é uma pendência de
    provisionamento — o `data_postgres` publica no boot (pre-warm) e a cada
    alteração —, não um erro interno da IA.
    """


class TenantConfigCache:
    """Cache local por tenant, populado sob demanda a partir do Redis."""

    def __init__(self, redis: Redis) -> None:
        self._redis = redis
        self._lock = asyncio.Lock()
        self._local: dict[str, RuntimeConfig] = {}

    async def get_config(self, tenant_id: str) -> RuntimeConfig:
        """Config do tenant, do cache local ou do Redis.

        Raises:
            ConfigIndisponivelError: chave ausente, ilegível ou Redis fora.
        """
        async with self._lock:
            em_cache = self._local.get(tenant_id)
        if em_cache is not None:
            return em_cache

        chave = f"tenant:config:{tenant_id}"
        try:
            # Fora do lock: I/O de rede não pode bloquear as leituras dos
            # outros tenants. Uma corrida aqui só faz dois requests
            # simultâneos buscarem a mesma chave e gravarem o mesmo valor.
            bruto = await self._redis.get(chave)
        except Exception as exc:
            raise ConfigIndisponivelError(
                f"falha ao ler a config do tenant no Redis: {type(exc).__name__}"
            ) from exc

        if not bruto:
            raise ConfigIndisponivelError(
                f"config não publicada para o tenant {tenant_id}"
            )

        try:
            config = RuntimeConfig.model_validate_json(bruto)
        except Exception as exc:
            # Sem o payload no log: ele carrega as chaves de API decifradas.
            raise ConfigIndisponivelError(
                f"config do tenant ilegível: {type(exc).__name__}"
            ) from exc

        async with self._lock:
            self._local[tenant_id] = config
        return config

    async def invalidate(self, tenant_id: str) -> None:
        """Descarta a cópia local; a próxima leitura relê do Redis."""
        async with self._lock:
            existia = self._local.pop(tenant_id, None) is not None
        if existia:
            logger.info("Config invalidada em memória (tenant={})", tenant_id)

    async def invalidate_all(self) -> None:
        """Descarta tudo. Usado quando a notificação não identifica o tenant."""
        async with self._lock:
            self._local.clear()
        logger.info("Cache de config invalidado por completo")
