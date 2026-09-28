"""RPCs pelo motor Jev contra um `grpc.aio.server` real, com o Jev dublado.

Cobre: análise, resposta (transferência antes de gerar, geração, sem_info,
reserva quando o Jev cai), sentimento, teste de regra e a volta ao caminho da
LLM quando a chave da plataforma não está configurada.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from typing import Any

import grpc
import pytest

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.contracts import ai_engine_pb2 as pb
from ia_engine_jev.contracts import ai_engine_pb2_grpc as pbg
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.servicer import IaEngineServicer
from ia_engine_jev.typesafe import JevNaoConfigurado, RespostaJev
from tests.conftest import FakeConfigCache, runtime_config
from tests.jev_fakes import FakeJev, resposta

CHAVE = "ts-chave-da-plataforma"


@asynccontextmanager
async def _stub(
    fake: FakeJev,
    chat_factory: Callable[..., Any],
    emb_factory: Callable[..., Any],
    **config: Any,
) -> AsyncIterator[pbg.IaEngineServiceStub]:
    cfg = runtime_config(**{"typesafe_api_key": CHAVE, **config})
    chaves: list[str] = []

    def fabrica(api_key: str, _modelo: str) -> FakeJev:
        if not api_key:
            raise JevNaoConfigurado("sem chave")
        chaves.append(api_key)
        return fake

    servicer = IaEngineServicer(
        chat_model_factory=chat_factory,
        embeddings_factory=emb_factory,
        config_cache=FakeConfigCache(cfg),  # type: ignore[arg-type]
        jev_factory=fabrica,
    )
    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(servicer, server)
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as canal:
            yield pbg.IaEngineServiceStub(canal)
    finally:
        await server.stop(None)


INTENTS = [
    pb.IntentDef(tag="cartoes", descricao="cartões de visita", exemplo="quero cartões"),
    pb.IntentDef(tag="duvida_prazo", descricao="pergunta de prazo"),
]
FLUXOS = [
    pb.KeyValuePair(key="Comercial - vendas", value="10"),
    pb.KeyValuePair(key="Financeiro - boletos", value="20"),
]


def _responder(**extra: Any) -> pb.ResponderRequest:
    base: dict[str, Any] = {
        "tenant_id": "t1",
        "atendimento_id": "1",
        "mensagem": "quanto custa 500 cartões?",
        "fluxos_disponiveis": FLUXOS,
        "intents": INTENTS,
        "trechos": [pb.Trecho(id="7", conteudo="500 cartões custam R$ 90.")],
    }
    base.update(extra)
    return pb.ResponderRequest(**base)


# ------------------------------------------------------------------ Analyse
async def test_analyse_pelo_jev(fake_chat_factory, fake_embeddings_factory):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        assert etapa == "analise"
        return resposta(
            escolhas={
                pi.PRINCIPAL: ("cartoes", 0.92),
                "entidade::qtd": ("500", 0.9),
            },
            nouls={
                "intencao::duvida_prazo": 0.85,
                "entidade_presente::qtd": 0.9,
            },
        )

    fake = FakeJev(roteiro)
    async with _stub(
        fake,
        fake_chat_factory,
        fake_embeddings_factory,
        entity_descricoes={"qtd": "quantidade"},
        jev_config={"entidades": {"qtd": {"estrategia": "regex"}}},
    ) as stub:
        r = await stub.Analyse(
            pb.AnalyseRequest(
                tenant_id="t1", mensagem="quero 500 cartões", intents=INTENTS
            )
        )
    assert r.motor == "jev" and r.modelo == "jev-1.13.0"
    assert r.intent_principal == "cartoes"
    assert [i.tipo for i in r.intents] == ["cartoes", "duvida_prazo"]
    assert [(e.tipo, e.valor) for e in r.entidades] == [("qtd", "500")]
    assert r.uso.requisicoes == 1 and r.uso.tokens_entrada == 100


async def test_analyse_com_jev_fora_falha_como_hoje(
    fake_chat_factory, fake_embeddings_factory
):
    async with _stub(
        FakeJev(falha=True), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc:
            await stub.Analyse(
                pb.AnalyseRequest(tenant_id="t1", mensagem="oi", intents=INTENTS)
            )
    assert exc.value.code() == grpc.StatusCode.UNAVAILABLE


async def test_sem_chave_volta_ao_caminho_da_llm(
    fake_chat_factory, fake_embeddings_factory
):
    fake = FakeJev()
    async with _stub(
        fake, fake_chat_factory, fake_embeddings_factory, typesafe_api_key=""
    ) as stub:
        a = await stub.Analyse(
            pb.AnalyseRequest(tenant_id="t1", mensagem="oi", intents=INTENTS)
        )
        r = await stub.Responder(_responder())
    assert a.motor == "llm" and r.motor == "llm"
    assert fake.chamadas == []


# ---------------------------------------------------------------- Responder
async def test_transfere_antes_de_gerar_sem_chamar_a_llm(
    fake_chat_factory, fake_embeddings_factory
):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        if etapa == "antes":
            return resposta(
                nouls={pt.PEDE_HUMANO: 0.95},
                escolhas={pt.SETOR: ("Financeiro - boletos", 0.9)},
            )
        return resposta()

    fake = FakeJev(roteiro)
    async with _stub(fake, fake_chat_factory, fake_embeddings_factory) as stub:
        r = await stub.Responder(_responder(mensagem="quero falar com o Paulo"))
    assert r.transferir_atendimento
    assert r.motivo_transferencia == "pede_humano"
    assert r.fluxo_transferencia == "Financeiro - boletos"
    assert r.decisao == "transferida" and r.motor == "jev"
    assert r.resposta_texto == "Um momento, vou chamar um atendente."
    assert {c[0] for c in fake.chamadas} == {"antes", "trecho"}
    assert any(s.nome == "pede_humano" for s in r.sinais)


async def test_regra_do_tenant_com_mensagem_e_destino(
    fake_chat_factory, fake_embeddings_factory
):
    regra = RegraTransferencia(
        id=5,
        nome="Fechar pedido",
        condicao="O cliente quer fechar o pedido",
        destino_tipo="fluxo",
        destino_fluxo_id=10,
        mensagem="Vou passar para o comercial fechar com você.",
    )

    def roteiro(etapa: str, _s: Any, perguntas: Any) -> RespostaJev:
        if etapa == "antes":
            assert "regra::5" in perguntas
            return resposta(nouls={"regra::5": 0.9})
        return resposta()

    async with _stub(
        FakeJev(roteiro),
        fake_chat_factory,
        fake_embeddings_factory,
        regras_transferencia=[regra],
    ) as stub:
        r = await stub.Responder(_responder(mensagem="pode fechar"))
    assert r.motivo_transferencia == "regra:Fechar pedido"
    assert r.regra_id == 5
    assert r.fluxo_transferencia == "Comercial - vendas"
    assert r.resposta_texto == "Vou passar para o comercial fechar com você."


async def test_gera_so_texto_com_trecho_aprovado(
    fake_chat_factory, fake_embeddings_factory
):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        if etapa == "trecho":
            return resposta(nouls={"relevante": 0.9, "responde": 0.9})
        if etapa == "depois":
            return resposta(nouls={pc.RESPOSTA_APOIADA: 0.93})
        return resposta(nouls={pt.PEDE_INFORMACAO: 0.9})

    async with _stub(
        FakeJev(roteiro), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        r = await stub.Responder(_responder())
    assert not r.transferir_atendimento
    assert r.decisao == "automatica"
    assert r.resposta_texto == "resumo fake"  # o texto que a LLM fake devolve
    assert r.confiabilidade == pytest.approx(0.93)
    assert [(t.id, t.aprovado) for t in r.trechos] == [("7", True)]
    assert r.uso.requisicoes == 3


async def test_base_sem_resposta_manda_a_msg_sem_info(
    fake_chat_factory, fake_embeddings_factory
):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        if etapa == "antes":
            return resposta(nouls={pt.PEDE_INFORMACAO: 0.95})
        return resposta(nouls={"relevante": 0.1})

    async with _stub(
        FakeJev(roteiro), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        r = await stub.Responder(_responder())
    assert r.decisao == "sem_info"
    assert not r.transferir_atendimento
    assert r.resposta_texto == "Não encontrei essa informação."


async def test_promessa_de_transferir_e_regerada_e_marcada(
    fake_chat_factory, fake_embeddings_factory
):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        if etapa == "depois":
            return resposta(
                nouls={pc.RESPOSTA_APOIADA: 0.9, pc.RESPOSTA_TRANSFERE: 0.95}
            )
        if etapa == "trecho":
            return resposta(nouls={"relevante": 0.9, "responde": 0.9})
        return resposta()

    fake = FakeJev(roteiro)
    async with _stub(fake, fake_chat_factory, fake_embeddings_factory) as stub:
        r = await stub.Responder(_responder())
    assert r.regerada and r.decisao == "a_revisar"
    assert not r.transferir_atendimento
    assert [c[0] for c in fake.chamadas].count("depois") == 2


async def test_jev_fora_cai_na_reserva(fake_chat_factory, fake_embeddings_factory):
    async with _stub(
        FakeJev(falha=True), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        r = await stub.Responder(_responder())
    assert r.motor == "jev" and r.decisao == "reserva"
    assert r.resposta_texto  # o caminho da LLM com schema respondeu


# ------------------------------------------------------------- Sentimento
async def test_sentimento_pelo_jev(fake_chat_factory, fake_embeddings_factory):
    def roteiro(etapa: str, _s: Any, _p: Any) -> RespostaJev:
        return resposta(
            niveis={"nota": (0.4, {0: 0.7, 1: 0.3})},
            escolhas={"sentimento": ("negativo", 0.9)},
        )

    async with _stub(
        FakeJev(roteiro), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        r = await stub.Sentimento(
            pb.SentimentoRequest(
                tenant_id="t1",
                historico=pb.ChatHistory(
                    turnos=[pb.ChatTurn(role="human", conteudo="péssimo atendimento")]
                ),
            )
        )
    assert (r.nota, r.sentimento) == (1, "negativo")
    assert r.feedback == "péssimo atendimento"


async def test_sentimento_com_jev_fora_usa_a_llm(
    fake_chat_factory, fake_embeddings_factory
):
    async with _stub(
        FakeJev(falha=True), fake_chat_factory, fake_embeddings_factory
    ) as stub:
        r = await stub.Sentimento(
            pb.SentimentoRequest(
                tenant_id="t1",
                historico=pb.ChatHistory(
                    turnos=[pb.ChatTurn(role="human", conteudo="5")]
                ),
            )
        )
    assert r.nota == 5  # o fake da LLM


# ------------------------------------------------------------ Testar regra
async def test_testar_regra(fake_chat_factory, fake_embeddings_factory):
    fake = FakeJev(lambda _e, _s, _p: resposta(nouls={"regra": 0.72}))
    async with _stub(fake, fake_chat_factory, fake_embeddings_factory) as stub:
        r = await stub.TestarRegraTransferencia(
            pb.TestarRegraTransferenciaRequest(
                tenant_id="t1",
                frase="pode fechar",
                condicao="O cliente quer fechar o pedido",
                sensibilidade="alta",
            )
        )
    assert r.probabilidade == pytest.approx(0.72)
    assert r.limiar == pytest.approx(0.65) and r.dispararia
    assert fake.chamadas[0][1] == {"mensagem": "pode fechar"}


async def test_testar_regra_sem_chave(fake_chat_factory, fake_embeddings_factory):
    async with _stub(
        FakeJev(), fake_chat_factory, fake_embeddings_factory, typesafe_api_key=""
    ) as stub:
        with pytest.raises(grpc.aio.AioRpcError) as exc:
            await stub.TestarRegraTransferencia(
                pb.TestarRegraTransferenciaRequest(
                    tenant_id="t1", frase="x", condicao="y"
                )
            )
    assert exc.value.code() == grpc.StatusCode.FAILED_PRECONDITION
