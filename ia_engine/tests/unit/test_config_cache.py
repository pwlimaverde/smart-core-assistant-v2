"""Cache de config e canal de invalidação (`ia_engine.config`).

Usa um fake de Redis em memória em vez de servidor real: o que precisa ser
provado aqui é o contrato (chave lida, erro quando falta, cópia local
descartada na invalidação), não o driver.
"""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from ia_engine.config.cache import ConfigIndisponivelError, TenantConfigCache
from ia_engine.config.listener import CANAL_INVALIDACAO, escutar_invalidacoes
from ia_engine.config.models import RuntimeConfig

TENANT = "f47ac10b-58cc-4372-a567-0e02b2c3d479"


def _payload(**overrides: Any) -> str:
    """JSON no formato que o `RuntimeConfigDto` do Rust publica."""
    base: dict[str, Any] = {
        "tenant_id": TENANT,
        "dados_empresa": "Acme LTDA",
        "persona_bot": "cordial e objetivo",
        "bot_agent_name": "Ana",
        "msg_fallback": "falhou",
        "msg_sem_info": "sem info",
        "msg_transferencia": "transferindo",
        "llm_class": "ChatGoogleGenerativeAI",
        "model": "gemini-2.5-flash-lite",
        "llm_temperature": 0.0,
        "transcription_provider": "groq",
        "transcription_model": "whisper-large-v3-turbo",
        "transcription_enabled": True,
        "vision_provider": "google",
        "vision_model": "gemini-2.5-flash-lite",
        "embeddings_class": "OpenAIEmbeddings",
        "embeddings_model": "text-embedding-3-small",
        "chunk_size": 1000,
        "chunk_overlap": 200,
        "similarity_threshold": 0.4,
        "vector_distance_threshold": 0.5,
        "openai_api_key": "sk-openai",
        "groq_api_key": "gsk-groq",
        "google_api_key": "goog-key",
        "prompts": {},
    }
    base.update(overrides)
    import json

    return json.dumps(base)


class FakeRedis:
    """Mínimo do contrato usado: `get` e um `pubsub` que entrega mensagens."""

    def __init__(self, dados: dict[str, str] | None = None) -> None:
        self.dados = dados or {}
        self.gets = 0
        self.mensagens: list[dict[str, Any]] = []
        self.erro_no_get: Exception | None = None

    async def get(self, chave: str) -> str | None:
        self.gets += 1
        if self.erro_no_get is not None:
            raise self.erro_no_get
        return self.dados.get(chave)

    def pubsub(self) -> FakePubSub:
        return FakePubSub(self.mensagens)


class FakePubSub:
    def __init__(self, mensagens: list[dict[str, Any]]) -> None:
        self._mensagens = mensagens
        self.canais: list[str] = []
        self.fechado = False

    async def subscribe(self, canal: str) -> None:
        self.canais.append(canal)

    async def listen(self):
        for m in self._mensagens:
            yield m

    async def aclose(self) -> None:
        self.fechado = True


# ------------------------------------------------------------------- cache
@pytest.mark.asyncio
async def test_le_a_config_da_chave_que_o_rust_publica():
    redis = FakeRedis({f"tenant:config:{TENANT}": _payload()})
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    config = await cache.get_config(TENANT)

    assert config.model == "gemini-2.5-flash-lite"
    assert config.persona_bot == "cordial e objetivo"


@pytest.mark.asyncio
async def test_segunda_leitura_vem_do_cache_local_sem_tocar_o_redis():
    redis = FakeRedis({f"tenant:config:{TENANT}": _payload()})
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    await cache.get_config(TENANT)
    await cache.get_config(TENANT)

    assert redis.gets == 1, "o cache local deveria evitar o segundo GET"


@pytest.mark.asyncio
async def test_config_ausente_falha_explicito_em_vez_de_chamar_llm_sem_chave():
    cache = TenantConfigCache(FakeRedis())  # type: ignore[arg-type]

    with pytest.raises(ConfigIndisponivelError) as exc_info:
        await cache.get_config(TENANT)

    assert TENANT in str(exc_info.value)


@pytest.mark.asyncio
async def test_redis_fora_do_ar_vira_erro_de_dominio():
    redis = FakeRedis()
    redis.erro_no_get = ConnectionError("connection refused")
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    with pytest.raises(ConfigIndisponivelError):
        await cache.get_config(TENANT)


@pytest.mark.asyncio
async def test_payload_corrompido_nao_vaza_conteudo_na_mensagem():
    """A mensagem de erro não pode carregar o payload: ele traz as chaves de
    API decifradas."""
    redis = FakeRedis({f"tenant:config:{TENANT}": '{"nao_e": "config valida"'})
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    with pytest.raises(ConfigIndisponivelError) as exc_info:
        await cache.get_config(TENANT)

    assert "nao_e" not in str(exc_info.value)


@pytest.mark.asyncio
async def test_invalidacao_forca_releitura():
    redis = FakeRedis({f"tenant:config:{TENANT}": _payload()})
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    await cache.get_config(TENANT)
    await cache.invalidate(TENANT)
    redis.dados[f"tenant:config:{TENANT}"] = _payload(model="gpt-4o-mini")
    config = await cache.get_config(TENANT)

    assert redis.gets == 2
    assert config.model == "gpt-4o-mini"


