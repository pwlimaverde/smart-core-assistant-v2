"""Usecase da feature Embed: valida a dimensão dos vetores (1536)."""

from __future__ import annotations

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine.features.embed.domain.errors import (
    EmbeddingDimensaoError,
    EmbedError,
)
from ia_engine.features.embed.domain.parameters import EmbedParameters

# Dimensão do schema pgvector `vector(1536)` (migração 0007) — validada em
# todo batch para a falha aparecer aqui, não silenciosa na gravação.
EMBEDDING_DIM = 1536


class EmbedUsecase(
    UsecaseBaseCallData[
        list[list[float]], list[list[float]], EmbedParameters, EmbedError
    ]
):
    """FETCH (provedor de embeddings) → PROCESS (validação de dimensão)."""

    def process(
        self, data: list[list[float]], parameters: EmbedParameters
    ) -> ReturnSuccessOrError[list[list[float]], EmbedError]:
        for idx, vector in enumerate(data):
            if len(vector) != EMBEDDING_DIM:
                return self.fail(
                    EmbeddingDimensaoError(
                        message=(
                            f"embedding[{idx}] tem dimensão {len(vector)}, "
                            f"esperado {EMBEDDING_DIM}"
                        )
                    )
                )
        return self.ok([list(v) for v in data])

    def on_unexpected(self, exception: Exception) -> EmbedError:
        return ErrorGeneric(
            message=f"{type(exception).__name__}: {exception}"
        )
