"""Conversão de histórico de chat (domínio) para mensagens LangChain."""

from __future__ import annotations

from collections.abc import Iterable, Sequence

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage

# (role, conteudo) — role é "human" | "ai"
ChatTurnTuple = tuple[str, str]


def to_lc_messages(turnos: Iterable[ChatTurnTuple]) -> list[BaseMessage]:
    """Converte turnos (role, conteudo) em HumanMessage/AIMessage."""
    messages: list[BaseMessage] = []
    for role, conteudo in turnos:
        if (role or "").strip().lower() == "ai":
            messages.append(AIMessage(content=conteudo))
        else:
            messages.append(HumanMessage(content=conteudo))
    return messages


def history_to_text(turnos: Sequence[ChatTurnTuple]) -> str:
    """Serializa o histórico como texto simples (para prompts não multi-turn)."""
    return "\n".join(f"{role}: {conteudo}" for role, conteudo in turnos)
