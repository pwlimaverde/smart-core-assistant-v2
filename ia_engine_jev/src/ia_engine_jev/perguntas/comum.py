"""O `state` que acompanha as perguntas: só o necessário.

A doc do jev-1.13 avisa que `state` grande com lixo derruba a acurácia. Por
isso vão as últimas falas, não a conversa inteira, e a empresa em uma linha.
Seis falas: a coleta pergunta "o cliente já disse X?" e a resposta pode estar
duas ou três trocas atrás.
A mensagem do cliente é dado, nunca instrução: vai sempre como campo do
`state`, referenciado por caminho entre crases nas instruções.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ia_engine_jev.shared.history import ChatTurnTuple

FALAS_NO_HISTORICO = 6
LIMITE_EMPRESA = 300


def historico_curto(
    historico: Sequence[ChatTurnTuple], falas: int = FALAS_NO_HISTORICO
) -> list[str]:
    """Últimas falas como "cliente: ..." / "atendente: ..."."""
    linhas: list[str] = []
    for role, conteudo in list(historico)[-falas:]:
        quem = "atendente" if (role or "").strip().lower() == "ai" else "cliente"
        texto = (conteudo or "").strip()
        if texto:
            linhas.append(f"{quem}: {texto[:400]}")
    return linhas


def empresa_em_uma_linha(dados_empresa: str) -> str:
    for linha in (dados_empresa or "").splitlines():
        if linha.strip():
            return linha.strip()[:LIMITE_EMPRESA]
    return ""


def estado_da_mensagem(
    mensagem: str,
    historico: Sequence[ChatTurnTuple],
    dados_empresa: str = "",
) -> dict[str, Any]:
    estado: dict[str, Any] = {
        "mensagem": mensagem,
        "historico": historico_curto(historico),
    }
    empresa = empresa_em_uma_linha(dados_empresa)
    if empresa:
        estado["empresa"] = empresa
    return estado
