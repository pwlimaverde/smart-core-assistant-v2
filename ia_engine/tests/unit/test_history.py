"""Testes da conversão de histórico de chat (`shared/history.py`)."""

from __future__ import annotations

from langchain_core.messages import AIMessage, HumanMessage

from ia_engine.shared.history import history_to_text, to_lc_messages


def test_to_lc_messages_role_ai_vira_aimessage():
    mensagens = to_lc_messages([("ai", "Olá, tudo bem?")])
    assert len(mensagens) == 1
    assert isinstance(mensagens[0], AIMessage)
    assert mensagens[0].content == "Olá, tudo bem?"


def test_to_lc_messages_role_human_ou_desconhecido_vira_humanmessage():
    mensagens = to_lc_messages([("human", "oi"), ("sistema", "outro")])
    assert all(isinstance(m, HumanMessage) for m in mensagens)


def test_to_lc_messages_role_ai_e_case_insensitive():
    mensagens = to_lc_messages([("AI", "resposta do bot")])
    assert isinstance(mensagens[0], AIMessage)


def test_history_to_text_serializa_turnos():
    texto = history_to_text([("human", "oi"), ("ai", "olá!")])
    assert texto == "human: oi\nai: olá!"
