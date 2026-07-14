"""Usecase da feature Sentimento: valida/converte o structured output."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)
from pydantic import BaseModel

from ia_engine.domain.errors import LlmRespostaInvalidaError
from ia_engine.domain.models import AnaliseAvaliacao
from ia_engine.features.sentimento.domain.errors import SentimentoError
from ia_engine.features.sentimento.domain.parameters import (
    SentimentoParameters,
)


class SentimentoUsecase(
    UsecaseBaseCallData[
        AnaliseAvaliacao, Any, SentimentoParameters, SentimentoError
    ]
):
    """FETCH (LLM) → PROCESS (validação/conversão do output)."""

    def process(
        self, data: Any, parameters: SentimentoParameters
    ) -> ReturnSuccessOrError[AnaliseAvaliacao, SentimentoError]:
        if isinstance(data, AnaliseAvaliacao):
            return self.ok(data)
        if isinstance(data, BaseModel):
            return self.ok(AnaliseAvaliacao.model_validate(data.model_dump()))
        if isinstance(data, dict):
            return self.ok(AnaliseAvaliacao.model_validate(data))
        return self.fail(
            LlmRespostaInvalidaError(
                message="LLM retornou tipo inesperado na análise de sentimento"
            )
        )

    def on_unexpected(self, exception: Exception) -> SentimentoError:
        return ErrorGeneric(
            message=f"{type(exception).__name__}: {exception}"
        )
