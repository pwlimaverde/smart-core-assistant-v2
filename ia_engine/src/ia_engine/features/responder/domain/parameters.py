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
    # Persona e nome do agente configurados pelo tenant: até aqui existiam no
    # banco e no painel, mas nunca chegavam à IA (não havia campo no proto).
    persona_bot: str = ""
    bot_agent_name: str = ""
    # Mensagem de transferência do tenant; vazia cai no texto genérico.
    msg_transferencia: str = ""
    # Mensagem do tenant para "não encontrei essa informação". Existia no banco,
    # no painel e no RuntimeConfig lido daqui — e nunca era aplicada.
    msg_sem_info: str = ""
    campos_coletados: tuple[CampoColetado, ...] = field(default=())
    campos_pendentes: tuple[CampoPendente, ...] = field(default=())
    # Overrides de prompt resolvidos pelo Rust (chave ausente => default do
    # datasource). Dict em vez de tupla porque a busca aqui e' por chave.
    prompts: dict[str, str] = field(default_factory=dict)
