"""Roundtrip dos 6 RPCs contra um grpc.aio.server real (LLM/embeddings fakes)."""

from __future__ import annotations

import loguru
import pytest

from ia_engine.contracts import ai_engine_pb2 as pb


@pytest.mark.asyncio
async def test_transcribe_roundtrip(ia_stub, secret_config):
    resp = await ia_stub.Transcribe(
        pb.TranscribeRequest(
            tenant_id="t1",
            media=pb.MediaRef(url="https://r2.example/audio.ogg", mimetype="audio/ogg"),
            language="pt",
            transcription_provider=secret_config,
        )
    )
    assert resp.transcricao == "transcrição fake do áudio"
    assert resp.resumo  # resumo gerado pelo chat fake


@pytest.mark.asyncio
async def test_interpret_media_roundtrip(ia_stub, secret_config):
    resp = await ia_stub.InterpretMedia(
        pb.InterpretMediaRequest(
            tenant_id="t1",
            media=pb.MediaRef(
                url="https://r2.example/img.jpg", mimetype="image/jpeg"
            ),
            media_type="imageMessage",
            vision_provider=secret_config,
        )
    )
    assert resp.analise == "Descrição completa da mídia."
    assert resp.resumo == "Resumo curto da mídia."


@pytest.mark.asyncio
async def test_analyse_roundtrip(ia_stub, secret_config):
    resp = await ia_stub.Analyse(
        pb.AnalyseRequest(
            tenant_id="t1",
            mensagem="Olá, meu nome é Ana",
            historico=pb.ChatHistory(
                turnos=[pb.ChatTurn(role="human", conteudo="oi")]
            ),
            valid_intent_types="saudacao,duvida",
            valid_entity_types=["nome_contato"],
            llm=secret_config,
        )
    )
    assert [i.tipo for i in resp.intents] == ["saudacao"]
    assert resp.intents[0].confianca == pytest.approx(0.95)
    assert resp.entidades[0].tipo == "nome_contato"
    assert resp.entidades[0].valor == "Ana"


@pytest.mark.asyncio
async def test_embed_roundtrip(ia_stub, secret_config):
    resp = await ia_stub.Embed(
        pb.EmbedRequest(
            tenant_id="t1",
            textos=["texto um", "texto dois"],
            embeddings_provider=secret_config,
        )
    )
    assert len(resp.embeddings) == 2
    assert len(resp.embeddings[0].valores) == 1536


@pytest.mark.asyncio
async def test_responder_roundtrip(ia_stub, secret_config):
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
            dados_empresa="Empresa X",
            dados_treinamento="Funcionamos das 8h às 18h.",
            llm=secret_config,
            embeddings_provider=secret_config,
            similarity_threshold=0.5,
        )
    )
    assert resp.resposta_texto  # veio do RespostaBot fake
    assert isinstance(resp.transferir_atendimento, bool)
    assert 0.0 <= resp.confiabilidade <= 1.0


@pytest.mark.asyncio
async def test_sentimento_roundtrip(ia_stub, secret_config):
    resp = await ia_stub.Sentimento(
        pb.SentimentoRequest(
            tenant_id="t1",
            historico=pb.ChatHistory(
                turnos=[pb.ChatTurn(role="human", conteudo="Adorei o atendimento!")]
            ),
            llm=secret_config,
        )
    )
    assert resp.nota == 5
    assert resp.sentimento == "positivo"


@pytest.mark.asyncio
async def test_invalid_request_aborts_with_invalid_argument(ia_stub, secret_config):
    import grpc

    with pytest.raises(grpc.aio.AioRpcError) as exc_info:
        await ia_stub.Responder(
            pb.ResponderRequest(
                tenant_id="t1",
                mensagem="",  # obrigatório ausente
                llm=secret_config,
                embeddings_provider=secret_config,
                similarity_threshold=0.5,
            )
        )
    assert exc_info.value.code() == grpc.StatusCode.INVALID_ARGUMENT


@pytest.mark.asyncio
async def test_api_key_nunca_aparece_em_logs(ia_stub, secret_config):
    """A api_key do request não pode vazar em nenhum log estruturado.

    Cobre os dois caminhos críticos com a api_key presente no request:
    o de SUCESSO e o de ERRO (`servicer._abort`, que loga tipo/mensagem da
    exceção em WARNING) — é justamente no caminho de erro que um vazamento de
    segredo costuma aparecer.
    """
    import grpc

    captured: list[str] = []
    sink_id = loguru.logger.add(lambda msg: captured.append(str(msg)), level="DEBUG")
    try:
        # Caminho de sucesso.
        await ia_stub.Responder(
            pb.ResponderRequest(
                tenant_id="t1",
                mensagem="Olá",
                dados_treinamento="",
                llm=secret_config,
                embeddings_provider=secret_config,
                similarity_threshold=0.5,
            )
        )
        # Caminho de erro: request inválido dispara `_abort` -> WARNING logado.
        with pytest.raises(grpc.aio.AioRpcError):
            await ia_stub.Responder(
                pb.ResponderRequest(
                    tenant_id="t1",
                    mensagem="",  # obrigatório ausente -> InvalidRequestError
                    llm=secret_config,
                    embeddings_provider=secret_config,
                    similarity_threshold=0.5,
                )
            )
    finally:
        loguru.logger.remove(sink_id)

    assert captured  # garante que houve log capturado (caminho de erro logou)
    assert all("SUPER_SECRET_API_KEY_12345" not in line for line in captured)
