"""Testes do datasource da feature Responder (`responder_datasource.py`).

Cobre a montagem do prompt (`_formatar_campos`, funções puras) e os dois
ramos de conversão do output do LLM (`RespostaBot` bruto vs. `dict`), além
do tipo inesperado que vira `LlmOutputInesperadoException` — mock só na
fronteira externa (o chat model / embeddings, nunca a lógica de domínio).
"""

from __future__ import annotations

from typing import Any

import pytest
from langchain_core.runnables import Runnable, RunnableLambda

from ia_engine.domain.models import LlmProviderSpec, RespostaBot
from ia_engine.features.responder.datasources.responder_datasource import (
    ResponderDataSource,
    _formatar_campos,
)
from ia_engine.features.responder.domain.parameters import (
    CampoColetado,
    CampoPendente,
    ResponderParameters,
)
from ia_engine.llm.errors import LlmOutputInesperadoException

SPEC = LlmProviderSpec(provider="openai", model="gpt-4o-mini")


# ------------------------------------------------------- _formatar_campos
def test_formatar_campos_vazio_retorna_string_vazia():
    assert _formatar_campos((), ()) == ""


def test_formatar_campos_coletados_usa_nome_ou_slug():
    coletados = (CampoColetado(slug="email", nome="", valor="a@b.com"),)
    texto = _formatar_campos(coletados, ())
    assert "CAMPOS COLETADOS" in texto
    assert "**email**: a@b.com" in texto


def test_formatar_campos_pendentes_com_hint():
    pendentes = (
        CampoPendente(
            slug="tel",
            nome="Telefone",
            descricao="número de contato",
            hint="DDD+número",
        ),
    )
    texto = _formatar_campos((), pendentes)
    assert "CAMPOS PENDENTES" in texto
    assert "**Telefone**: número de contato [DDD+número]" in texto
    assert "colete esses dados" in texto


def test_formatar_campos_pendentes_sem_hint_nao_anexa_colchetes():
    pendentes = (
        CampoPendente(slug="nome", nome="", descricao="nome completo", hint=""),
    )
    texto = _formatar_campos((), pendentes)
    assert "**nome**: nome completo" in texto
    assert "[" not in texto


# ------------------------------------------------------------- datasource
class _StructuredOutputChat:
    """Fake mínimo: só implementa `with_structured_output`."""

    def __init__(self, value: Any) -> None:
        self._value = value

    def with_structured_output(
        self, _schema: Any, **_kwargs: Any
    ) -> Runnable[Any, Any]:
        return RunnableLambda(lambda _input: self._value)


class _FakeEmbeddings:
    async def aembed_query(self, text: str) -> list[float]:
        return [float(len(text)), 0.5]


def _params(**overrides: Any) -> ResponderParameters:
    base = dict(
        mensagem="Olá",
        historico=(),
        fluxos_disponiveis=(),
        dados_empresa="Empresa X",
        dados_treinamento="",
        similarity_threshold=0.5,
        llm=SPEC,
        embeddings_provider=SPEC,
    )
    base.update(overrides)
    return ResponderParameters(**base)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_datasource_aceita_dict_bruto_do_llm():
    datasource = ResponderDataSource(
        chat_model_factory=lambda _spec: _StructuredOutputChat(
            {"resposta_texto": "Oi!", "acao_transferencia": None, "confianca": 0.6}
        ),
        embeddings_factory=lambda _spec: _FakeEmbeddings(),
    )
    data = await datasource(_params())
    assert isinstance(data.resposta, RespostaBot)
    assert data.resposta.resposta_texto == "Oi!"


@pytest.mark.asyncio
async def test_datasource_tipo_inesperado_leva_a_llm_output_inesperado_exception():
    datasource = ResponderDataSource(
        chat_model_factory=lambda _spec: _StructuredOutputChat(42),
        embeddings_factory=lambda _spec: _FakeEmbeddings(),
    )
    with pytest.raises(LlmOutputInesperadoException):
        await datasource(_params())


@pytest.mark.asyncio
async def test_datasource_calcula_vetor_de_treinamento_quando_presente():
    """Com `dados_treinamento` preenchido, o vetor de treinamento é
    calculado (embedding extra) — cobre o ramo positivo do `if`."""
    datasource = ResponderDataSource(
        chat_model_factory=lambda _spec: _StructuredOutputChat(
            RespostaBot(resposta_texto="Ok", acao_transferencia=None, confianca=0.8)
        ),
        embeddings_factory=lambda _spec: _FakeEmbeddings(),
    )
    data = await datasource(_params(dados_treinamento="Horário: 8h-18h"))
    assert data.training_vec is not None
