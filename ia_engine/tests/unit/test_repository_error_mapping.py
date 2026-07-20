"""Cobertura da união fechada de erros de cada repository RSOE.

Complementa `test_usecases_rsoe.py`: aqui o foco é exercitar TODA variante
do `map_error` de cada repository (inclusive o caso `ErrorGeneric` default,
que `test_usecases_rsoe.py` não cobria para todas as features) e os ramos
do `process`/`on_unexpected` dos usecases que ainda não tinham teste
próprio (Analyse, InterpretMedia, Responder). Mock só na fronteira externa
— o `DataSource` — via o mesmo `_StaticDataSource` fake determinístico.
"""

from __future__ import annotations

import pytest
from py_return_success_or_error import (
    DataSource,
    ErrorGeneric,
    Failure,
    Parameters,
    Success,
)
from pydantic import BaseModel

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    MediaDownloadError,
    ProviderConfigError,
)
from ia_engine.domain.models import (
    IntentsEntidades,
    LlmProviderSpec,
    MediaAnalysis,
    RespostaBot,
)
from ia_engine.features.analyse import (
    AnalyseParameters,
    AnalyseRepository,
    AnalyseUsecase,
)
from ia_engine.features.embed import EmbedParameters, EmbedRepository, EmbedUsecase
from ia_engine.features.interpret_media import (
    InterpretMediaParameters,
    InterpretMediaRepository,
    InterpretMediaUsecase,
)
from ia_engine.features.responder import (
    ResponderParameters,
    ResponderRepository,
    ResponderUsecase,
)
from ia_engine.features.responder.domain.errors import ResponderError
from ia_engine.features.responder.domain.models import ResponderData
from ia_engine.features.sentimento import (
    SentimentoParameters,
    SentimentoRepository,
    SentimentoUsecase,
)
from ia_engine.features.transcribe import (
    TranscribeParameters,
    TranscribeRepository,
    TranscribeUsecase,
)
from ia_engine.llm.errors import LlmOutputInesperadoException, ProviderConfigException
from ia_engine.shared.media import MediaDownloadException

SPEC = LlmProviderSpec(provider="openai", model="gpt-4o-mini")


class _StaticDataSource[TData, TParams: Parameters](DataSource[TData, TParams]):
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


# --------------------------------------------------------------- analyse
ANALYSE_PARAMS = AnalyseParameters(
    mensagem="olá",
    historico=(),
    valid_intent_types="saudacao",
    valid_entity_types=(),
    llm=SPEC,
)


@pytest.mark.asyncio
async def test_analyse_sucesso_com_dict_bruto():
    repo = AnalyseRepository(
        _StaticDataSource(
            value={
                "intents": [{"tipo": "saudacao", "confianca": 0.9}],
                "entidades": [],
            }
        )
    )
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    match result:
        case Success(analise):
            assert analise.intents[0].tipo == "saudacao"
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


@pytest.mark.asyncio
async def test_analyse_sucesso_com_basemodel_bruto():
    """Alguns provedores retornam o schema já como instância pydantic
    (não como dict) — cobre o ramo `isinstance(data, BaseModel)`."""
    from ia_engine.domain.models import EntidadeItem, IntentItem

    bruto = IntentsEntidades(
        intents=[IntentItem(tipo="duvida", confianca=0.8)],
        entidades=[EntidadeItem(tipo="nome_contato", valor="Ana", confianca=0.7)],
    )
    repo = AnalyseRepository(_StaticDataSource(value=bruto))
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    match result:
        case Success(analise):
            assert analise.intents[0].tipo == "duvida"
            assert analise.entidades[0].valor == "Ana"
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


@pytest.mark.asyncio
async def test_analyse_tipo_inesperado_falha_no_process():
    repo = AnalyseRepository(_StaticDataSource(value="não é dict nem BaseModel"))
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, LlmRespostaInvalidaError)


@pytest.mark.asyncio
async def test_analyse_provider_invalido_vira_provider_config_error():
    repo = AnalyseRepository(
        _StaticDataSource(raises=ProviderConfigException("provider vazio"))
    )
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


@pytest.mark.asyncio
async def test_analyse_erro_tecnico_inesperado_vira_error_generic_no_repository():
    """Exceção não mapeada explicitamente cai no `case _` do repository."""
    repo = AnalyseRepository(_StaticDataSource(raises=RuntimeError("boom")))
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


