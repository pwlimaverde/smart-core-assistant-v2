"""Cópia de um valor livre do texto do cliente pela LLM (texto puro, sem schema).

Só roda quando o Jev já disse que o valor está presente, e o resultado é
conferido depois — pelo Jev (`confere::<tipo>`) e pelo código (o valor tem de
estar no texto). O prompt pede cópia, nunca interpretação.
"""

from __future__ import annotations

from langchain_core.language_models.chat_models import BaseChatModel

_NADA = "NADA"
_LIMITE = 200


def _prompt(mensagem: str, campo: str, descricao: str, normalizar: str) -> str:
    regra = f"\n{normalizar}" if normalizar else ""
    return (
        "Copie EXATAMENTE, do texto do cliente abaixo, o trecho que informa o "
        f"campo '{campo}' ({descricao or campo}). Responda só o trecho, sem "
        f"explicar, sem aspas.{regra} Se o cliente não informou, responda {_NADA}."
        f"\n\nTexto do cliente:\n{mensagem}"
    )


async def copiar_valor(
    llm: BaseChatModel,
    mensagem: str,
    campo: str,
    descricao: str = "",
    normalizar: str = "",
) -> str:
    """O trecho copiado, ou "" quando a LLM diz que não há."""
    saida = await llm.ainvoke(_prompt(mensagem, campo, descricao, normalizar))
    conteudo = getattr(saida, "content", saida)
    texto = conteudo if isinstance(conteudo, str) else str(conteudo)
    texto = texto.strip().strip("\"'").strip()
    if not texto or texto.upper().startswith(_NADA):
        return ""
    return texto[:_LIMITE]
