"""Geração de embeddings em batch (RPC Embed)."""

from __future__ import annotations

from langchain_core.embeddings import Embeddings

from ia_engine.domain.errors import EmbeddingError

EMBEDDING_DIM = 1536


async def embed(
    *, textos: list[str], embeddings: Embeddings
) -> list[list[float]]:
    """Gera embeddings para o batch de textos.

    Raises:
        EmbeddingError: batch vazio ou dimensão diferente de 1536.
    """
    if not textos:
        raise EmbeddingError("nenhum texto informado para embeddings")

    vectors = await embeddings.aembed_documents(textos)

    for idx, vector in enumerate(vectors):
        if len(vector) != EMBEDDING_DIM:
            raise EmbeddingError(
                f"embedding[{idx}] tem dimensão {len(vector)}, "
                f"esperado {EMBEDDING_DIM}"
            )
    return [list(v) for v in vectors]