@pytest.mark.asyncio
async def test_analyse_bug_no_process_vira_error_generic_via_on_unexpected():
    """`valid_entity_types`/dados corrompidos que estourem dentro do
    `process` (bug do usecase, não do datasource) são convertidos por
    `on_unexpected` — nunca propagam como exceção ao chamador."""
    # `confianca` não numérica quebra o `float(...)` dentro do process.
    repo = AnalyseRepository(
        _StaticDataSource(
            value={"intents": [{"tipo": "x", "confianca": "não-num"}]}
        )
    )
    result = await AnalyseUsecase(repo)(ANALYSE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


# --------------------------------------------------------- interpret_media
INTERPRET_PARAMS = InterpretMediaParameters(
    url="https://r2.example/img.jpg",
    mimetype="image/jpeg",
    media_type="imageMessage",
    file_name="",
    vision_provider=SPEC,
)


@pytest.mark.asyncio
async def test_interpret_media_sucesso_com_dict_bruto():
    repo = InterpretMediaRepository(
        _StaticDataSource(value={"analise": "uma foto", "resumo": "foto"})
    )
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    match result:
        case Success(analysis):
            assert analysis == MediaAnalysis(analise="uma foto", resumo="foto")
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


@pytest.mark.asyncio
async def test_interpret_media_tipo_inesperado_falha_no_process():
    repo = InterpretMediaRepository(_StaticDataSource(value=123))
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, LlmRespostaInvalidaError)


@pytest.mark.asyncio
async def test_interpret_media_analise_vazia_falha_no_process():
    repo = InterpretMediaRepository(
        _StaticDataSource(value=MediaAnalysis(analise="   ", resumo=""))
    )
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, LlmRespostaInvalidaError)


@pytest.mark.asyncio
async def test_interpret_media_provider_invalido_vira_provider_config_error():
    repo = InterpretMediaRepository(
        _StaticDataSource(raises=ProviderConfigException("sem api key"))
    )
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


@pytest.mark.asyncio
async def test_interpret_media_download_falho_vira_media_download_error():
    repo = InterpretMediaRepository(
        _StaticDataSource(raises=MediaDownloadException("HTTP 404"))
    )
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, MediaDownloadError)


@pytest.mark.asyncio
async def test_interpret_media_erro_tecnico_inesperado_vira_error_generic():
    repo = InterpretMediaRepository(_StaticDataSource(raises=RuntimeError("boom")))
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


class _BadDict(dict):  # type: ignore[type-arg]
    """Dict que quebra no `.get` — simula um bug de contrato do provedor."""

    def get(self, *_args: object, **_kwargs: object) -> object:
        raise RuntimeError("contrato do provedor corrompido")


