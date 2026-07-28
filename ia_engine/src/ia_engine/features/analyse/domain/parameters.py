"""Parâmetros de entrada da feature Analyse — só dados."""

from __future__ import annotations

from dataclasses import dataclass, field

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.shared.history import ChatTurnTuple


@dataclass(frozen=True)
class AnalyseParameters(Parameters):
    """Entrada do RPC Analyse."""

    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    valid_intent_types: str
    valid_entity_types: tuple[str, ...]
    llm: LlmProviderSpec
    # Overrides de prompt resolvidos pelo Rust (chave ausente => default do
    # datasource). Dict em vez de tupla porque a busca aqui e' por chave.
    prompts: dict[str, str] = field(default_factory=dict)
