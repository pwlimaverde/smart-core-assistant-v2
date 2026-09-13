"""RPC ExtrairTextoDocumento (B9 / N10 E5) contra um `grpc.aio.server` real.

Mock só na fronteira externa: o download da URL pré-assinada.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import grpc
import pytest

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.features.extrair_texto.datasources import (
    extrair_texto_datasource as modulo_datasource,
)
from ia_engine.servicer import IaEngineServicer


@asynccontextmanager
async def _stub() -> AsyncIterator[pbg.IaEngineServiceStub]:
    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(IaEngineServicer(), server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as channel:
            yield pbg.IaEngineServiceStub(channel)
    finally:
        await server.stop(None)


def _baixa(monkeypatch: pytest.MonkeyPatch, conteudo: bytes) -> None:
    async def _fake(url: str, **_kwargs: object) -> bytes:
        return conteudo

    monkeypatch.setattr(modulo_datasource, "download_media", _fake)


def _pedido(
    mimetype: str, url: str = "https://r2/assinada"
) -> pb.ExtrairTextoDocumentoRequest:
    return pb.ExtrairTextoDocumentoRequest(
        tenant_id="tenant-1",
        media=pb.MediaRef(url=url, mimetype=mimetype, file_name="material.txt"),
    )


async def test_devolve_texto_formato_e_contagem(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _baixa(monkeypatch, b"Horario: 8h as 18h")
    async with _stub() as stub:
        resp = await stub.ExtrairTextoDocumento(_pedido("text/plain"))
    assert resp.texto == "Horario: 8h as 18h"
    assert resp.formato == "txt"
    assert resp.caracteres == len("Horario: 8h as 18h")


async def test_formato_nao_suportado_e_invalid_argument(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _baixa(monkeypatch, b"\xd0\xcf\x11\xe0")
    async with _stub() as stub:
        with pytest.raises(grpc.aio.AioRpcError) as erro:
            await stub.ExtrairTextoDocumento(_pedido("application/msword"))
    assert erro.value.code() == grpc.StatusCode.INVALID_ARGUMENT
    assert "docx" in (erro.value.details() or "")


async def test_arquivo_sem_texto_e_invalid_argument(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _baixa(monkeypatch, b"   ")
    async with _stub() as stub:
        with pytest.raises(grpc.aio.AioRpcError) as erro:
            await stub.ExtrairTextoDocumento(_pedido("text/plain"))
    assert erro.value.code() == grpc.StatusCode.INVALID_ARGUMENT


async def test_sem_url_aborta_antes_de_baixar() -> None:
    async with _stub() as stub:
        with pytest.raises(grpc.aio.AioRpcError) as erro:
            await stub.ExtrairTextoDocumento(_pedido("text/plain", url=""))
    assert erro.value.code() == grpc.StatusCode.INVALID_ARGUMENT
