"""Assinante do canal de invalidação de config (Redis Pub/Sub).

Sem isto, mudar um prompt ou a persona no painel só teria efeito depois de
reiniciar o contêiner (ou de expirar o TTL de 24h da chave). Com o canal, o
Rust reescreve `tenant:config:<uuid>` e publica o `tenant_id`; aqui a cópia em
RAM é descartada e a próxima mensagem já usa o valor novo.

Ver `doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`, seção 3.3.
"""

from __future__ import annotations

import asyncio

from loguru import logger
from redis.asyncio import Redis

from ia_engine.config.cache import TenantConfigCache

CANAL_INVALIDACAO = "tenant:config:invalidate"

# Espera antes de reassinar quando a conexão cai. O Redis é local (rede do
# compose): uma reconexão rápida é barata, e ficar sem o canal significa servir
# config velha em silêncio.
_BACKOFF_SEGUNDOS = 5.0


async def escutar_invalidacoes(
    redis: Redis, cache: TenantConfigCache, *, parar: asyncio.Event | None = None
) -> None:
    """Escuta o canal e invalida o cache, reconectando indefinidamente.

    Args:
        redis: Cliente dedicado — `subscribe` monopoliza a conexão, então não
            reaproveite o mesmo cliente usado para `get`.
        cache: Cache a invalidar.
        parar: Encerra o laço quando sinalizado (usado nos testes e no shutdown).
    """
    # `parar` é verificado no FIM de cada ciclo, não no começo: garante ao menos
    # uma assinatura completa. No shutdown real quem interrompe a espera em
    # `listen()` é o cancelamento da task, não este evento.
    while True:
        try:
            pubsub = redis.pubsub()
            await pubsub.subscribe(CANAL_INVALIDACAO)
            logger.info("Escutando invalidações de config em {}", CANAL_INVALIDACAO)
            try:
                async for mensagem in pubsub.listen():
                    if mensagem.get("type") != "message":
                        continue
                    await _aplicar(mensagem.get("data"), cache)
                    if parar is not None and parar.is_set():
                        break
            finally:
                await pubsub.aclose()
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning(
                "Canal de invalidação caiu ({}); reassinando em {}s",
                type(exc).__name__,
                _BACKOFF_SEGUNDOS,
            )
        if parar is not None and parar.is_set():
            break
        await asyncio.sleep(_BACKOFF_SEGUNDOS)


async def _aplicar(dado: object, cache: TenantConfigCache) -> None:
    """Invalida o tenant informado; payload vazio invalida tudo.

    O Rust publica o `tenant_id` em texto puro. Um payload que não seja um
    tenant reconhecível derruba o cache inteiro em vez de ser ignorado: servir
    config velha é pior que um punhado de leituras a mais no Redis.
    """
    tenant_id = dado.decode("utf-8") if isinstance(dado, bytes) else str(dado or "")
    tenant_id = tenant_id.strip()
    if tenant_id:
        await cache.invalidate(tenant_id)
    else:
        await cache.invalidate_all()
