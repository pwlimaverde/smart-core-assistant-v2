"""Efeitos da config de tenant no fluxo real dos RPCs.

Estes testes cobrem exatamente o que estava quebrado antes de a config vir do
Redis: a persona e as mensagens configuradas pelo tenant não chegavam à IA
(não havia campo no proto), e os prompts eram constantes no código.

Cada teste vai pelo `grpc.aio.server` real e inspeciona o que o LLM recebeu,
em vez de checar o objeto de parâmetros — é a única forma de provar que o dado
atravessou servicer, usecase e datasource até o prompt.
"""

from __future__ import annotations

import itertools
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import grpc
import pytest
from langchain_core.messages import AIMessage

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.domain.models import RespostaBot
from ia_engine.servicer import IaEngineServicer
from tests.conftest import (
    FakeChatModel,
    FakeConfigCache,
    FakeEmbeddings,
    runtime_config,
)


class ChatQueRegistraPrompt(FakeChatModel):
    """Guarda o prompt de sistema que o LLM recebeu, para inspeção."""

    capturado: Any = None

    def with_structured_output(self, schema: Any, **kwargs: Any):  # type: ignore[override]
        runnable = super().with_structured_output(schema, **kwargs)
        registro = self

        class _Espiao:
            def __or__(self, outro: Any) -> Any:  # pragma: no cover - não usado
                return outro

            async def ainvoke(self, entrada: Any, *a: Any, **kw: Any) -> Any:
                return await runnable.ainvoke(entrada, *a, **kw)

        # O prompt vira ChatPromptTemplate | modelo; o template formata antes de
        # chegar aqui, então basta interceptar a mensagem já renderizada.
        original = runnable.ainvoke

        async def _ainvoke(entrada: Any, *a: Any, **kw: Any) -> Any:
            registro.capturado = entrada
            return await original(entrada, *a, **kw)

        runnable.ainvoke = _ainvoke  # type: ignore[method-assign]
        return runnable


@asynccontextmanager
async def _stub(servicer: IaEngineServicer) -> AsyncIterator[pbg.IaEngineServiceStub]:
    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(servicer, server)
    porta = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{porta}") as canal:
            yield pbg.IaEngineServiceStub(canal)
    finally:
        await server.stop(None)


def _chat_com_resposta(texto: str, confianca: float = 0.9) -> ChatQueRegistraPrompt:
    return ChatQueRegistraPrompt(
        messages=itertools.cycle([AIMessage(content="")]),
        resposta_bot=RespostaBot(
            resposta_texto=texto, acao_transferencia=None, confianca=confianca
        ),
    )


def _responder_request() -> pb.ResponderRequest:
    return pb.ResponderRequest(
        tenant_id="t1",
        atendimento_id="42",
        mensagem="meu aparelho parou",
        dados_treinamento="Manual: reiniciar o aparelho.",
    )


# ------------------------------------------------------- persona e identidade
@pytest.mark.asyncio
async def test_persona_e_nome_do_agente_chegam_ao_prompt():
    """Antes desta mudança, `persona_bot` e `bot_agent_name` existiam no banco
    e no painel mas não tinham campo no proto — o tenant configurava e nada
    acontecia."""
    chat = _chat_com_resposta("Olá!")
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(
                persona_bot="irônico e brevíssimo", bot_agent_name="Zé do Suporte"
            )
        ),
    )
    async with _stub(servicer) as stub:
        await stub.Responder(_responder_request())

    prompt = str(chat.capturado)
    assert "Zé do Suporte" in prompt
    assert "irônico e brevíssimo" in prompt


@pytest.mark.asyncio
async def test_dados_da_empresa_vem_da_config_e_nao_do_request():
    chat = _chat_com_resposta("Olá!")
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(dados_empresa="Fábrica de Guarda-Chuvas Ltda")
        ),
    )
    async with _stub(servicer) as stub:
        await stub.Responder(_responder_request())

    assert "Fábrica de Guarda-Chuvas Ltda" in str(chat.capturado)


# ------------------------------------------------------------ prompt override
@pytest.mark.asyncio
async def test_regras_de_resposta_configuradas_substituem_o_default():
    chat = _chat_com_resposta("Olá!")
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(
                prompts={
                    "PROMPT_REGRAS_RESPOSTA": "### Regra única: responda em haicai."
                }
            )
        ),
    )
    async with _stub(servicer) as stub:
        await stub.Responder(_responder_request())

    prompt = str(chat.capturado)
    assert "responda em haicai" in prompt
    # O default some quando há override — não são concatenados.
    assert "siga rigorosamente" not in prompt


@pytest.mark.asyncio
async def test_sem_override_o_prompt_default_do_codigo_e_usado():
    """A IA não pode ficar sem prompt porque ninguém semeou a chave."""
    chat = _chat_com_resposta("Olá!")
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(runtime_config(prompts={})),
    )
    async with _stub(servicer) as stub:
        await stub.Responder(_responder_request())

    assert "siga rigorosamente" in str(chat.capturado)


