"""Datasource da feature Analyse: chamada ao LLM com schema dinâmico.

Constrói o schema pydantic de structured output a partir dos tipos válidos do
request (`valid_intent_types`, `valid_entity_types`) e invoca o LLM. Devolve o
resultado BRUTO — o parse para o domínio é regra do usecase.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any, Literal

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from py_return_success_or_error import DataSource
from pydantic import BaseModel, Field, create_model

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.analyse.domain.parameters import AnalyseParameters
from ia_engine.shared.history import to_lc_messages

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]

_SYSTEM_PROMPT = (
    "Você é um analisador de mensagens de atendimento. Extraia as INTENÇÕES e "
    "ENTIDADES presentes na última mensagem do usuário, considerando o "
    "histórico. Responda estritamente no schema estruturado solicitado. Use "
    "apenas os tipos permitidos; se nada se aplicar, retorne listas vazias."
)


def _parse_intent_types(valid_intent_types: str) -> list[str]:
    raw = (valid_intent_types or "").replace(";", ",")
    return [t.strip() for t in raw.split(",") if t.strip()]


def build_dynamic_model(
    intent_types: list[str], entity_types: list[str]
) -> type[BaseModel]:
    """Cria o modelo de structured output com `type` restrito quando possível."""
    intent_type_ann: Any = (
        Literal[tuple(intent_types)] if intent_types else str  # type: ignore[misc]
    )
    entity_type_ann: Any = (
        Literal[tuple(entity_types)] if entity_types else str  # type: ignore[misc]
    )

    intent_item = create_model(
        "IntentItemDyn",
        tipo=(
            intent_type_ann,
            Field(description="Tipo da intenção detectada"),
        ),
        confianca=(float, Field(default=1.0, ge=0.0, le=1.0)),
    )
    entity_item = create_model(
        "EntidadeItemDyn",
        tipo=(
            entity_type_ann,
            Field(description="Tipo da entidade extraída"),
        ),
        valor=(str, Field(description="Valor textual da entidade")),
        confianca=(float, Field(default=1.0, ge=0.0, le=1.0)),
    )
    return create_model(
        "AnalyseOutput",
        intents=(
            list[intent_item],  # type: ignore[valid-type]
            Field(default_factory=list),
        ),
        entidades=(
            list[entity_item],  # type: ignore[valid-type]
            Field(default_factory=list),
        ),
    )


class AnalyseDataSource(DataSource[Any, AnalyseParameters]):
    """Monta o schema dinâmico e invoca o LLM com structured output."""

    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, parameters: AnalyseParameters) -> Any:
        llm = self._chat_model_factory(parameters.llm)
        intent_types = _parse_intent_types(parameters.valid_intent_types)
        entity_types = [
            t.strip() for t in parameters.valid_entity_types if t.strip()
        ]
        schema = build_dynamic_model(intent_types, entity_types)

        prompt = ChatPromptTemplate.from_messages(
            [
                ("system", _SYSTEM_PROMPT),
                MessagesPlaceholder(variable_name="chat_history"),
                ("user", "{input}"),
            ]
        )
        chain = prompt | llm.with_structured_output(schema)
        return await chain.ainvoke(
            {
                "chat_history": to_lc_messages(parameters.historico),
                "input": parameters.mensagem,
            }
        )
