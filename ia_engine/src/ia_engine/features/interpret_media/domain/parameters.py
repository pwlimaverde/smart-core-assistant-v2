"""Parâmetros de entrada da feature InterpretMedia — só dados."""

from __future__ import annotations

from dataclasses import dataclass

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
