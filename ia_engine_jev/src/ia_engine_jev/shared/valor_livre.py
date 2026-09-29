"""Cópia de valores livres do texto do cliente pela LLM — uma chamada para
todos os campos (antes: uma por campo, em série).

Só roda para os campos que o Jev disse estarem presentes, e o resultado é
conferido depois pelo Jev (`confere::<chave>`) e pelo código (o valor tem de
estar no texto). O prompt pede cópia, nunca interpretação. A saída é JSON
simples; o que não for objeto de strings é descartado.
"""

from __future__ import annotations

import json
import re
from collections.abc import Sequence
from dataclasses import dataclass

from langchain_core.language_models.chat_models import BaseChatModel

_LIMITE = 200
_OBJETO = re.compile(r"\{.*\}", re.DOTALL)


@dataclass(frozen=True)
class CampoACopiar:
    """`chave`: identificador simples (vai para o JSON e para o `state`)."""

    chave: str
    nome: str
    descricao: str = ""


def _prompt(mensagem: str, campos: Sequence[CampoACopiar], normalizar: str) -> str:
    lista = "\n".join(
        f'- "{c.chave}": {c.nome}' + (f" ({c.descricao})" if c.descricao else "")
        for c in campos
    )
    regra = f"\n{normalizar}" if normalizar else ""
    return (
        "Copie EXATAMENTE, do texto do cliente abaixo, o trecho que informa cada "
        "campo da lista. Responda só um objeto JSON com as chaves da lista e o "
        'trecho copiado como texto; use "" para o campo que o cliente não '
        f"informou. Não explique.{regra}\n\nCampos:\n{lista}\n\n"
        f"Texto do cliente:\n{mensagem}"
    )


def _ler_json(texto: str) -> dict[str, str]:
    achado = _OBJETO.search(texto or "")
    if not achado:
        return {}
    try:
        bruto = json.loads(achado.group(0))
    except json.JSONDecodeError:
        return {}
    if not isinstance(bruto, dict):
        return {}
    return {
        str(k): v.strip().strip("\"'").strip()[:_LIMITE]
        for k, v in bruto.items()
        if isinstance(v, str) and v.strip()
    }


async def copiar_valores(
    llm: BaseChatModel,
    mensagem: str,
    campos: Sequence[CampoACopiar],
    normalizar: str = "",
) -> dict[str, str]:
    """chave → trecho copiado, só para as chaves pedidas e com valor."""
    if not campos:
        return {}
    saida = await llm.ainvoke(_prompt(mensagem, campos, normalizar))
    conteudo = getattr(saida, "content", saida)
    valores = _ler_json(conteudo if isinstance(conteudo, str) else str(conteudo))
    pedidas = {c.chave for c in campos}
    return {k: v for k, v in valores.items() if k in pedidas}
