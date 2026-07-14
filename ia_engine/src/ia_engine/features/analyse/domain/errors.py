"""União fechada de erros da feature Analyse."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    ProviderConfigError,
)

type AnalyseError = (
    ProviderConfigError | LlmRespostaInvalidaError | ErrorGeneric
)
