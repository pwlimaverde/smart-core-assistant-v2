"""União fechada de erros da feature Transcribe."""

from __future__ import annotations

from dataclasses import dataclass
from typing import final

from py_return_success_or_error import AppError, ErrorGeneric

from ia_engine.domain.errors import MediaDownloadError, ProviderConfigError


@final
@dataclass(frozen=True)
class TranscricaoVaziaError(AppError):
    """O transcritor retornou texto vazio."""


@final
@dataclass(frozen=True)
class TranscricaoIndisponivelError(AppError):
    """Transcrição de áudio ainda não integrada a um provedor concreto."""


type TranscribeError = (
    ProviderConfigError
    | MediaDownloadError
    | TranscricaoVaziaError
    | TranscricaoIndisponivelError
    | ErrorGeneric
)
