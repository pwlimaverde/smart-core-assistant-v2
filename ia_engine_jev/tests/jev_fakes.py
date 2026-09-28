"""Dublê do Jev para os testes: respostas gravadas, nenhuma chamada de rede."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from typing import Any

from ia_engine_jev.typesafe import (
    Escolha,
    JevIndisponivel,
    Nivel,
    Pergunta,
    RespostaJev,
)

type Roteiro = Callable[[str, Any, Mapping[str, Pergunta]], RespostaJev]


class FakeJev:
    """Responde por etapa; guarda cada chamada para as asserções."""

    def __init__(self, roteiro: Roteiro | None = None, *, falha: bool = False) -> None:
        self._roteiro = roteiro or (lambda _e, _s, _p: RespostaJev(modelo="jev-teste"))
        self._falha = falha
        self.chamadas: list[tuple[str, Any, Mapping[str, Pergunta]]] = []

    async def perguntar(
        self, etapa: str, state: Any, perguntas: Mapping[str, Pergunta]
    ) -> RespostaJev:
        self.chamadas.append((etapa, state, perguntas))
        if self._falha:
            raise JevIndisponivel("simulado")
        return self._roteiro(etapa, state, perguntas)


def resposta(
    *,
    escolhas: dict[str, tuple[str, float]] | None = None,
    nouls: dict[str, float] | None = None,
    niveis: dict[str, tuple[float, dict[int, float]]] | None = None,
    tokens: int = 100,
) -> RespostaJev:
    return RespostaJev(
        escolhas={k: Escolha(v[0], v[1]) for k, v in (escolhas or {}).items()},
        nouls=dict(nouls or {}),
        niveis={k: Nivel(v[0], 0.9, v[1]) for k, v in (niveis or {}).items()},
        tokens_entrada=tokens,
        modelo="jev-1.13.0",
        duracao_ms=10,
    )
