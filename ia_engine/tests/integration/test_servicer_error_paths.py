"""Ramos de erro/degradação graciosa dos RPCs (`servicer.py`).

Complementa `test_server_roundtrip.py` (que cobre o caminho feliz de todos
os RPCs): aqui cada teste força a `Failure` de uma feature diferente,
contra um `grpc.aio.server` real, e verifica que o RPC aborta com o
`grpc.StatusCode` correto — uma falha da IA nunca trava o servidor, só o
RPC em questão retorna erro ao chamador. Mock só na fronteira externa (chat
model/embeddings/transcriber fakes, download de mídia monkeypatchado).
"""

from __future__ import annotations

import itertools
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import grpc
import pytest
from langchain_core.messages import AIMessage

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.domain.errors import InvalidRequestError
from ia_engine.features.transcribe import PendingTranscriber
from ia_engine.servicer import IaEngineServicer
from tests.conftest import FakeChatModel, FakeEmbeddings


@asynccontextmanager
async def _stub_for(
    servicer: IaEngineServicer,
) -> AsyncIterator[pbg.IaEngineServiceStub]:
    """Sobe um `grpc.aio.server` real com o servicer já configurado."""
    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as channel:
            yield pbg.IaEngineServiceStub(channel)
    finally:
        await server.stop(None)


def _spec() -> pb.LlmProviderConfig:
    return pb.LlmProviderConfig(provider="openai", model="gpt-4o-mini")


