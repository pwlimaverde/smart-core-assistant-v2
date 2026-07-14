"""Usecase da feature Transcribe: regra pura sobre o dado do datasource."""

from __future__ import annotations

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine.domain.models import MediaAnalysis
from ia_engine.features.transcribe.domain.errors import (
    TranscribeError,
    TranscricaoVaziaError,
)
from ia_engine.features.transcribe.domain.models import TranscricaoBruta
from ia_engine.features.transcribe.domain.parameters import (
    TranscribeParameters,
)


class TranscribeUsecase(
    UsecaseBaseCallData[
        MediaAnalysis, TranscricaoBruta, TranscribeParameters, TranscribeError
    ]
):
    """FETCH (download + transcrição + resumo) → PROCESS (validação)."""

    def process(
        self, data: TranscricaoBruta, parameters: TranscribeParameters
    ) -> ReturnSuccessOrError[MediaAnalysis, TranscribeError]:
        transcricao = data.transcricao.strip()
        if not transcricao:
            return self.fail(
                TranscricaoVaziaError(
                    message="transcrição retornou texto vazio"
                )
            )
        return self.ok(
            MediaAnalysis(analise=transcricao, resumo=data.resumo)
        )

    def on_unexpected(self, exception: Exception) -> TranscribeError:
        return ErrorGeneric(
            message=f"{type(exception).__name__}: {exception}"
        )
