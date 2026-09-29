"""Conferência depois de redigir, numa requisição só (padrão *verify* da doc):

- a resposta se apoia na evidência? promete o que não pode? diz que vai
  transferir? (fatos e decisão — a LLM não decide transferência);
- repete os dados que o cliente acabou de dar? pede um dado proibido? (estilo
  e política do tenant, que antes eram só pedidos no prompt);
- os valores que a LLM copiou da mensagem (campos do cartão e entidades
  livres) são mesmo o que o cliente disse?

Cada pergunta é estreita e com o caso ruim no `true`, como no cookbook da
cascata de extração: o código agrega com "qualquer uma falhou".
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from ia_engine_jev.typesafe.tipos import PerguntaNoul

RESPOSTA_APOIADA = "resposta_apoiada"
PROMETE = "promete_o_que_nao_pode"
RESPOSTA_TRANSFERE = "resposta_transfere"
ECOA = "ecoa_cliente"
PEDE_PROIBIDO = "pede_dado_proibido"


def id_confere(chave: str) -> str:
    """Conferência de um valor copiado: `campo:<slug>` ou `entidade:<tipo>`."""
    return f"confere::{chave}"


def estado_da_resposta(
    pergunta: str,
    resposta: str,
    evidencia: Sequence[str],
    restricoes: str,
    valores: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    estado: dict[str, Any] = {
        "pergunta": pergunta,
        "resposta": resposta,
        "evidencia": [t[:3000] for t in evidencia],
    }
    if restricoes.strip():
        estado["restricoes_da_persona"] = restricoes.strip()[:1500]
    if valores:
        estado["valores"] = dict(valores)
    return estado


def perguntas_da_resposta(
    *,
    com_texto: bool = True,
    nunca_pedir: Sequence[str] = (),
    valores: Mapping[str, tuple[str, str]] | None = None,
) -> dict[str, PerguntaNoul]:
    """`valores`: chave → (nome do campo, definição), para conferir a cópia."""
    perguntas: dict[str, PerguntaNoul] = {}
    if com_texto:
        perguntas[RESPOSTA_APOIADA] = PerguntaNoul(
            instrucoes=(
                "Is every factual claim in `resposta` — prices, deadlines, "
                "products, conditions, policies, addresses — supported by "
                "`evidencia`? Greetings, thanks and questions back to the "
                "customer need no support."
            )
        )
        perguntas[PROMETE] = PerguntaNoul(
            instrucoes=(
                "Does `resposta` promise a specific price, discount, deadline or "
                "delivery that is not stated in `evidencia`, or that "
                "`restricoes_da_persona` forbids?"
            )
        )
        perguntas[RESPOSTA_TRANSFERE] = PerguntaNoul(
            instrucoes=(
                "Does `resposta` tell the customer they will be transferred or "
                "forwarded to a person, attendant or another department?"
            )
        )
        perguntas[ECOA] = PerguntaNoul(
            instrucoes=(
                "Does `resposta` repeat back to the customer the details they "
                "just gave in `pergunta` (quantities, sizes, products), instead "
                "of only asking what is still missing?"
            ),
            sim="Restates the customer's own data as a summary or confirmation.",
            nao="Only acknowledges briefly, answers, or asks for what is missing.",
        )
        if nunca_pedir:
            perguntas[PEDE_PROIBIDO] = PerguntaNoul(
                instrucoes={
                    "question": (
                        "Does `resposta` ask the customer for any item in `never_ask`?"
                    ),
                    "never_ask": list(nunca_pedir),
                }
            )
    for chave, (nome, definicao) in (valores or {}).items():
        perguntas[id_confere(chave)] = PerguntaNoul(
            instrucoes={
                "question": (
                    f"Is `valores.{chave}` what the customer states for this "
                    "field in `pergunta`, allowing only format normalization, "
                    "with nothing invented or completed?"
                ),
                "field": nome,
                "definition": definicao or nome,
            },
            sim="The value is stated by the customer in the message.",
            nao="The value is not in the message, is guessed, or is incomplete.",
        )
    return perguntas
