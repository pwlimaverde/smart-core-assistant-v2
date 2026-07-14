"""Constrói um modelo de embeddings LangChain a partir de `LlmProviderSpec`."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from langchain.embeddings import init_embeddings

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.llm.errors import ProviderConfigException

if TYPE_CHECKING:
    from langchain_core.embeddings import Embeddings


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

    try:
        return init_embeddings(model, provider=provider, **kwargs)
    except Exception as exc:
        raise ProviderConfigException(
            f"falha ao inicializar embeddings provider='{provider}' "
            f"model='{model}'"
        ) from exc
