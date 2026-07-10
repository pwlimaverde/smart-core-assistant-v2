"""Análise de sentimento/avaliação do atendimento (RPC Sentimento).

Equivale a `FeaturesCompose.analise_avaliacao` da v1: extrai nota (1-5),
sentimento e feedback a partir do histórico via structured output.
"""

from __future__ import annotations

from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel

from ia_engine.domain.errors import SentimentoError
from ia_engine.domain.models import AnaliseAvaliacao
from ia_engine.features._history import ChatTurnTuple, history_to_text

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


async def sentimento(
    *, historico: list[ChatTurnTuple], llm: BaseChatModel
) -> AnaliseAvaliacao:
    """Analisa o sentimento/avaliação do histórico.

    Raises:
        SentimentoError: LLM retornou tipo inesperado.
    """
    prompt = ChatPromptTemplate.from_messages(
        [("system", _SYSTEM_PROMPT), ("human", _HUMAN_PROMPT)]
    )
    chain = prompt | llm.with_structured_output(AnaliseAvaliacao)
    result: Any = await chain.ainvoke(
        {"chat_history": history_to_text(historico)}
    )

    if isinstance(result, AnaliseAvaliacao):
        return result
    if isinstance(result, BaseModel):
        return AnaliseAvaliacao.model_validate(result.model_dump())
    if isinstance(result, dict):
        return AnaliseAvaliacao.model_validate(result)
    raise SentimentoError("LLM retornou tipo inesperado na análise de sentimento")
