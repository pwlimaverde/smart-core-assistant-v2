"""Perguntas e respostas do Jev em tipos nossos, sem o SDK.

As perguntas (`perguntas/`) e as decisões (`decisoes/`) são funções puras que
só conhecem estes tipos — testáveis sem rede e sem o pacote `typesafe_sdk`.
Quem converte para o SDK, e de volta, é o `cliente.py`.

Lembrete da doc (jev-1.13): o id da pergunta **não** vai ao modelo; a pergunta
inteira tem de estar em `instrucoes`. Instruções em inglês (idioma principal do
Jev); opções e exemplos do tenant em português.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class PerguntaChoice:
    """Uma entre opções nomeadas. `criterios`: rótulo → descrição (ou None)."""

    instrucoes: Any
    criterios: Mapping[str, Any]


@dataclass(frozen=True)
class PerguntaNoul:
    """Sim ou não; `sim`/`nao` descrevem o que conta como cada lado."""

    instrucoes: Any
    sim: Any = None
    nao: Any = None


@dataclass(frozen=True)
class PerguntaScore:
    """Nível numa escala ordenada; o nível 0 é o primeiro de `niveis`."""

    instrucoes: Any
    niveis: tuple[Any, ...]


type Pergunta = PerguntaChoice | PerguntaNoul | PerguntaScore


@dataclass(frozen=True)
class Escolha:
    """Resposta de um `Choice`."""

    escolha: str
    confianca: float
    probabilidades: Mapping[str, float] = field(default_factory=dict)


@dataclass(frozen=True)
class Nivel:
    """Resposta de um `Score`: `valor` é a média ponderada dos níveis."""

    valor: float
    confianca: float
    probabilidades: Mapping[int, float] = field(default_factory=dict)

    def mais_provavel(self) -> int:
        """O nível de maior probabilidade.

        A doc avisa que o `score` não serve para reconstruir números entre
        níveis: para uma nota, vale o nível mais provável, não a média
        arredondada.
        """
        if not self.probabilidades:
            return round(self.valor)
        return max(self.probabilidades.items(), key=lambda kv: (kv[1], -kv[0]))[0]


@dataclass(frozen=True)
class RespostaJev:
    """Respostas de uma requisição, por id de pergunta, com custo e versão."""

    escolhas: Mapping[str, Escolha] = field(default_factory=dict)
    nouls: Mapping[str, float] = field(default_factory=dict)
    niveis: Mapping[str, Nivel] = field(default_factory=dict)
    tokens_entrada: int = 0
    modelo: str = ""
    duracao_ms: int = 0

    def noul(self, pergunta: str, padrao: float = 0.0) -> float:
        return self.nouls.get(pergunta, padrao)

    def escolha(self, pergunta: str) -> Escolha | None:
        return self.escolhas.get(pergunta)

    def nivel(self, pergunta: str) -> Nivel | None:
        return self.niveis.get(pergunta)


@dataclass(frozen=True)
class Uso:
    """Soma de várias requisições de uma decisão."""

    tokens_entrada: int = 0
    requisicoes: int = 0
    duracao_ms: int = 0
    modelo: str = ""

    def mais(self, resposta: RespostaJev) -> Uso:
        return Uso(
            tokens_entrada=self.tokens_entrada + resposta.tokens_entrada,
            requisicoes=self.requisicoes + 1,
            duracao_ms=self.duracao_ms + resposta.duracao_ms,
            modelo=resposta.modelo or self.modelo,
        )

    @staticmethod
    def de(respostas: list[RespostaJev]) -> Uso:
        uso = Uso()
        for r in respostas:
            uso = uso.mais(r)
        return uso
