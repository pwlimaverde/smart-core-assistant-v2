"""Repositório da feature Responder: exceção técnica → erro de domínio."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import (
    LlmRespostaInvalidaError,
    ProviderConfigError,
)
from ia_engine.features.responder.domain.errors import ResponderError
from ia_engine.features.responder.domain.models import ResponderData
from ia_engine.features.responder.domain.parameters import (
    ResponderParameters,
)
from ia_engine.llm.errors import (
    LlmOutputInesperadoException,
    ProviderConfigException,
)


class ResponderRepository(
    RepositoryBase[ResponderData, ResponderParameters, ResponderError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: ResponderParameters
    ) -> ResponderError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case LlmOutputInesperadoException():
                return LlmRespostaInvalidaError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
