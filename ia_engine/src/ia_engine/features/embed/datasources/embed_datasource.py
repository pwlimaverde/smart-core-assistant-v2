"""Datasource da feature Embed: chamada ao provedor de embeddings."""

from __future__ import annotations

from collections.abc import Callable

from langchain_core.embeddings import Embeddings
from py_return_success_or_error import DataSource

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.embed.domain.parameters import EmbedParameters

EmbeddingsFactory = Callable[[LlmProviderSpec], Embeddings]


class EmbedDataSource(DataSource[list[list[float]], EmbedParameters]):
    """Gera os embeddings do batch no provedor configurado."""

    def __init__(self, *, embeddings_factory: EmbeddingsFactory) -> None:
        self._embeddings_factory = embeddings_factory

    async def __call__(
        self, parameters: EmbedParameters
    ) -> list[list[float]]:
        embeddings = self._embeddings_factory(parameters.embeddings_provider)
        return await embeddings.aembed_documents(list(parameters.textos))
