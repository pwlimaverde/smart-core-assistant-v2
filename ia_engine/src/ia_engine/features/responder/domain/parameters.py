"""Parâmetros de entrada da feature Responder — só dados.

O RAG textual já chega resolvido em `dados_treinamento` (o worker resolve via
`data_postgres.QueryCompose` antes desta chamada).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.shared.history import ChatTurnTuple


@dataclass(frozen=True)
class CampoColetado:
    """Campo do atendimento já coletado."""

    slug: str
    nome: str
    valor: str


@dataclass(frozen=True)
class CampoPendente:
    """Campo do atendimento ainda não coletado."""

    slug: str
    nome: str
    descricao: str
    hint: str


@dataclass(frozen=True)
class ResponderParameters(Parameters):
    """Entrada do RPC Responder."""

    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    fluxos_disponiveis: tuple[tuple[str, str], ...]
    dados_empresa: str
    dados_treinamento: str
    similarity_threshold: float
    llm: LlmProviderSpec
    embeddings_provider: LlmProviderSpec
    campos_coletados: tuple[CampoColetado, ...] = field(default=())
    campos_pendentes: tuple[CampoPendente, ...] = field(default=())
