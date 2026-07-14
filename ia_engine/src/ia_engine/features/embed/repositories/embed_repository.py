"""Repositório da feature Embed: exceção técnica → erro de domínio."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import ProviderConfigError
from ia_engine.features.embed.domain.errors import EmbedError
from ia_engine.features.embed.domain.parameters import EmbedParameters
from ia_engine.llm.errors import ProviderConfigException


class EmbedRepository(
    RepositoryBase[list[list[float]], EmbedParameters, EmbedError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: EmbedParameters
    ) -> EmbedError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
