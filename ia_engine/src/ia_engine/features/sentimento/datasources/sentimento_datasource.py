"""Datasource da feature Sentimento: chamada ao LLM com structured output.

Equivale a `FeaturesCompose.analise_avaliacao` da v1: extrai nota (1-5),
sentimento e feedback a partir do histórico. Devolve o resultado BRUTO — a
validação/conversão é regra do usecase.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate
from py_return_success_or_error import DataSource

from ia_engine.domain.models import AnaliseAvaliacao, LlmProviderSpec
from ia_engine.features.sentimento.domain.parameters import (
    SentimentoParameters,
)
from ia_engine.shared.history import history_to_text

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]

_SYSTEM_PROMPT = """Você é um especialista em análise de satisfação do cliente.
Sua tarefa é analisar a resposta do usuário a uma solicitação de feedback e extrair:
1. A nota numérica (1 a 5).
2. O sentimento (apenas 'positivo' ou 'negativo').
3. O feedback textual.

REGRAS:
- Nota: Extraia o número 1-5. Se for > 5, normalize (ex: 10 -> 5). Se não houver número, infira pelo sentimento (Positivo=5, Negativo=1).
- Sentimento: Classifique estritamente como 'positivo' (notas 4-5 ou elogios) ou 'negativo' (notas 1-3 ou críticas). Evite 'neutro'.
- Feedback: Extraia o texto explicativo. Se for apenas a nota, retorne None.
"""

_HUMAN_PROMPT = """Histórico da conversa recente (foco na última mensagem do usuário):
{chat_history}

Analise a última resposta do usuário."""


class SentimentoDataSource(DataSource[Any, SentimentoParameters]):
    """Invoca o LLM com o schema `AnaliseAvaliacao`."""

    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, parameters: SentimentoParameters) -> Any:
        llm = self._chat_model_factory(parameters.llm)
        prompt = ChatPromptTemplate.from_messages(
            [("system", _SYSTEM_PROMPT), ("human", _HUMAN_PROMPT)]
        )
        chain = prompt | llm.with_structured_output(AnaliseAvaliacao)
        return await chain.ainvoke(
            {"chat_history": history_to_text(parameters.historico)}
        )
