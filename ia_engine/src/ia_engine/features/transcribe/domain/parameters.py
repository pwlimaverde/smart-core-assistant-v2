"""Parâmetros de entrada da feature Transcribe — só dados."""

from __future__ import annotations

from dataclasses import dataclass

from py_return_success_or_error import Parameters

from ia_engine.domain.models import LlmProviderSpec


@dataclass(frozen=True)
class TranscribeParameters(Parameters):
    """Entrada do RPC Transcribe (mídia sempre por URL pré-assinada)."""

    url: str
    mimetype: str
    language: str
    transcription_provider: LlmProviderSpec
