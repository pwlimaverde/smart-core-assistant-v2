"""Testes da fábrica de embeddings (`llm/embeddings_factory.py`).

Mesma lógica de `test_provider_factory.py`: `init_embeddings` do LangChain
não faz chamada de rede na construção, então exercitamos o comportamento
real (só `langchain-openai` está instalado nas dependências do projeto).

Nota sobre `output_dimensionality`: o schema pgvector do projeto é
`vector(1536)` (ver `features/embed/domain/usecases.py::EMBEDDING_DIM`), e
o modelo padrão do Google (`gemini-embedding-001`) retorna 3072 dimensões
por padrão — só bate com o schema se `output_dimensionality=1536` for
passado explicitamente ao construir o embedder. Hoje `build_embeddings`
**não** repassa `extra_params`/`output_dimensionality` (só `api_key`) — a
única rede de segurança contra dimensão errada é a validação no usecase
(`EmbeddingDimensaoError`, já coberta em `test_usecases_rsoe.py`). Como
`langchain-google-genai` não é dependência instalada do projeto, o
provider `google_genai` falha hoje por `ImportError` (pacote ausente)
antes mesmo de chegar a essa questão — comportamento coberto abaixo.
"""

from __future__ import annotations

import pytest

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.llm.embeddings_factory import build_embeddings
from ia_engine.llm.errors import ProviderConfigException


def test_provider_vazio_leva_a_provider_config_exception():
    spec = LlmProviderSpec(provider="", model="text-embedding-3-small")
    with pytest.raises(ProviderConfigException, match="provider"):
        build_embeddings(spec)


def test_model_vazio_leva_a_provider_config_exception():
    spec = LlmProviderSpec(provider="openai", model="")
    with pytest.raises(ProviderConfigException, match="model"):
        build_embeddings(spec)


def test_provider_desconhecido_leva_a_provider_config_exception():
    spec = LlmProviderSpec(provider="nao-existe", model="qualquer")
    with pytest.raises(ProviderConfigException) as exc_info:
        build_embeddings(spec)
    assert "provider='nao-existe'" in str(exc_info.value)
    assert "Supported" not in str(exc_info.value)


def test_provider_google_genai_sem_pacote_instalado_falha():
    """`google_genai` é um provider válido do LangChain, mas o pacote
    `langchain-google-genai` não está instalado (só `langchain-openai` é
    dependência do projeto) — vira `ImportError` interno, traduzido para o
    erro fechado da camada LLM."""
    spec = LlmProviderSpec(
        provider="google_genai", model="models/gemini-embedding-001"
    )
    with pytest.raises(ProviderConfigException, match="google_genai"):
        build_embeddings(spec)


def test_build_embeddings_sucesso_aplica_api_key():
    spec = LlmProviderSpec(
        provider="openai", model="text-embedding-3-small", api_key="sk-test"
    )
    embeddings = build_embeddings(spec)
    assert embeddings.openai_api_key.get_secret_value() == "sk-test"  # type: ignore[union-attr]


def test_build_embeddings_sem_api_key_nao_forca_o_kwarg(
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-env")
    spec = LlmProviderSpec(provider="openai", model="text-embedding-3-small")
    embeddings = build_embeddings(spec)
    assert embeddings.openai_api_key.get_secret_value() == "sk-env"  # type: ignore[union-attr]
