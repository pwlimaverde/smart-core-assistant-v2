"""Feature Embed (RPC Embed): embeddings em batch (dimensão 1536)."""

from ia_engine.features.embed.datasources.embed_datasource import (
    EmbedDataSource,
)
from ia_engine.features.embed.domain.errors import (
    EmbeddingDimensaoError,
    EmbedError,
)
from ia_engine.features.embed.domain.parameters import EmbedParameters
from ia_engine.features.embed.domain.usecases import (
    EMBEDDING_DIM,
    EmbedUsecase,
)
from ia_engine.features.embed.repositories.embed_repository import (
    EmbedRepository,
)

__all__ = [
    "EMBEDDING_DIM",
    "EmbedDataSource",
    "EmbedError",
    "EmbedParameters",
    "EmbedRepository",
    "EmbedUsecase",
    "EmbeddingDimensaoError",
]
