"""Usecase da feature ExtrairTextoDocumento: regra pura sobre o texto lido."""

from __future__ import annotations

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine.features.extrair_texto.domain.errors import (
    ExtrairTextoError,
    TextoVazioError,
)
from ia_engine.features.extrair_texto.domain.models import TextoExtraido
from ia_engine.features.extrair_texto.domain.parameters import (
    ExtrairTextoParameters,
)


class ExtrairTextoUsecase(
    UsecaseBaseCallData[
        TextoExtraido, TextoExtraido, ExtrairTextoParameters, ExtrairTextoError
    ]
):
    """FETCH (download + leitura) → PROCESS (documento sem texto é falha)."""

    def process(
        self, data: TextoExtraido, parameters: ExtrairTextoParameters
    ) -> ReturnSuccessOrError[TextoExtraido, ExtrairTextoError]:
        texto = data.texto.strip()
        if not texto:
            # Vetorizar texto vazio casaria com qualquer pergunta; e quem treinou
            # precisa saber que o arquivo (ex.: PDF escaneado) não tinha texto.
            return self.fail(
                TextoVazioError(
                    message=(
                        "o arquivo não tem texto legível "
                        "(PDF escaneado precisa passar por OCR antes)"
                    )
                )
            )
        return self.ok(TextoExtraido(texto=texto, formato=data.formato))

    def on_unexpected(self, exception: Exception) -> ExtrairTextoError:
        return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")
