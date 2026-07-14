"""Parâmetros de entrada da feature Analyse — só dados."""

from __future__ import annotations

from dataclasses import dataclass

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
