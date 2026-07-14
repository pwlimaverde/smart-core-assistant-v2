"""Constrói um chat model LangChain a partir de `LlmProviderSpec`.

A `api_key` chega por request e é passada direto ao construtor do provedor —
nunca é logada nem persistida.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from langchain.chat_models import init_chat_model

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.llm.errors import ProviderConfigException

if TYPE_CHECKING:
    from langchain_core.language_models.chat_models import BaseChatModel


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


def _extra_params(spec: LlmProviderSpec) -> dict[str, Any]:
    return {key: _coerce(value) for key, value in spec.extra_params if key}


def build_chat_model(spec: LlmProviderSpec) -> BaseChatModel:
    """Instancia o chat model do provedor informado no request.

    Raises:
        ProviderConfigException: `provider`/`model` vazios ou falha na
            inicialização (mensagem sanitizada, sem detalhes do provedor).
    """
    provider = (spec.provider or "").strip()
    model = (spec.model or "").strip()
    if not provider:
        raise ProviderConfigException("provider do LLM não informado")
    if not model:
        raise ProviderConfigException("model do LLM não informado")

    kwargs: dict[str, Any] = _extra_params(spec)
    kwargs["temperature"] = spec.temperature
    if spec.api_key:
        kwargs["api_key"] = spec.api_key

    try:
        return init_chat_model(model, model_provider=provider, **kwargs)
    except Exception as exc:
        # Não propaga detalhes do provedor (podem conter fragmentos sensíveis).
        raise ProviderConfigException(
            f"falha ao inicializar chat model provider='{provider}' "
            f"model='{model}'"
        ) from exc
