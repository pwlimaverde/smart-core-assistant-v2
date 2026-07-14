"""Repositório da feature InterpretMedia: exceção técnica → erro de domínio."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import MediaDownloadError, ProviderConfigError
from ia_engine.features.interpret_media.domain.errors import (
    InterpretMediaError,
)
from ia_engine.features.interpret_media.domain.parameters import (
    InterpretMediaParameters,
)
from ia_engine.llm.errors import ProviderConfigException
from ia_engine.shared.media import MediaDownloadException


class InterpretMediaRepository(
    RepositoryBase[Any, InterpretMediaParameters, InterpretMediaError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: InterpretMediaParameters
    ) -> InterpretMediaError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case MediaDownloadException():
                return MediaDownloadError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
