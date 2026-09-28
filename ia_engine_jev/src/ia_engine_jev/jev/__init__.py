"""Tradução das exceções do cliente Jev para erros de domínio (`AppError`)."""

from __future__ import annotations

from py_return_success_or_error import AppError, ErrorGeneric

from ia_engine_jev.domain.errors import (
    JevIndisponivelError,
    JevNaoConfiguradoError,
    JevPerguntaInvalidaError,
    ProviderConfigError,
)
from ia_engine_jev.llm.errors import ProviderConfigException
from ia_engine_jev.typesafe import (
    JevChaveInvalida,
    JevIndisponivel,
    JevLimite,
    JevNaoConfigurado,
    JevPerguntaInvalida,
)


def erro_de_dominio(exception: Exception) -> AppError:
    """Exceção técnica → caso de domínio, sem a mensagem de terceiros."""
    match exception:
        case JevIndisponivel() | JevLimite():
            return JevIndisponivelError(message=str(exception))
        case JevNaoConfigurado() | JevChaveInvalida():
            return JevNaoConfiguradoError(message=str(exception))
        case JevPerguntaInvalida():
            return JevPerguntaInvalidaError(message=str(exception))
        case ProviderConfigException():
            return ProviderConfigError(message=str(exception))
        case _:
            return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")
