"""Testes da fábrica de embeddings (`llm/embeddings_factory.py`).

Mesma lógica de `test_provider_factory.py`: `init_embeddings` do LangChain
não faz chamada de rede na construção, então exercitamos o comportamento
real (`langchain-openai` e `langchain-google-genai` instalados).

Nota sobre `output_dimensionality`: o schema pgvector do projeto é
`vector(1536)` (ver `features/embed/domain/usecases.py::EMBEDDING_DIM`), e
o modelo padrão do Google (`gemini-embedding-001`) retorna 3072 dimensões
por padrão — só bate com o schema se `output_dimensionality=1536` for
passado explicitamente ao construir o embedder. A partir da N6.4,
`build_embeddings` força `output_dimensionality=1536` para o provider
`google_genai` (coberto abaixo); a validação no usecase
(`EmbeddingDimensaoError`, em `test_usecases_rsoe.py`) segue como segunda
rede de segurança.
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


def test_build_embeddings_google_genai_forca_dimensao_1536():
    """`google_genai` agora é dependência instalada (N6.4). O default do
    modelo é 3072/768; `build_embeddings` DEVE forçar 1536 (pgvector) — nunca
    deixar implícito, senão o RAG quebraria silenciosamente na gravação."""
    spec = LlmProviderSpec(
        provider="google_genai",
        model="models/gemini-embedding-001",
        api_key="gk-test",
    )
    embeddings = build_embeddings(spec)
    assert type(embeddings).__name__ == "GoogleGenerativeAIEmbeddings"
    assert embeddings.output_dimensionality == 1536  # type: ignore[union-attr]


def test_build_embeddings_openai_nao_recebe_output_dimensionality():
    """A dimensão forçada é exclusiva do Google — OpenAI não deve recebê-la
    (usaria `dimensions`, não `output_dimensionality`)."""
    spec = LlmProviderSpec(
        provider="openai", model="text-embedding-3-small", api_key="sk-test"
    )
    embeddings = build_embeddings(spec)
    assert not hasattr(embeddings, "output_dimensionality")


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
