"""Testes da fábrica de chat models (`llm/provider_factory.py`).

Não mockamos `init_chat_model` do LangChain — ele é puramente síncrono na
resolução do provedor (nenhuma chamada de rede acontece na construção do
objeto), então exercitamos o comportamento real: provider/model ausentes,
provider desconhecido (`ValueError` do LangChain), provider conhecido mas
sem o pacote de integração instalado (`ImportError`, caso de `groq` e
`google_genai` neste ambiente) e o caminho de sucesso com `openai` (único
provedor instalado nas dependências do projeto).
"""

from __future__ import annotations

import pytest

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.llm.errors import ProviderConfigException
from ia_engine.llm.provider_factory import _coerce, _extra_params, build_chat_model


# --------------------------------------------------------------- validação
def test_provider_vazio_leva_a_provider_config_exception():
    spec = LlmProviderSpec(provider="", model="gpt-4o-mini")
    with pytest.raises(ProviderConfigException, match="provider"):
        build_chat_model(spec)


def test_provider_somente_espacos_e_tratado_como_vazio():
    spec = LlmProviderSpec(provider="   ", model="gpt-4o-mini")
    with pytest.raises(ProviderConfigException, match="provider"):
        build_chat_model(spec)


def test_model_vazio_leva_a_provider_config_exception():
    spec = LlmProviderSpec(provider="openai", model="")
    with pytest.raises(ProviderConfigException, match="model"):
        build_chat_model(spec)


# ------------------------------------------------- resolução de provider
def test_provider_desconhecido_leva_a_provider_config_exception():
    """Slug que o LangChain não reconhece (`ValueError` interno)."""
    spec = LlmProviderSpec(provider="nao-existe", model="qualquer")
    with pytest.raises(ProviderConfigException) as exc_info:
        build_chat_model(spec)
    assert "provider='nao-existe'" in str(exc_info.value)
    # a mensagem sanitizada não deve conter a lista de providers do LangChain.
    assert "Supported" not in str(exc_info.value)


def test_build_chat_model_groq_resolve_provider_e_aplica_api_key():
    """`groq` agora é dependência instalada (N6.4) — o slug resolve para
    `ChatGroq` de verdade e a `api_key` do request é injetada."""
    spec = LlmProviderSpec(
        provider="groq",
        model="llama-3.3-70b-versatile",
        api_key="gsk-test",
        temperature=0.1,
    )
    model = build_chat_model(spec)
    assert type(model).__name__ == "ChatGroq"
    assert model.groq_api_key.get_secret_value() == "gsk-test"  # type: ignore[union-attr]


def test_build_chat_model_google_genai_resolve_provider():
    """`google_genai` agora é dependência instalada (N6.4) — resolve para
    `ChatGoogleGenerativeAI`."""
    spec = LlmProviderSpec(
        provider="google_genai",
        model="gemini-2.5-flash",
        api_key="gk-test",
        temperature=0.1,
    )
    model = build_chat_model(spec)
    assert type(model).__name__ == "ChatGoogleGenerativeAI"


# ------------------------------------------------------------- sucesso
def test_build_chat_model_sucesso_aplica_temperature_e_api_key():
    spec = LlmProviderSpec(
        provider="openai", model="gpt-4o-mini", api_key="sk-test", temperature=0.3
    )
    model = build_chat_model(spec)
    assert model.temperature == pytest.approx(0.3)
    assert model.openai_api_key.get_secret_value() == "sk-test"  # type: ignore[union-attr]


def test_build_chat_model_sem_api_key_nao_forca_o_kwarg(
    monkeypatch: pytest.MonkeyPatch,
):
    """`api_key` vazia não é repassada — deixa o provedor resolver sozinho
    (ex.: variável de ambiente `OPENAI_API_KEY`)."""
    monkeypatch.setenv("OPENAI_API_KEY", "sk-env")
    spec = LlmProviderSpec(provider="openai", model="gpt-4o-mini")
    model = build_chat_model(spec)
    assert model.openai_api_key.get_secret_value() == "sk-env"  # type: ignore[union-attr]


def test_build_chat_model_aplica_extra_params_coeridos():
    spec = LlmProviderSpec(
        provider="openai",
        model="gpt-4o-mini",
        api_key="sk-test",
        extra_params=(("max_tokens", "128"),),
    )
    model = build_chat_model(spec)
    assert model.max_tokens == 128  # type: ignore[union-attr]


# --------------------------------------------------------- coerção pura
@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("true", True),
        ("True", True),
        ("false", False),
        ("FALSE", False),
        ("42", 42),
        ("3.14", 3.14),
        ("texto-livre", "texto-livre"),
    ],
)
def test_coerce_converte_string_para_tipo_usual(raw: str, expected: object):
    assert _coerce(raw) == expected


def test_extra_params_ignora_chaves_vazias():
    spec = LlmProviderSpec(
        provider="openai",
        model="gpt-4o-mini",
        extra_params=(("", "ignorado"), ("top_p", "0.9")),
    )
    assert _extra_params(spec) == {"top_p": 0.9}
