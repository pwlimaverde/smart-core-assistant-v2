"""Perguntas de entidade: presença (`Noul`) e escolha entre candidatos.

O valor nunca é gerado pelo Jev: ele escolhe entre candidatos achados por
código (regex, lista, data) ou confere o valor que a LLM pequena copiou do
texto (`livre`).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.domain.jev import EntidadeDef
from ia_engine_jev.typesafe.tipos import PerguntaChoice, PerguntaNoul

NENHUM = "nenhum"


def id_presenca(tipo: str) -> str:
    return f"entidade_presente::{tipo}"


def id_escolha(tipo: str) -> str:
    return f"entidade::{tipo}"


def id_opcao(tipo: str, indice: int) -> str:
    return f"entidade::{tipo}::{indice}"


def id_conferencia(tipo: str) -> str:
    return f"confere::{tipo}"


def pergunta_presenca(ent: EntidadeDef) -> PerguntaNoul:
    return PerguntaNoul(
        instrucoes={
            "question": "Does the customer state a value for this field in `mensagem`?",
            "field": ent.tipo,
            "definition": ent.descricao or ent.tipo,
        },
        sim="The customer gives a concrete value for the field.",
        nao="The field is not mentioned, or only asked about without a value.",
    )


def pergunta_escolha(ent: EntidadeDef, candidatos: Sequence[str]) -> PerguntaChoice:
    criterios: dict[str, Any] = {c: None for c in candidatos}
    criterios[NENHUM] = "None of the candidates is the value of the field."
    return PerguntaChoice(
        instrucoes={
            "question": (
                "Which candidate is the value the customer gives for this field "
                "in `mensagem`?"
            ),
            "field": ent.tipo,
            "definition": ent.descricao or ent.tipo,
        },
        criterios=criterios,
    )


def perguntas_varios(ent: EntidadeDef) -> dict[str, PerguntaNoul]:
    """Um `Noul` por opção: o cliente pode querer mais de uma."""
    return {
        id_opcao(ent.tipo, n): PerguntaNoul(
            instrucoes={
                "question": "Does the customer ask for this option in `mensagem`?",
                "field": ent.tipo,
                "option": opcao,
            }
        )
        for n, opcao in enumerate(ent.opcoes)
    }


def pergunta_conferencia(tipo: str, descricao: str) -> PerguntaNoul:
    """Confere o valor copiado pela LLM: `state.valores[tipo]` contra a mensagem."""
    return PerguntaNoul(
        instrucoes={
            "question": (
                f"Is `valores.{tipo}` exactly what the customer states for this field "
                "in `mensagem`, with nothing invented or completed?"
            ),
            "field": tipo,
            "definition": descricao or tipo,
        },
        sim="The value is stated by the customer in the message.",
        nao="The value is not in the message, is guessed, or is incomplete.",
    )
