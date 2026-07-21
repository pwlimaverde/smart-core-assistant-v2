"""Constrói um modelo de embeddings LangChain a partir de `LlmProviderSpec`."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from langchain.embeddings import init_embeddings

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.llm.errors import ProviderConfigException

if TYPE_CHECKING:
    from langchain_core.embeddings import Embeddings

# Dimensão do schema pgvector `vector(1536)` (validada em EmbedUsecase). O
# default do Google (`gemini-embedding-001`) é 3072 — sem forçar 1536 aqui o
# RAG quebraria silenciosamente na gravação. Nunca deixar implícito.
_PGVECTOR_DIM = 1536
_GOOGLE_PROVIDER = "google_genai"


def build_embeddings(spec: LlmProviderSpec) -> Embeddings:
    """Instancia o modelo de embeddings do provedor informado no request.

    Raises:
        ProviderConfigException: `provider`/`model` vazios ou falha na
            inicialização (mensagem sanitizada, sem detalhes do provedor).
    """
    provider = (spec.provider or "").strip()
    model = (spec.model or "").strip()
    if not provider:
        raise ProviderConfigException("provider de embeddings não informado")
    if not model:
        raise ProviderConfigException("model de embeddings não informado")

    kwargs: dict[str, Any] = {}
    if spec.api_key:
        kwargs["api_key"] = spec.api_key
    if provider == _GOOGLE_PROVIDER:
        # pgvector espera 1536; o default 3072 do Google romperia o schema.
        kwargs["output_dimensionality"] = _PGVECTOR_DIM

    try:
        return init_embeddings(model, provider=provider, **kwargs)
    except Exception as exc:
        raise ProviderConfigException(
            f"falha ao inicializar embeddings provider='{provider}' "
            f"model='{model}'"
        ) from exc
