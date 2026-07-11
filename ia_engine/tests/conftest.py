"""Fixtures de teste: fakes determinísticos de LLM/embeddings e server real.

Nenhum teste toca rede ou provedor real — todos os modelos são fakes.
"""

from __future__ import annotations

import hashlib
import itertools
from collections.abc import AsyncIterator
from typing import Any

import grpc
import pytest
import pytest_asyncio
from langchain_core.embeddings import Embeddings
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langchain_core.messages import AIMessage
from langchain_core.runnables import Runnable, RunnableLambda

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.domain.models import AnaliseAvaliacao, MediaAnalysis, RespostaBot
from ia_engine.servicer import IaEngineServicer

EMBEDDING_DIM = 1536


class FakeChatModel(GenericFakeChatModel):
    """Chat model fake com `with_structured_output` ciente do schema."""

    resposta_bot: Any = None
    media_analysis: Any = None
    avaliacao: Any = None
    analyse_value: Any = None

    def with_structured_output(  # type: ignore[override]
        self, schema: Any, **_kwargs: Any
    ) -> Runnable[Any, Any]:
        if schema is RespostaBot:
            value = self.resposta_bot
        elif schema is MediaAnalysis:
            value = self.media_analysis
        elif schema is AnaliseAvaliacao:
            value = self.avaliacao
        else:  # schema dinâmico do Analyse
            value = self.analyse_value
        return RunnableLambda(lambda _input: value)


class FakeEmbeddings(Embeddings):
    """Embeddings determinísticos (hash) de dimensão fixa (default 1536)."""

    def __init__(self, dim: int = EMBEDDING_DIM) -> None:
        self.dim = dim

    def _vec(self, text: str) -> list[float]:
        digest = hashlib.sha256(text.encode("utf-8")).digest()
        return [
            ((digest[i % len(digest)] + i) % 17 + 1) / 17.0
            for i in range(self.dim)
        ]

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._vec(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._vec(text)

    async def aembed_documents(self, texts: list[str]) -> list[list[float]]:
        return self.embed_documents(texts)

    async def aembed_query(self, text: str) -> list[float]:
        return self._vec(text)


class FakeTranscriber:
    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str:
        return "transcrição fake do áudio"


def _fake_chat() -> FakeChatModel:
    return FakeChatModel(
        messages=itertools.cycle([AIMessage(content="resumo fake")]),
        resposta_bot=RespostaBot(
            resposta_texto="Olá! Como posso ajudar?",
            acao_transferencia=None,
            confianca=0.9,
        ),
        media_analysis=MediaAnalysis(
            analise="Descrição completa da mídia.",
            resumo="Resumo curto da mídia.",
        ),
        avaliacao=AnaliseAvaliacao(
            nota=5, sentimento="positivo", feedback="Atendimento ótimo"
        ),
        analyse_value={
            "intents": [{"tipo": "saudacao", "confianca": 0.95}],
            "entidades": [
                {"tipo": "nome_contato", "valor": "Ana", "confianca": 0.9}
            ],
        },
    )


@pytest.fixture
def fake_chat_factory():
    def factory(_config: pb.LlmProviderConfig) -> FakeChatModel:
        return _fake_chat()

    return factory


@pytest.fixture
def fake_embeddings_factory():
    def factory(_config: pb.LlmProviderConfig) -> FakeEmbeddings:
        return FakeEmbeddings()

    return factory


@pytest.fixture
def fake_transcriber_factory():
    def factory(_config: pb.LlmProviderConfig) -> FakeTranscriber:
        return FakeTranscriber()

    return factory


@pytest.fixture(autouse=True)
def _patch_media_download(monkeypatch: pytest.MonkeyPatch) -> None:
    """Evita rede real: download de mídia retorna bytes fixos."""

    async def _fake_download(url: str, **_kwargs: Any) -> bytes:
        if not url:
            from ia_engine.domain.errors import MediaDownloadError

            raise MediaDownloadError("URL da mídia não informada")
        return b"\x00\x01\x02fake-media-bytes"

    monkeypatch.setattr(
        "ia_engine.features.interpret_media.download_media", _fake_download
    )
    monkeypatch.setattr(
        "ia_engine.features.transcribe.download_media", _fake_download
    )


@pytest_asyncio.fixture
async def ia_stub(
    fake_chat_factory,
    fake_embeddings_factory,
    fake_transcriber_factory,
) -> AsyncIterator[pbg.IaEngineServiceStub]:
    """Sobe um grpc.aio.server real em porta aleatória com fakes injetados."""
    servicer = IaEngineServicer(
        chat_model_factory=fake_chat_factory,
        embeddings_factory=fake_embeddings_factory,
        transcriber_factory=fake_transcriber_factory,
    )
    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as channel:
            yield pbg.IaEngineServiceStub(channel)
    finally:
        await server.stop(None)


@pytest.fixture
def secret_config() -> pb.LlmProviderConfig:
    """Config com api_key sensível para checar que nunca vaza em log."""
    return pb.LlmProviderConfig(
        provider="openai",
        model="gpt-4o-mini",
        api_key="SUPER_SECRET_API_KEY_12345",
        temperature=0.2,
    )
