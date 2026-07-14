"""Repositório da feature Sentimento: exceção técnica → erro de domínio."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import ProviderConfigError
from ia_engine.features.sentimento.domain.errors import SentimentoError
from ia_engine.features.sentimento.domain.parameters import (
    SentimentoParameters,
)
from ia_engine.llm.errors import ProviderConfigException


class SentimentoRepository(
    RepositoryBase[Any, SentimentoParameters, SentimentoError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: SentimentoParameters
    ) -> SentimentoError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
