"""União fechada de erros da feature Sentimento."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    ProviderConfigError,
)

type SentimentoError = (
    ProviderConfigError | LlmRespostaInvalidaError | ErrorGeneric
)
