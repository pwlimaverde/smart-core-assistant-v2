"""Valores de domínio do motor Jev (sem pydantic: `dataclass(frozen=True)`).

O `servicer` converte o proto nestes tipos; perguntas e decisões só os
conhecem — nunca o proto nem o SDK.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class IntentDef:
    tag: str
    grupo: str = ""
    descricao: str = ""
    exemplo: str = ""
    comportamento: str = ""


@dataclass(frozen=True)
class EntidadeDef:
    """`estrategia`: regex | lista | varios | data | livre."""

    tipo: str
    descricao: str = ""
    estrategia: str = "livre"
    opcoes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Trecho:
    id: str
    conteudo: str
    distancia: float = 0.0


@dataclass(frozen=True)
class Sinal:
    """Um sinal que pesou na decisão: valor medido e limiar comparado."""

    nome: str
    valor: float
    limiar: float


@dataclass(frozen=True)
class TrechoAvaliado:
    id: str
    aprovado: bool
    conflito: bool


@dataclass(frozen=True)
class Fluxo:
    """Fluxo de destino: `chave` é o "Setor - descrição" do worker."""

    chave: str
    fluxo_id: str


@dataclass(frozen=True)
class IntencaoDetectada:
    tipo: str
    confianca: float


@dataclass(frozen=True)
class EntidadeDetectada:
    tipo: str
    valor: str
    confianca: float


@dataclass(frozen=True)
class AnaliseJev:
    """Resultado do `Analyse` pelo Jev."""

    intents: tuple[IntencaoDetectada, ...] = ()
    entidades: tuple[EntidadeDetectada, ...] = ()
    intent_principal: str = ""
    confianca_principal: float = 0.0
    intents_a_revisar: tuple[str, ...] = ()
    modelo: str = ""
    tokens_entrada: int = 0
    requisicoes: int = 0
    duracao_ms: int = 0


@dataclass(frozen=True)
class DecisaoResposta:
    """Resultado do `Responder` pelo motor Jev."""

    resposta_texto: str
    transferir: bool
    fluxo_transferencia: str
    confiabilidade: float
    motivo: str = ""
    decisao: str = "automatica"
    sinais: tuple[Sinal, ...] = ()
    trechos: tuple[TrechoAvaliado, ...] = ()
    intencao_principal: str = ""
    confianca_intencao: float = 0.0
    regra_id: int = 0
    regerada: bool = False
    modelo: str = ""
    tokens_entrada: int = 0
    requisicoes: int = 0
    duracao_ms: int = 0
    campos_extraidos: tuple[tuple[str, str, float], ...] = field(default=())
