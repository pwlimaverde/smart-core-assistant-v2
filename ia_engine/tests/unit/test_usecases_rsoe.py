"""Testes do padrão py-return-success-or-error nas features.

Cobrem o contrato das camadas: curto-circuito do fetch, falha de domínio no
`process`, tradução exceção→erro nos repositórios e o `on_unexpected`.
"""

from __future__ import annotations

import httpx
import pytest
from py_return_success_or_error import (
    DataSource,
    ErrorGeneric,
    Failure,
    Parameters,
    Success,
)

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    MediaDownloadError,
    ProviderConfigError,
)
from ia_engine.domain.models import LlmProviderSpec, MediaAnalysis
from ia_engine.features.embed import (
    EmbeddingDimensaoError,
    EmbedParameters,
    EmbedUsecase,
)
from ia_engine.features.embed.repositories.embed_repository import (
    EmbedRepository,
)
from ia_engine.features.sentimento import (
    SentimentoParameters,
    SentimentoRepository,
    SentimentoUsecase,
)
from ia_engine.features.transcribe import (
    TranscribeParameters,
    TranscribeRepository,
    TranscribeUsecase,
    TranscricaoIndisponivelError,
    TranscricaoVaziaError,
)
from ia_engine.features.transcribe.domain.models import TranscricaoBruta
from ia_engine.llm.errors import ProviderConfigException
from ia_engine.shared.media import MediaDownloadException

SPEC = LlmProviderSpec(provider="openai", model="gpt-4o-mini")

TRANSCRIBE_PARAMS = TranscribeParameters(
    url="https://r2.example/audio.ogg",
    mimetype="audio/ogg",
    language="pt",
    transcription_provider=SPEC,
)


class _StaticDataSource[TData, TParams: Parameters](
    DataSource[TData, TParams]
):
    """Datasource fake: devolve um valor fixo ou lança a exceção dada."""

    def __init__(
        self, *, value: TData | None = None, raises: Exception | None = None
    ) -> None:
        self._value = value
        self._raises = raises

    async def __call__(self, parameters: TParams) -> TData:
        if self._raises is not None:
            raise self._raises
        assert self._value is not None
        return self._value


# --------------------------------------------------------------- transcribe
@pytest.mark.asyncio
async def test_transcribe_sucesso():
    repo = TranscribeRepository(
        _StaticDataSource(
            value=TranscricaoBruta(transcricao="olá mundo", resumo="resumo")
        )
    )
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    match result:
        case Success(analysis):
            assert analysis == MediaAnalysis(
                analise="olá mundo", resumo="resumo"
            )
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


@pytest.mark.asyncio
async def test_transcribe_vazia_falha_no_process():
    repo = TranscribeRepository(
        _StaticDataSource(value=TranscricaoBruta(transcricao="  ", resumo=""))
    )
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, TranscricaoVaziaError)


@pytest.mark.asyncio
async def test_transcribe_download_falho_curto_circuita():
    """Failure do fetch retorna direto — o process nem roda."""
    repo = TranscribeRepository(
        _StaticDataSource(raises=MediaDownloadException("HTTP 403"))
    )
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, MediaDownloadError)
    assert "403" in result.error.message


@pytest.mark.asyncio
async def test_transcribe_pendente_vira_indisponivel():
    repo = TranscribeRepository(
        _StaticDataSource(raises=NotImplementedError("pendente"))
    )
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, TranscricaoIndisponivelError)


def test_transcribe_map_error_httpx_inesperado_vira_generico():
    repo = TranscribeRepository(_StaticDataSource(raises=RuntimeError("x")))
    erro = repo.map_error(httpx.ConnectError("sem rota"), TRANSCRIBE_PARAMS)
    assert isinstance(erro, ErrorGeneric)


# -------------------------------------------------------------------- embed
EMBED_PARAMS = EmbedParameters(
    textos=("texto um",), embeddings_provider=SPEC
)


@pytest.mark.asyncio
async def test_embed_dimensao_errada_falha():
    repo = EmbedRepository(_StaticDataSource(value=[[0.1, 0.2]]))
    result = await EmbedUsecase(repo)(EMBED_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, EmbeddingDimensaoError)
    assert "esperado 1536" in result.error.message


@pytest.mark.asyncio
async def test_embed_provider_invalido_vira_provider_config_error():
    repo = EmbedRepository(
        _StaticDataSource(raises=ProviderConfigException("provider vazio"))
    )
    result = await EmbedUsecase(repo)(EMBED_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


# --------------------------------------------------------------- sentimento
@pytest.mark.asyncio
async def test_sentimento_tipo_inesperado_falha_no_process():
    repo = SentimentoRepository(_StaticDataSource(value="não sou um schema"))
    result = await SentimentoUsecase(repo)(
        SentimentoParameters(historico=(("human", "oi"),), llm=SPEC)
    )
    assert isinstance(result, Failure)
    assert isinstance(result.error, LlmRespostaInvalidaError)


@pytest.mark.asyncio
async def test_sentimento_dict_invalido_vira_on_unexpected():
    """Dict fora do schema estoura na validação pydantic dentro do process —
    o `on_unexpected` converte o bug em `ErrorGeneric`, nunca exceção."""
    repo = SentimentoRepository(_StaticDataSource(value={"nota": "não-num"}))
    result = await SentimentoUsecase(repo)(
        SentimentoParameters(historico=(("human", "oi"),), llm=SPEC)
    )
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)
