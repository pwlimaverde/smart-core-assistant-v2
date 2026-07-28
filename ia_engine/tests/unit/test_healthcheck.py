"""Sonda de health usada pelo `healthcheck` do compose (`healthcheck.py`).

Cada teste sobe um `grpc.aio.server` real com o `HealthServicer` oficial e
consulta pela sonda síncrona — é exatamente o caminho que o Docker executa,
sem mock do protocolo.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import grpc
import pytest
from grpc_health.v1 import health, health_pb2, health_pb2_grpc

from ia_engine.healthcheck import check, main


@asynccontextmanager
async def _servidor_health(
    status: health_pb2.HealthCheckResponse.ServingStatus.ValueType,
) -> AsyncIterator[str]:
    """Sobe um servidor gRPC real anunciando o status informado."""
    server = grpc.aio.server()
    servicer = health.aio.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    await servicer.set("", status)
    try:
        yield f"127.0.0.1:{port}"
    finally:
        await server.stop(None)


async def _check_em_thread(address: str) -> bool:
    """A sonda é síncrona; roda fora do loop para não bloquear o servidor."""
    return await asyncio.to_thread(check, address)


@pytest.mark.asyncio
async def test_check_true_quando_servidor_responde_serving():
    async with _servidor_health(
        health_pb2.HealthCheckResponse.SERVING
    ) as address:
        assert await _check_em_thread(address) is True


@pytest.mark.asyncio
async def test_check_false_quando_servidor_responde_not_serving():
    """Processo no ar mas drenando (shutdown gracioso) não é saudável."""
    async with _servidor_health(
        health_pb2.HealthCheckResponse.NOT_SERVING
    ) as address:
        assert await _check_em_thread(address) is False


@pytest.mark.asyncio
async def test_main_retorna_zero_com_endereco_serving():
    async with _servidor_health(
        health_pb2.HealthCheckResponse.SERVING
    ) as address:
        assert await asyncio.to_thread(main, [address]) == 0


def test_check_false_quando_nao_ha_ninguem_escutando():
    # Porta reservada pelo IANA para "discard"; nada escuta nela no runner.
    assert check("127.0.0.1:9", timeout=0.5) is False


def test_main_retorna_um_quando_servidor_esta_fora():
    assert main(["127.0.0.1:9"]) == 1


def test_main_sem_argumento_resolve_endereco_do_ambiente(
    monkeypatch: pytest.MonkeyPatch,
):
    """Sem argumento a sonda usa `Settings`; `0.0.0.0` (bind) precisa virar
    loopback, senão a conexão sai para um destino inválido."""
    enderecos: list[str] = []

    def _falso_check(address: str, **_kwargs: object) -> bool:
        enderecos.append(address)
        return True

    monkeypatch.setenv("GRPC_HOST", "0.0.0.0")
    monkeypatch.setenv("GRPC_PORT", "50060")
    monkeypatch.setattr("ia_engine.healthcheck.check", _falso_check)

    assert main([]) == 0
    assert enderecos == ["127.0.0.1:50060"]


def test_main_sem_argumento_preserva_host_explicito(
    monkeypatch: pytest.MonkeyPatch,
):
    """Só o bind curinga vira loopback; um host nomeado passa intacto."""
    enderecos: list[str] = []

    def _falso_check(address: str, **_kwargs: object) -> bool:
        enderecos.append(address)
        return True

    monkeypatch.setenv("GRPC_HOST", "ia_engine")
    monkeypatch.setenv("GRPC_PORT", "50060")
    monkeypatch.setattr("ia_engine.healthcheck.check", _falso_check)

    assert main([]) == 0
    assert enderecos == ["ia_engine:50060"]
