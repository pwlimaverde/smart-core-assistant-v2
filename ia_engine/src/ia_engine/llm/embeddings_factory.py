"""Constrói um modelo de embeddings LangChain a partir de `LlmProviderConfig`."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from langchain.embeddings import init_embeddings

from ia_engine.domain.errors import ProviderConfigError

if TYPE_CHECKING:
    from langchain_core.embeddings import Embeddings

    from ia_engine.contracts import ai_engine_pb2 as pb


def build_embeddings(config: pb.LlmProviderConfig) -> Embeddings:
    """Instancia o modelo de embeddings do provedor informado no request.

    Raises:
        ProviderConfigError: se `provider` ou `model` estiverem vazios.
    """
    provider = (config.provider or "").strip()
    model = (config.model or "").strip()
    if not provider:
        raise ProviderConfigError("provider de embeddings não informado")
    if not model:
        raise ProviderConfigError("model de embeddings não informado")

    kwargs: dict[str, Any] = {}
    if config.api_key:
        kwargs["api_key"] = config.api_key

    try:
        return init_embeddings(model, provider=provider, **kwargs)
    except Exception as exc:  # noqa: BLE001
        raise ProviderConfigError(
            f"falha ao inicializar embeddings provider='{provider}' "
            f"model='{model}'"
        ) from exc
