"""Usecase da feature InterpretMedia: valida/converte o structured output."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine.domain.errors import LlmRespostaInvalidaError
from ia_engine.domain.models import MediaAnalysis
from ia_engine.features.interpret_media.domain.errors import (
    InterpretMediaError,
)
from ia_engine.features.interpret_media.domain.parameters import (
    InterpretMediaParameters,
)


class InterpretMediaUsecase(
    UsecaseBaseCallData[
        MediaAnalysis, Any, InterpretMediaParameters, InterpretMediaError
    ]
):
    """FETCH (download + LLM de visão) → PROCESS (validação do output)."""

    def process(
        self, data: Any, parameters: InterpretMediaParameters
    ) -> ReturnSuccessOrError[MediaAnalysis, InterpretMediaError]:
        if isinstance(data, MediaAnalysis):
            analysis = data
        elif isinstance(data, dict):
            analysis = MediaAnalysis(
                analise=str(data.get("analise", "")),
                resumo=str(data.get("resumo", "")),
            )
        else:
            return self.fail(
                LlmRespostaInvalidaError(
                    message=(
                        "LLM retornou tipo inesperado para a análise de mídia"
                    )
                )
            )

        if not (analysis.analise or "").strip():
            return self.fail(
                LlmRespostaInvalidaError(
                    message="LLM retornou análise vazia para a mídia"
                )
            )
        return self.ok(analysis)

    def on_unexpected(self, exception: Exception) -> InterpretMediaError:
        return ErrorGeneric(
            message=f"{type(exception).__name__}: {exception}"
        )
