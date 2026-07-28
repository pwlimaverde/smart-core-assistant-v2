"""Roundtrip dos 6 RPCs contra um grpc.aio.server real (LLM/embeddings fakes)."""

from __future__ import annotations

import loguru
import pytest

from ia_engine.contracts import ai_engine_pb2 as pb


@pytest.mark.asyncio
async def test_transcribe_roundtrip(ia_stub):
    resp = await ia_stub.Transcribe(
        pb.TranscribeRequest(
            tenant_id="t1",
            media=pb.MediaRef(url="https://r2.example/audio.ogg", mimetype="audio/ogg"),
            language="pt",
        )
    )
    assert resp.transcricao == "transcrição fake do áudio"
    assert resp.resumo  # resumo gerado pelo chat fake


@pytest.mark.asyncio
async def test_interpret_media_roundtrip(ia_stub):
    resp = await ia_stub.InterpretMedia(
        pb.InterpretMediaRequest(
            tenant_id="t1",
            media=pb.MediaRef(
                url="https://r2.example/img.jpg", mimetype="image/jpeg"
            ),
            media_type="imageMessage",
        )
    )
    assert resp.analise == "Descrição completa da mídia."
    assert resp.resumo == "Resumo curto da mídia."


@pytest.mark.asyncio
async def test_analyse_roundtrip(ia_stub):
    resp = await ia_stub.Analyse(
        pb.AnalyseRequest(
            tenant_id="t1",
            mensagem="Olá, meu nome é Ana",
            historico=pb.ChatHistory(
                turnos=[pb.ChatTurn(role="human", conteudo="oi")]
            ),
            valid_intent_types="saudacao,duvida",
            valid_entity_types=["nome_contato"],
        )
    )
    assert [i.tipo for i in resp.intents] == ["saudacao"]
    assert resp.intents[0].confianca == pytest.approx(0.95)
    assert resp.entidades[0].tipo == "nome_contato"
    assert resp.entidades[0].valor == "Ana"


@pytest.mark.asyncio
async def test_embed_roundtrip(ia_stub):
    resp = await ia_stub.Embed(
        pb.EmbedRequest(
            tenant_id="t1",
            textos=["texto um", "texto dois"],
        )
    )
    assert len(resp.embeddings) == 2
    assert len(resp.embeddings[0].valores) == 1536


@pytest.mark.asyncio
async def test_responder_roundtrip(ia_stub):
    resp = await ia_stub.Responder(
        pb.ResponderRequest(
            tenant_id="t1",
            atendimento_id="a1",
            mensagem="Qual o horário de funcionamento?",
            historico=pb.ChatHistory(
                turnos=[pb.ChatTurn(role="human", conteudo="oi")]
            ),
            fluxos_disponiveis=[
                pb.KeyValuePair(key="Financeiro - cobranças", value="setor")
            ],
            dados_treinamento="Funcionamos das 8h às 18h.",
        )
    )
    assert resp.resposta_texto  # veio do RespostaBot fake
    assert isinstance(resp.transferir_atendimento, bool)
    assert 0.0 <= resp.confiabilidade <= 1.0


@pytest.mark.asyncio
async def test_sentimento_roundtrip(ia_stub):
    resp = await ia_stub.Sentimento(
        pb.SentimentoRequest(
            tenant_id="t1",
            historico=pb.ChatHistory(
                turnos=[pb.ChatTurn(role="human", conteudo="Adorei o atendimento!")]
            ),
        )
    )
    assert resp.nota == 5
    assert resp.sentimento == "positivo"


@pytest.mark.asyncio
async def test_invalid_request_aborts_with_invalid_argument(ia_stub):
    import grpc

    with pytest.raises(grpc.aio.AioRpcError) as exc_info:
        await ia_stub.Responder(
            pb.ResponderRequest(
                tenant_id="t1",
                mensagem="",  # obrigatório ausente
            )
        )
    assert exc_info.value.code() == grpc.StatusCode.INVALID_ARGUMENT


@pytest.mark.asyncio
async def test_api_key_nunca_aparece_em_logs(
    fake_chat_factory, fake_embeddings_factory
):
    """A api_key resolvida do tenant não pode vazar em nenhum log estruturado.

    A chave deixou de vir no request e passou a vir da config publicada no
    Redis — o risco de vazamento acompanhou. Cobre os dois caminhos críticos:
    o de SUCESSO e o de ERRO (`servicer._abort`, que loga tipo/mensagem em
    WARNING), que é onde um segredo costuma escapar.
    """
    import grpc

    from ia_engine.contracts import ai_engine_pb2_grpc as pbg
    from ia_engine.servicer import IaEngineServicer
    from tests.conftest import FakeConfigCache, runtime_config

    sentinela = "SUPER_SECRET_API_KEY_12345"

    # Registra a chave que chegou às fábricas: sem isto o teste passaria mesmo
    # que a sentinela nunca atravessasse o sistema — um assert de "não vazou"
    # sobre um segredo que não circula não prova nada.
    chaves_vistas: list[str] = []

    def _chat_factory_espiao(spec):
        chaves_vistas.append(spec.api_key)
        return fake_chat_factory(spec)

    servicer = IaEngineServicer(
        chat_model_factory=_chat_factory_espiao,
        embeddings_factory=fake_embeddings_factory,
        config_cache=FakeConfigCache(
            runtime_config(
                openai_api_key=sentinela,
                groq_api_key=sentinela,
                google_api_key=sentinela,
            )
        ),
    )

    server = grpc.aio.server()
    pbg.add_IaEngineServiceServicer_to_server(servicer, server)
    porta = server.add_insecure_port("127.0.0.1:0")
    await server.start()

    captured: list[str] = []
    sink_id = loguru.logger.add(lambda msg: captured.append(str(msg)), level="DEBUG")
    try:
        async with grpc.aio.insecure_channel(f"127.0.0.1:{porta}") as canal:
            stub = pbg.IaEngineServiceStub(canal)
            # Caminho de sucesso.
            await stub.Responder(
                pb.ResponderRequest(
                    tenant_id="t1", mensagem="Olá", dados_treinamento=""
                )
            )
            # Caminho de erro: obrigatório ausente -> `_abort` loga em WARNING.
            with pytest.raises(grpc.aio.AioRpcError):
                await stub.Responder(
                    pb.ResponderRequest(tenant_id="t1", mensagem="")
                )
    finally:
        loguru.logger.remove(sink_id)
        await server.stop(None)

    assert sentinela in chaves_vistas, "a chave nem chegou ao fluxo: teste inócuo"
    assert captured  # garante que houve log capturado (caminho de erro logou)
    assert all(sentinela not in line for line in captured)
