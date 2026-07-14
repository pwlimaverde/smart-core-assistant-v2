"""Repositório da feature Analyse: exceção técnica → erro de domínio."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import ProviderConfigError
from ia_engine.features.analyse.domain.errors import AnalyseError
from ia_engine.features.analyse.domain.parameters import AnalyseParameters
from ia_engine.llm.errors import ProviderConfigException


class AnalyseRepository(
    RepositoryBase[Any, AnalyseParameters, AnalyseError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: AnalyseParameters
    ) -> AnalyseError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
