"""Perguntas antes de gerar a resposta: transferência, setor, irritação.

Uma requisição só, com todas as perguntas em paralelo e isoladas. As regras do
tenant são lidas **ao pé da letra**: cada condição vira um `Noul` com os
exemplos que transferem e os que não transferem como critérios.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.domain.jev import Fluxo
from ia_engine_jev.typesafe.tipos import PerguntaChoice, PerguntaNoul, PerguntaScore

PEDE_HUMANO = "pede_humano"
SETOR = "setor"
INSATISFACAO = "insatisfacao"
PEDE_INFORMACAO = "pede_informacao"
NENHUM_SETOR = "nenhum"


def id_regra(regra_id: int) -> str:
    return f"regra::{regra_id}"


def id_campo(slug: str) -> str:
    return f"campo_presente::{slug}"


def pergunta_pede_humano() -> PerguntaNoul:
    return PerguntaNoul(
        instrucoes=(
            "Does the customer in `mensagem` ask to talk to a human person — an "
            "attendant, a salesperson, the owner, or someone by name — instead of "
            "the automated assistant?"
        ),
        sim=[
            "quero falar com um atendente",
            "me passa pro Paulo",
            "tem alguém aí de verdade?",
        ],
        nao=[
            "o Paulo me indicou vocês",
            "qual o horário de atendimento?",
            "obrigado pela ajuda",
        ],
    )


def pergunta_regra(regra: RegraTransferencia) -> PerguntaNoul:
    return pergunta_de_condicao(regra.condicao, regra.exemplos_sim, regra.exemplos_nao)


def pergunta_de_condicao(
    condicao: str, exemplos_sim: Sequence[str], exemplos_nao: Sequence[str]
) -> PerguntaNoul:
    return PerguntaNoul(
        instrucoes={
            "question": "Is this condition true for the customer's `mensagem`?",
            "condition": condicao,
        },
        sim=list(exemplos_sim) or None,
        nao=list(exemplos_nao) or None,
    )


def pergunta_setor(fluxos: Sequence[Fluxo]) -> PerguntaChoice:
    criterios: dict[str, Any] = {f.chave: None for f in fluxos if f.chave}
    criterios[NENHUM_SETOR] = "No listed department fits the customer's request."
    return PerguntaChoice(
        instrucoes=(
            "Which department should handle what the customer asks in `mensagem`?"
        ),
        criterios=criterios,
    )


def pergunta_insatisfacao() -> PerguntaScore:
    return PerguntaScore(
        instrucoes="How upset is the customer in `mensagem`, given `historico`?",
        niveis=(
            "Calm or neutral: no complaint.",
            "Annoyed: mild complaint or impatience, still cooperative.",
            "Angry: strong complaint, threat to leave, insults or repeated anger.",
        ),
    )


def pergunta_pede_informacao() -> PerguntaNoul:
    """Distingue pedido de informação (precisa da base) de conversa social."""
    return PerguntaNoul(
        instrucoes=(
            "Does `mensagem` ask for information about the business — products, "
            "prices, deadlines, policies, how something works — rather than being a "
            "greeting, thanks, small talk or the customer giving their own data?"
        )
    )


def pergunta_campo(slug: str, nome: str, descricao: str) -> PerguntaNoul:
    return PerguntaNoul(
        instrucoes={
            "question": "Does the customer state a value for this field in `mensagem`?",
            "field": nome or slug,
            "definition": descricao or nome or slug,
        }
    )
