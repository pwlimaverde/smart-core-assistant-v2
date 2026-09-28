"""Conferência depois de gerar: a resposta se apoia na base? promete demais?

Substitui o score triádico por cosseno (parecença de vocabulário) por uma
probabilidade: `resposta_apoiada` vira a `confiabilidade` gravada.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.typesafe.tipos import PerguntaNoul

RESPOSTA_APOIADA = "resposta_apoiada"
PROMETE = "promete_o_que_nao_pode"
RESPOSTA_TRANSFERE = "resposta_transfere"


def estado_da_resposta(
    pergunta: str, resposta: str, trechos_aprovados: Sequence[str], restricoes: str
) -> dict[str, Any]:
    estado: dict[str, Any] = {
        "pergunta": pergunta,
        "resposta": resposta,
        "trechos_aprovados": [t[:3000] for t in trechos_aprovados],
    }
    if restricoes.strip():
        estado["restricoes_da_persona"] = restricoes.strip()[:1500]
    return estado


def perguntas_da_resposta() -> dict[str, PerguntaNoul]:
    return {
        RESPOSTA_APOIADA: PerguntaNoul(
            instrucoes=(
                "Is every factual claim in `resposta` — prices, deadlines, products, "
                "conditions, policies — supported by `trechos_aprovados`? Greetings, "
                "thanks and questions back to the customer need no support."
            )
        ),
        PROMETE: PerguntaNoul(
            instrucoes=(
                "Does `resposta` promise a specific price, discount, deadline or "
                "delivery that is not stated in `trechos_aprovados`, or that "
                "`restricoes_da_persona` forbids?"
            )
        ),
        RESPOSTA_TRANSFERE: PerguntaNoul(
            instrucoes=(
                "Does `resposta` tell the customer they will be transferred or "
                "forwarded to a person, attendant or another department?"
            )
        ),
    }