# ------------------------------------------------------------------ Transcribe
@pytest.mark.asyncio
async def test_transcribe_pendente_aborta_com_internal(fake_chat_factory):
    """`PendingTranscriber` (padrão de produção) ainda não integrado a um
    provedor concreto — o RPC não trava, aborta com INTERNAL e mensagem
    sem detalhes sensíveis."""
    servicer = IaEngineServicer(
        chat_model_factory=fake_chat_factory,
        transcriber_factory=lambda _spec: PendingTranscriber(),
    )
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Transcribe(
                pb.TranscribeRequest(
                    tenant_id="t1",
                    media=pb.MediaRef(
                        url="https://r2.example/audio.ogg", mimetype="audio/ogg"
                    ),
                    language="pt",
                    transcription_provider=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


@pytest.mark.asyncio
async def test_transcribe_com_fabrica_padrao_usa_pending_transcriber(
    fake_chat_factory,
):
    """Sem `transcriber_factory` explícito no construtor, o servicer cai no
    padrão de produção (`PendingTranscriber` via `_default_transcriber_factory`)
    — mesmo comportamento gracioso do teste acima, mas exercitando o valor
    padrão do parâmetro em vez de uma fábrica injetada."""
    servicer = IaEngineServicer(chat_model_factory=fake_chat_factory)
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Transcribe(
                pb.TranscribeRequest(
                    tenant_id="t1",
                    media=pb.MediaRef(
                        url="https://r2.example/audio.ogg", mimetype="audio/ogg"
                    ),
                    language="pt",
                    transcription_provider=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


# -------------------------------------------------------------- InterpretMedia
@pytest.mark.asyncio
async def test_interpret_media_download_falho_aborta_com_failed_precondition(
    fake_chat_factory, monkeypatch: pytest.MonkeyPatch
):
    from ia_engine.shared.media import MediaDownloadException

    async def _fake_download_falho(_url: str, **_kwargs: Any) -> bytes:
        raise MediaDownloadException("HTTP 404 ao baixar mídia")

    monkeypatch.setattr(
        "ia_engine.features.interpret_media.datasources"
        ".interpret_media_datasource.download_media",
        _fake_download_falho,
    )
    servicer = IaEngineServicer(chat_model_factory=fake_chat_factory)
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.InterpretMedia(
                pb.InterpretMediaRequest(
                    tenant_id="t1",
                    media=pb.MediaRef(
                        url="https://r2.example/img.jpg", mimetype="image/jpeg"
                    ),
                    media_type="imageMessage",
                    vision_provider=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.FAILED_PRECONDITION
    assert "404" in exc_info.value.details()


# -------------------------------------------------------------------- Analyse
@pytest.mark.asyncio
async def test_analyse_llm_devolve_tipo_inesperado_aborta_com_internal(
    fake_embeddings_factory,
):
    chat = FakeChatModel(
        messages=itertools.cycle([AIMessage(content="")]),
        analyse_value="texto solto, não é dict nem schema",
    )
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=fake_embeddings_factory,
    )
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Analyse(
                pb.AnalyseRequest(
                    tenant_id="t1",
                    mensagem="oi",
                    valid_intent_types="saudacao",
                    llm=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


# ---------------------------------------------------------------------- Embed
@pytest.mark.asyncio
async def test_embed_sem_textos_aborta_com_invalid_argument(fake_embeddings_factory):
    servicer = IaEngineServicer(embeddings_factory=fake_embeddings_factory)
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Embed(
                pb.EmbedRequest(
                    tenant_id="t1", textos=[], embeddings_provider=_spec()
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INVALID_ARGUMENT


@pytest.mark.asyncio
async def test_embed_dimensao_errada_aborta_com_internal():
    """Provedor devolve vetores fora do schema `vector(1536)` — o RPC não
    grava lixo no pgvector, aborta com INTERNAL."""
    servicer = IaEngineServicer(
        embeddings_factory=lambda _spec: FakeEmbeddings(dim=8)
    )
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Embed(
                pb.EmbedRequest(
                    tenant_id="t1",
                    textos=["texto um"],
                    embeddings_provider=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


# ----------------------------------------------------------------- Responder
@pytest.mark.asyncio
async def test_responder_llm_devolve_tipo_inesperado_aborta_com_internal(
    fake_embeddings_factory,
):
    chat = FakeChatModel(
        messages=itertools.cycle([AIMessage(content="")]), resposta_bot=None
    )
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=fake_embeddings_factory,
    )
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Responder(
                pb.ResponderRequest(
                    tenant_id="t1",
                    mensagem="Olá",
                    llm=_spec(),
                    embeddings_provider=_spec(),
                    similarity_threshold=0.5,
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


# ----------------------------------------------------------------- Sentimento
@pytest.mark.asyncio
async def test_sentimento_llm_devolve_tipo_inesperado_aborta_com_internal():
    chat = FakeChatModel(
        messages=itertools.cycle([AIMessage(content="")]), avaliacao=None
    )
    servicer = IaEngineServicer(chat_model_factory=lambda _spec: chat)
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Sentimento(
                pb.SentimentoRequest(
                    tenant_id="t1",
                    historico=pb.ChatHistory(
                        turnos=[pb.ChatTurn(role="human", conteudo="oi")]
                    ),
                    llm=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL


# ------------------------------------------------------- degradação graciosa
@pytest.mark.asyncio
async def test_erro_tecnico_inesperado_nao_vaza_detalhe_ao_cliente():
    """Uma exceção técnica não prevista (bug/instabilidade do provedor) vira
    `ErrorGeneric` — o cliente recebe uma mensagem genérica, nunca o texto
    bruto da exceção (que poderia conter fragmento sensível do provedor)."""

    def _chat_model_factory_com_bug(_spec: Any) -> Any:
        raise RuntimeError("token interno do provedor: xyz-123")

    servicer = IaEngineServicer(chat_model_factory=_chat_model_factory_com_bug)
    async with _stub_for(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Sentimento(
                pb.SentimentoRequest(
                    tenant_id="t1",
                    historico=pb.ChatHistory(
                        turnos=[pb.ChatTurn(role="human", conteudo="oi")]
                    ),
                    llm=_spec(),
                )
            )
    assert exc_info.value.code() == grpc.StatusCode.INTERNAL
    assert exc_info.value.details() == "erro interno no ia_engine"
    assert "xyz-123" not in exc_info.value.details()


# --------------------------------------------------- defensivo (_abort)
class _ContextQueNaoPropaga:
    """Fake de `ServicerContext` cujo `abort` não levanta — simula uma
    implementação de transporte não conforme, para provar que `_abort`
    garante `NoReturn` mesmo nesse cenário defensivo."""

    async def abort(
        self, _code: grpc.StatusCode, _detail: str
    ) -> None:
        return None


@pytest.mark.asyncio
async def test_abort_e_defensivo_quando_context_abort_nao_propaga():
    servicer = IaEngineServicer()
    with pytest.raises(RuntimeError):
        await servicer._abort(  # type: ignore[arg-type]
            _ContextQueNaoPropaga(),
            InvalidRequestError(message="campo obrigatório ausente"),
            "Rpc",
            "t1",
        )
