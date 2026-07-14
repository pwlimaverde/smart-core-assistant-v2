"""União fechada de erros da feature Embed."""

from __future__ import annotations

from dataclasses import dataclass
from typing import final

from py_return_success_or_error import AppError, ErrorGeneric

from ia_engine.domain.errors import ProviderConfigError


@final
@dataclass(frozen=True)
class EmbeddingDimensaoError(AppError):
    """Embedding gerado com dimensão diferente da esperada (1536)."""


type EmbedError = (
    ProviderConfigError | EmbeddingDimensaoError | ErrorGeneric
)
