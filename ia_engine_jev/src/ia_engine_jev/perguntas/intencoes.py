"""Perguntas de intenção: a principal (`Choice`) e várias (`Noul` por intenção).

A LLM recebia só os NOMES das intenções; aqui cada opção leva descrição e
exemplo — é o que separa opções parecidas (doc: `what`/`examples`). Mais de
~240 intenções não cabem num `Choice` confiável: vira dois estágios (grupo,
depois a intenção dentro dele).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.domain.jev import IntentDef
from ia_engine_jev.typesafe.tipos import PerguntaChoice, PerguntaNoul

NENHUMA = "nenhuma"
LIMITE_CHOICE = 240
SEM_GRUPO = "outros"

PRINCIPAL = "intencao_principal"
GRUPO = "intencao_grupo"


def id_multi(tag: str) -> str:
    return f"intencao::{tag}"


def _opcao(intent: IntentDef) -> dict[str, Any]:
    opcao: dict[str, Any] = {"what": intent.descricao or intent.tag}
    if intent.exemplo.strip():
        opcao["examples"] = [intent.exemplo.strip()]
    return opcao


def pergunta_principal(intents: Sequence[IntentDef]) -> PerguntaChoice:
    criterios: dict[str, Any] = {i.tag: _opcao(i) for i in intents if i.tag}
    criterios[NENHUMA] = "None of the listed intents applies to `mensagem`."
    return PerguntaChoice(
        instrucoes=(
            "Which intent best describes what the customer wants in `mensagem`? "
            "Use `historico` only as context for short replies. "
            f"Pick '{NENHUMA}' when no listed intent applies."
        ),
        criterios=criterios,
    )


def perguntas_multi(intents: Sequence[IntentDef]) -> dict[str, PerguntaNoul]:
    """Um `Noul` por intenção: a doc manda assim quando várias podem valer."""
    return {
        id_multi(i.tag): PerguntaNoul(
            instrucoes={
                "question": "Does the customer express this intent in `mensagem`?",
                "intent": i.tag,
                "definition": i.descricao or i.tag,
                "example": i.exemplo,
            },
            sim="The message clearly expresses this intent.",
            nao="The intent is absent, only hinted at, or belongs to someone else.",
        )
        for i in intents
        if i.tag
    }


def grupos(intents: Sequence[IntentDef]) -> dict[str, list[IntentDef]]:
    por_grupo: dict[str, list[IntentDef]] = {}
    for i in intents:
        por_grupo.setdefault(i.grupo.strip() or SEM_GRUPO, []).append(i)
    return por_grupo


def precisa_de_dois_estagios(intents: Sequence[IntentDef]) -> bool:
    return len(intents) > LIMITE_CHOICE


def pergunta_grupo(por_grupo: dict[str, list[IntentDef]]) -> PerguntaChoice:
    criterios: dict[str, Any] = {
        nome: {"what": f"Intents about {nome}", "examples": [i.tag for i in itens[:8]]}
        for nome, itens in por_grupo.items()
    }
    criterios[NENHUMA] = "None of these groups applies to `mensagem`."
    return PerguntaChoice(
        instrucoes="Which group of intents does `mensagem` belong to?",
        criterios=criterios,
    )