@pytest.mark.asyncio
async def test_interpret_media_bug_no_process_vira_error_generic_via_on_unexpected():
    repo = InterpretMediaRepository(
        _StaticDataSource(value=_BadDict(analise="x", resumo="y"))
    )
    result = await InterpretMediaUsecase(repo)(INTERPRET_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


# --------------------------------------------------------------- responder
RESPONDER_PARAMS = ResponderParameters(
    mensagem="Olá",
    historico=(),
    fluxos_disponiveis=(("Financeiro - cobranças", "setor"),),
    dados_empresa="Empresa X",
    dados_treinamento="",
    similarity_threshold=0.5,
    llm=SPEC,
    embeddings_provider=SPEC,
)


def _responder_data(
    *,
    message_vec: tuple[float, ...] = (1.0, 0.0),
    response_vec: tuple[float, ...] = (1.0, 0.0),
) -> ResponderData:
    return ResponderData(
        resposta=RespostaBot(
            resposta_texto="Olá! Tudo certo?", acao_transferencia=None, confianca=0.9
        ),
        message_vec=message_vec,
        response_vec=response_vec,
        training_vec=None,
    )


@pytest.mark.asyncio
async def test_responder_sucesso():
    repo = ResponderRepository(_StaticDataSource(value=_responder_data()))
    result = await ResponderUsecase(repo)(RESPONDER_PARAMS)
    match result:
        case Success(final):
            assert final.transferir_atendimento is False
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


@pytest.mark.asyncio
async def test_responder_provider_invalido_vira_provider_config_error():
    repo = ResponderRepository(
        _StaticDataSource(raises=ProviderConfigException("provider vazio"))
    )
    result = await ResponderUsecase(repo)(RESPONDER_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


@pytest.mark.asyncio
async def test_responder_llm_output_inesperado_vira_llm_resposta_invalida_error():
    repo = ResponderRepository(
        _StaticDataSource(
            raises=LlmOutputInesperadoException("tipo inesperado do LLM")
        )
    )
    result = await ResponderUsecase(repo)(RESPONDER_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, LlmRespostaInvalidaError)


@pytest.mark.asyncio
async def test_responder_erro_tecnico_inesperado_vira_error_generic_no_repository():
    repo = ResponderRepository(_StaticDataSource(raises=RuntimeError("boom")))
    result = await ResponderUsecase(repo)(RESPONDER_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


@pytest.mark.asyncio
async def test_responder_bug_no_process_vira_error_generic_via_on_unexpected():
    """Vetores de dimensões diferentes estouram dentro do `process` (score
    triádico) — bug de dados, não erro de domínio previsto — e devem virar
    `ErrorGeneric` via `on_unexpected`, nunca propagar."""
    repo = ResponderRepository(
        _StaticDataSource(
            value=_responder_data(message_vec=(1.0, 0.0), response_vec=(1.0,))
        )
    )
    result: ResponderError | None = None
    outcome = await ResponderUsecase(repo)(RESPONDER_PARAMS)
    match outcome:
        case Failure(error):
            result = error
        case Success(_):
            pytest.fail("esperava falha por dimensões incompatíveis")
    assert isinstance(result, ErrorGeneric)


# -------------------------------------------------------------- sentimento
SENTIMENTO_PARAMS = SentimentoParameters(historico=(("human", "oi"),), llm=SPEC)


@pytest.mark.asyncio
async def test_sentimento_provider_invalido_vira_provider_config_error():
    repo = SentimentoRepository(
        _StaticDataSource(raises=ProviderConfigException("provider vazio"))
    )
    result = await SentimentoUsecase(repo)(SENTIMENTO_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


@pytest.mark.asyncio
async def test_sentimento_erro_tecnico_inesperado_vira_error_generic_no_repository():
    repo = SentimentoRepository(_StaticDataSource(raises=RuntimeError("boom")))
    result = await SentimentoUsecase(repo)(SENTIMENTO_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


class _OutroSchemaCompativel(BaseModel):
    """Outro `BaseModel` (não `AnaliseAvaliacao`) com campos compatíveis —
    cobre o ramo genérico `isinstance(data, BaseModel)` do usecase, que
    revalida via `model_dump()`."""

    nota: int
    sentimento: str
    feedback: str | None = None


@pytest.mark.asyncio
async def test_sentimento_sucesso_com_basemodel_generico():
    repo = SentimentoRepository(
        _StaticDataSource(
            value=_OutroSchemaCompativel(nota=4, sentimento="positivo")
        )
    )
    result = await SentimentoUsecase(repo)(SENTIMENTO_PARAMS)
    match result:
        case Success(avaliacao):
            assert avaliacao.nota == 4
            assert avaliacao.sentimento == "positivo"
        case Failure(error):
            pytest.fail(f"esperava sucesso, veio {error}")


# --------------------------------------------------------------- transcribe
TRANSCRIBE_PARAMS = TranscribeParameters(
    url="https://r2.example/audio.ogg",
    mimetype="audio/ogg",
    language="pt",
    transcription_provider=SPEC,
)


@pytest.mark.asyncio
async def test_transcribe_provider_invalido_vira_provider_config_error():
    repo = TranscribeRepository(
        _StaticDataSource(raises=ProviderConfigException("provider vazio"))
    )
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ProviderConfigError)


@pytest.mark.asyncio
async def test_transcribe_bug_no_process_vira_error_generic_via_on_unexpected():
    """Dado bruto corrompido (transcrição não-string, bug do datasource)
    estoura no `.strip()` do `process` — vira `ErrorGeneric` via
    `on_unexpected`, nunca propaga."""
    from ia_engine.features.transcribe.domain.models import TranscricaoBruta

    bruta_corrompida = TranscricaoBruta(transcricao=None, resumo="")  # type: ignore[arg-type]
    repo = TranscribeRepository(_StaticDataSource(value=bruta_corrompida))
    result = await TranscribeUsecase(repo)(TRANSCRIBE_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


# -------------------------------------------------------------------- embed
EMBED_PARAMS = EmbedParameters(textos=("texto um",), embeddings_provider=SPEC)


@pytest.mark.asyncio
async def test_embed_erro_tecnico_inesperado_vira_error_generic_no_repository():
    repo = EmbedRepository(_StaticDataSource(raises=RuntimeError("boom")))
    result = await EmbedUsecase(repo)(EMBED_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)


@pytest.mark.asyncio
async def test_embed_bug_no_process_vira_error_generic_via_on_unexpected():
    """Um item do batch que não é uma sequência (bug de contrato do
    provedor) estoura no `len(vector)` do `process` — vira `ErrorGeneric`
    via `on_unexpected`, nunca propaga."""
    repo = EmbedRepository(_StaticDataSource(value=[123]))  # type: ignore[list-item]
    result = await EmbedUsecase(repo)(EMBED_PARAMS)
    assert isinstance(result, Failure)
    assert isinstance(result.error, ErrorGeneric)
