"""União fechada de erros da feature InterpretMedia."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    MediaDownloadError,
    ProviderConfigError,
)

type InterpretMediaError = (
    ProviderConfigError
    | MediaDownloadError
    | LlmRespostaInvalidaError
    | ErrorGeneric
)