# ------------------------------------------------- mensagem de transferência
@pytest.mark.asyncio
async def test_mensagem_de_transferencia_do_tenant_e_usada():
    """Score baixo + confiança baixa força transferência; o aviso anexado deve
    ser o do tenant, não a constante do código."""
    chat = _chat_com_resposta("Não sei responder isso.", confianca=0.1)
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(
                msg_transferencia="Chamando o Zé, aguarde.",
                similarity_threshold=0.99,  # força o caminho de transferência
            )
        ),
    )
    async with _stub(servicer) as stub:
        resp = await stub.Responder(_responder_request())

    assert resp.transferir_atendimento is True
    assert "Chamando o Zé, aguarde." in resp.resposta_texto
    assert "um de nossos atendentes" not in resp.resposta_texto


@pytest.mark.asyncio
async def test_sem_mensagem_configurada_cai_no_texto_generico():
    chat = _chat_com_resposta("Não sei responder isso.", confianca=0.1)
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(msg_transferencia="", similarity_threshold=0.99)
        ),
    )
    async with _stub(servicer) as stub:
        resp = await stub.Responder(_responder_request())

    assert "um de nossos atendentes" in resp.resposta_texto


# --------------------------------------------------------- config indisponível
@pytest.mark.asyncio
async def test_config_ausente_aborta_com_failed_precondition():
    """Sem config publicada, o RPC falha ANTES de chamar o provedor: chamar o
    LLM sem chave gastaria uma requisição para mascarar um problema de
    provisionamento."""
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: _chat_com_resposta("nunca chamado"),
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(ausente=True),
    )
    async with _stub(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Responder(_responder_request())

    assert exc_info.value.code() == grpc.StatusCode.FAILED_PRECONDITION
    assert "t1" in exc_info.value.details()


@pytest.mark.asyncio
async def test_config_e_consultada_pelo_tenant_id_do_request():
    cache = FakeConfigCache()
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: _chat_com_resposta("oi"),
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=cache,
    )
    request = _responder_request()
    request.tenant_id = "tenant-especifico"
    async with _stub(servicer) as stub:
        await stub.Responder(request)

    assert cache.consultas == ["tenant-especifico"]


@pytest.mark.asyncio
async def test_regras_de_transferencia_sao_anexadas_quando_configuradas():
    """Bloco separado na v1: quando presente, soma-se às regras de resposta em
    vez de substituí-las."""
    chat = _chat_com_resposta("Olá!")
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: chat,
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=FakeConfigCache(
            runtime_config(
                prompts={
                    "PROMPT_REGRAS_TRANSFERENCIA": "### Transfira sempre às 18h."
                }
            )
        ),
    )
    async with _stub(servicer) as stub:
        await stub.Responder(_responder_request())

    prompt = str(chat.capturado)
    assert "Transfira sempre às 18h" in prompt
    assert "siga rigorosamente" in prompt, "as regras padrão devem permanecer"


@pytest.mark.asyncio
async def test_sem_cache_de_config_o_rpc_falha_em_vez_de_chamar_o_llm():
    """Processo mal configurado (sem Redis) não pode degradar silenciosamente
    para uma chamada de LLM sem credencial."""
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: _chat_com_resposta("nunca chamado"),
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        # config_cache ausente de propósito
    )
    async with _stub(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Responder(_responder_request())

    assert exc_info.value.code() == grpc.StatusCode.INVALID_ARGUMENT
    assert "sem cache de config" in exc_info.value.details()


@pytest.mark.asyncio
async def test_tenant_id_vazio_falha_antes_de_consultar_o_cache():
    cache = FakeConfigCache()
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: _chat_com_resposta("x"),
        embeddings_factory=lambda _spec: FakeEmbeddings(),
        config_cache=cache,
    )
    request = _responder_request()
    request.tenant_id = ""
    async with _stub(servicer) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc_info:
            await stub.Responder(request)

    assert exc_info.value.code() == grpc.StatusCode.INVALID_ARGUMENT
    assert "tenant_id" in exc_info.value.details()
    assert cache.consultas == [], "não faz sentido consultar cache sem tenant"


@pytest.mark.asyncio
async def test_transcribe_respeita_o_kill_switch_do_tenant():
    """Flag global ligada, mas o tenant desligou: não gasta transcrição."""
    servicer = IaEngineServicer(
        chat_model_factory=lambda _spec: _chat_com_resposta("x"),
        transcriber_factory=lambda _spec: pytest.fail(
            "não deveria construir transcritor com o tenant desligado"
        ),
        transcription_enabled=True,
        config_cache=FakeConfigCache(runtime_config(transcription_enabled=False)),
    )
    async with _stub(servicer) as stub:
        resp = await stub.Transcribe(
            pb.TranscribeRequest(
                tenant_id="t1",
                media=pb.MediaRef(url="https://r2/a.ogg", mimetype="audio/ogg"),
                language="pt",
            )
        )

    assert resp.transcricao == ""
