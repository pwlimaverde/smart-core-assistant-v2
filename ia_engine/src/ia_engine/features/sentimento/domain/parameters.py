"""Parâmetros de entrada da feature Sentimento — só dados."""

from __future__ import annotations

from dataclasses import dataclass

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.shared.history import ChatTurnTuple


@dataclass(frozen=True)
class SentimentoParameters(Parameters):
    """Entrada do RPC Sentimento."""

    historico: tuple[ChatTurnTuple, ...]
    llm: LlmProviderSpec
