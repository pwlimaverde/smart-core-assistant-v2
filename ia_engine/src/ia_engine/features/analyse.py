"""Análise prévia de mensagem: intents e entidades (RPC Analyse).

Constrói dinamicamente o schema pydantic de structured output a partir dos tipos
válidos recebidos no request (`valid_intent_types`, `valid_entity_types`).
"""

from __future__ import annotations

from typing import Any, Literal

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from pydantic import BaseModel, Field, create_model

from ia_engine.domain.errors import AnalyseError
from ia_engine.domain.models import EntidadeItem, IntentItem, IntentsEntidades
from ia_engine.features._history import ChatTurnTuple, to_lc_messages

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


async def analyse(
    *,
    mensagem: str,
    historico: list[ChatTurnTuple],
    valid_intent_types: str,
    valid_entity_types: list[str],
    llm: BaseChatModel,
) -> IntentsEntidades:
    """Extrai intents/entidades via structured output.

    Raises:
        AnalyseError: LLM retornou tipo inesperado.
    """
    intent_types = _parse_intent_types(valid_intent_types)
    entity_types = [t.strip() for t in valid_entity_types if t.strip()]
    schema = build_dynamic_model(intent_types, entity_types)

    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", _SYSTEM_PROMPT),
            MessagesPlaceholder(variable_name="chat_history"),
            ("user", "{input}"),
        ]
    )
    chain = prompt | llm.with_structured_output(schema)
    result: Any = await chain.ainvoke(
        {"chat_history": to_lc_messages(historico), "input": mensagem}
    )

    data = _as_dict(result)
    intents = [
        IntentItem(
            tipo=str(i.get("tipo", "")),
            confianca=float(i.get("confianca", 1.0)),
        )
        for i in data.get("intents", [])
        if str(i.get("tipo", "")).strip()
    ]
    entidades = [
        EntidadeItem(
            tipo=str(e.get("tipo", "")),
            valor=str(e.get("valor", "")),
            confianca=float(e.get("confianca", 1.0)),
        )
        for e in data.get("entidades", [])
        if str(e.get("tipo", "")).strip()
    ]
    return IntentsEntidades(intents=intents, entidades=entidades)


def _as_dict(result: Any) -> dict[str, list[dict[str, Any]]]:
    if isinstance(result, BaseModel):
        return result.model_dump()
    if isinstance(result, dict):
        return result
    raise AnalyseError("LLM retornou tipo inesperado na análise prévia")
