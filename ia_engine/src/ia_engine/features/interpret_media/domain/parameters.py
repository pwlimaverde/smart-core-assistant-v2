"""Parâmetros de entrada da feature InterpretMedia — só dados."""

from __future__ import annotations

from dataclasses import dataclass, field

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec


@dataclass(frozen=True)
class InterpretMediaParameters(Parameters):
    """Entrada do RPC InterpretMedia (mídia sempre por URL pré-assinada)."""

    url: str
    mimetype: str
    media_type: str
    file_name: str
    vision_provider: LlmProviderSpec
    # Overrides de prompt resolvidos pelo Rust (chave ausente => default do
    # datasource). Dict em vez de tupla porque a busca aqui e' por chave.
    prompts: dict[str, str] = field(default_factory=dict)
