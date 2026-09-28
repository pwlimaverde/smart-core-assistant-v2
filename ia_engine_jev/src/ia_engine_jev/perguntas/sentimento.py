"""Pesquisa de satisfação: nota (`Score` de 5 níveis) e sentimento (`Choice`)."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.perguntas.comum import historico_curto
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.typesafe.tipos import PerguntaChoice, PerguntaScore

NOTA = "nota"
SENTIMENTO = "sentimento"


def ultima_do_cliente(historico: Sequence[ChatTurnTuple]) -> str:
    for role, conteudo in reversed(list(historico)):
        if (role or "").strip().lower() != "ai" and (conteudo or "").strip():
            return conteudo.strip()
    return ""


def estado_da_avaliacao(historico: Sequence[ChatTurnTuple]) -> dict[str, Any]:
    return {
        "resposta_do_cliente": ultima_do_cliente(historico),
        "historico": historico_curto(historico),
    }


def perguntas_da_avaliacao() -> dict[str, PerguntaChoice | PerguntaScore]:
    return {
        NOTA: PerguntaScore(
            instrucoes=(
                "How satisfied is the customer with the service, judging by "
                "`resposta_do_cliente` (their answer to a satisfaction survey)?"
            ),
            niveis=(
                "Very dissatisfied: rating 1, strong complaint.",
                "Dissatisfied: rating 2, complaint.",
                "Neutral: rating 3, mixed or indifferent.",
                "Satisfied: rating 4, praise with small reservations.",
                "Very satisfied: rating 5, clear praise.",
            ),
        ),
        SENTIMENTO: PerguntaChoice(
            instrucoes=(
                "Is `resposta_do_cliente` positive or negative about the service?"
            ),
            criterios={
                "positivo": "Praise, thanks, or a rating of 4 or 5.",
                "negativo": "Complaint, criticism, or a rating of 1 to 3.",
            },
        ),
    }
