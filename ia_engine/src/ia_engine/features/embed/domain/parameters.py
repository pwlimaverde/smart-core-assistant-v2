"""Parâmetros de entrada da feature Embed — só dados."""

from __future__ import annotations

from dataclasses import dataclass

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec


@dataclass(frozen=True)
class EmbedParameters(Parameters):
    """Entrada do RPC Embed (batch nunca vazio — validado no servicer)."""

    textos: tuple[str, ...]
    embeddings_provider: LlmProviderSpec
