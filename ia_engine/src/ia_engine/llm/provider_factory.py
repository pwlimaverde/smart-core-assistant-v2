"""Constrói um chat model LangChain a partir de `LlmProviderConfig` (proto).

A `api_key` chega por request e é passada direto ao construtor do provedor —
nunca é logada nem persistida.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from langchain.chat_models import init_chat_model

from ia_engine.domain.errors import ProviderConfigError

if TYPE_CHECKING:
    from langchain_core.language_models.chat_models import BaseChatModel

    from ia_engine.contracts import ai_engine_pb2 as pb


# Coerção leve dos `extra_params` (string no proto) para tipos usuais.
def _coerce(value: str) -> Any:
    low = value.strip().lower()
    if low in ("true", "false"):
        return low == "true"
    try:
        if "." in value:
            return float(value)
        return int(value)
    except ValueError:
        return value


def _extra_params(config: pb.LlmProviderConfig) -> dict[str, Any]:
    return {kv.key: _coerce(kv.value) for kv in config.extra_params if kv.key}


def build_chat_model(config: pb.LlmProviderConfig) -> BaseChatModel:
    """Instancia o chat model do provedor informado no request.

    Raises:
        ProviderConfigError: se `provider` ou `model` estiverem vazios.
    """
    provider = (config.provider or "").strip()
    model = (config.model or "").strip()
    if not provider:
        raise ProviderConfigError("provider do LLM não informado")
    if not model:
        raise ProviderConfigError("model do LLM não informado")

    kwargs: dict[str, Any] = _extra_params(config)
    kwargs["temperature"] = config.temperature
    if config.api_key:
        kwargs["api_key"] = config.api_key

    try:
        return init_chat_model(model, model_provider=provider, **kwargs)
    except Exception as exc:  # noqa: BLE001
        # Não propaga detalhes do provedor (podem conter fragmentos sensíveis).
        raise ProviderConfigError(
            f"falha ao inicializar chat model provider='{provider}' "
            f"model='{model}'"
        ) from exc