# ---------------------------------------------------------------- listener
@pytest.mark.asyncio
async def test_listener_invalida_o_tenant_anunciado_no_canal():
    redis = FakeRedis({f"tenant:config:{TENANT}": _payload()})
    redis.mensagens = [{"type": "message", "data": TENANT.encode("utf-8")}]
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]
    await cache.get_config(TENANT)

    parar = asyncio.Event()
    parar.set()  # uma passagem só: consome as mensagens e encerra
    await escutar_invalidacoes(redis, cache, parar=parar)  # type: ignore[arg-type]

    redis.dados[f"tenant:config:{TENANT}"] = _payload(persona_bot="nova persona")
    assert (await cache.get_config(TENANT)).persona_bot == "nova persona"


@pytest.mark.asyncio
async def test_listener_assina_o_canal_do_contrato_com_o_rust():
    redis = FakeRedis()
    redis.mensagens = [{"type": "subscribe", "data": 1}]
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    parar = asyncio.Event()
    parar.set()
    await escutar_invalidacoes(redis, cache, parar=parar)  # type: ignore[arg-type]

    assert CANAL_INVALIDACAO == "tenant:config:invalidate"


@pytest.mark.asyncio
async def test_payload_vazio_derruba_o_cache_inteiro():
    """Servir config velha é pior que reler: sem tenant identificável, limpa tudo."""
    redis = FakeRedis({f"tenant:config:{TENANT}": _payload()})
    redis.mensagens = [{"type": "message", "data": b""}]
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]
    await cache.get_config(TENANT)

    parar = asyncio.Event()
    parar.set()
    await escutar_invalidacoes(redis, cache, parar=parar)  # type: ignore[arg-type]

    await cache.get_config(TENANT)
    assert redis.gets == 2, "esperado releitura apos invalidacao global"


@pytest.mark.asyncio
async def test_listener_reassina_quando_o_canal_cai(
    monkeypatch: pytest.MonkeyPatch,
):
    """Uma queda de conexão não pode encerrar o listener em silêncio: sem ele a
    IA passaria a servir config velha sem ninguém perceber."""
    monkeypatch.setattr("ia_engine.config.listener._BACKOFF_SEGUNDOS", 0.0)

    tentativas = 0

    class RedisQueDerrubaUmaVez(FakeRedis):
        def pubsub(self):
            nonlocal tentativas
            tentativas += 1
            if tentativas == 1:
                raise ConnectionError("conexao perdida")
            return FakePubSub([{"type": "message", "data": TENANT.encode()}])

    redis = RedisQueDerrubaUmaVez()
    cache = TenantConfigCache(redis)  # type: ignore[arg-type]

    parar = asyncio.Event()

    async def _parar_apos_reassinatura() -> None:
        while tentativas < 2:
            await asyncio.sleep(0)
        parar.set()

    await asyncio.gather(
        escutar_invalidacoes(redis, cache, parar=parar),  # type: ignore[arg-type]
        _parar_apos_reassinatura(),
    )

    assert tentativas >= 2, "o listener deveria ter reassinado apos a queda"


# ------------------------------------------------------------------ specs
def test_spec_llm_traduz_classe_langchain_para_slug_e_escolhe_a_chave_certa():
    """A config guarda nome de classe (herança da v1); as fábricas precisam do
    slug do provedor — e da chave daquele provedor, não de outra."""
    config = RuntimeConfig.model_validate_json(_payload())

    llm = config.spec_llm()
    embeddings = config.spec_embeddings()

    assert llm.provider == "google_genai"
    assert llm.api_key == "goog-key"
    # Embeddings usa outro provedor: a chave tem de acompanhar.
    assert embeddings.provider == "openai"
    assert embeddings.api_key == "sk-openai"


def test_spec_transcription_usa_a_chave_do_groq():
    config = RuntimeConfig.model_validate_json(_payload())

    spec = config.spec_transcription()

    assert spec.provider == "groq"
    assert spec.api_key == "gsk-groq"
    assert spec.model == "whisper-large-v3-turbo"


def test_spec_vision_usa_provedor_e_chave_de_visao():
    """`vision_provider` já vem como slug ('google'), não nome de classe —
    passa pela mesma normalização e tem de resolver a chave do Google."""
    config = RuntimeConfig.model_validate_json(_payload())

    spec = config.spec_vision()

    assert spec.provider == "google_genai"
    assert spec.api_key == "goog-key"
    assert spec.model == "gemini-2.5-flash-lite"


def test_prompt_cai_no_default_quando_nao_ha_override():
    config = RuntimeConfig.model_validate_json(_payload())

    assert config.prompt("PROMPT_REGRAS_RESPOSTA", "default do codigo") == (
        "default do codigo"
    )


def test_prompt_usa_o_override_publicado():
    config = RuntimeConfig.model_validate_json(
        _payload(prompts={"PROMPT_REGRAS_RESPOSTA": "regra do tenant"})
    )

    assert config.prompt("PROMPT_REGRAS_RESPOSTA", "default") == "regra do tenant"


def test_prompt_em_branco_nao_apaga_o_default():
    """O Rust omite vazios, mas um valor só com espaços não pode zerar o prompt."""
    config = RuntimeConfig.model_validate_json(
        _payload(prompts={"PROMPT_REGRAS_RESPOSTA": "   "})
    )

    assert config.prompt("PROMPT_REGRAS_RESPOSTA", "default") == "default"
