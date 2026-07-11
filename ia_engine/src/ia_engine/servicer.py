"""Camada fina gRPC: valida request, delega às features, converte para proto.

Mapeia exceções de domínio para `grpc.StatusCode`. Nunca loga `api_key`.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import NoReturn

import grpc
from loguru import logger

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.domain.errors import (
    IaEngineError,
    InvalidRequestError,
    MediaDownloadError,
    ProviderConfigError,
)
from ia_engine.features import (
    analyse as analyse_feature,
)
from ia_engine.features import (
    embed as embed_feature,
)
from ia_engine.features import (
    interpret_media as interpret_media_feature,
)
from ia_engine.features import (
    responder as responder_feature,
)
from ia_engine.features import (
    sentimento as sentimento_feature,
)
from ia_engine.features import (
    transcribe as transcribe_feature,
)
from ia_engine.features._history import ChatTurnTuple
from ia_engine.features.transcribe import AudioTranscriber, PendingTranscriber
from ia_engine.llm.embeddings_factory import build_embeddings
from ia_engine.llm.provider_factory import build_chat_model

ChatModelFactory = Callable[[pb.LlmProviderConfig], object]
EmbeddingsFactory = Callable[[pb.LlmProviderConfig], object]
TranscriberFactory = Callable[[pb.LlmProviderConfig], AudioTranscriber]


def _default_transcriber_factory(
    _config: pb.LlmProviderConfig,
) -> AudioTranscriber:
    return PendingTranscriber()


class IaEngineServicer(pbg.IaEngineServiceServicer):
    """Implementação do serviço gRPC IaEngineService."""

    def __init__(
        self,
        *,
        chat_model_factory: ChatModelFactory = build_chat_model,
        embeddings_factory: EmbeddingsFactory = build_embeddings,
        transcriber_factory: TranscriberFactory = _default_transcriber_factory,
    ) -> None:
        self._chat_model_factory = chat_model_factory
        self._embeddings_factory = embeddings_factory
        self._transcriber_factory = transcriber_factory

    # ---------------------------------------------------------------- RPCs
    async def Transcribe(
        self, request: pb.TranscribeRequest, context: grpc.aio.ServicerContext
    ) -> pb.TranscribeResponse:
        try:
            _require(request.media.url, "media.url")
            transcriber = self._transcriber_factory(request.transcription_provider)
            summarizer = self._chat_model(request.transcription_provider)
            result = await transcribe_feature.transcribe(
                url=request.media.url,
                mimetype=request.media.mimetype,
                language=request.language,
                transcriber=transcriber,
                summarizer_model=summarizer,  # type: ignore[arg-type]
            )
            return pb.TranscribeResponse(
                transcricao=result.analise, resumo=result.resumo
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "Transcribe", request.tenant_id)

    async def InterpretMedia(
        self,
        request: pb.InterpretMediaRequest,
        context: grpc.aio.ServicerContext,
    ) -> pb.InterpretMediaResponse:
        try:
            _require(request.media.url, "media.url")
            vision = self._chat_model(request.vision_provider)
            result = await interpret_media_feature.interpret_media(
                url=request.media.url,
                mimetype=request.media.mimetype,
                media_type=request.media_type,
                file_name=request.media.file_name,
                vision_model=vision,  # type: ignore[arg-type]
            )
            return pb.InterpretMediaResponse(
                analise=result.analise, resumo=result.resumo
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "InterpretMedia", request.tenant_id)

    async def Analyse(
        self, request: pb.AnalyseRequest, context: grpc.aio.ServicerContext
    ) -> pb.AnalyseResponse:
        try:
            _require(request.mensagem, "mensagem")
            llm = self._chat_model(request.llm)
            result = await analyse_feature.analyse(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                valid_intent_types=request.valid_intent_types,
                valid_entity_types=list(request.valid_entity_types),
                llm=llm,  # type: ignore[arg-type]
            )
            return pb.AnalyseResponse(
                intents=[
                    pb.Intent(tipo=i.tipo, confianca=i.confianca)
                    for i in result.intents
                ],
                entidades=[
                    pb.Entidade(
                        tipo=e.tipo, valor=e.valor, confianca=e.confianca
                    )
                    for e in result.entidades
                ],
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "Analyse", request.tenant_id)

    async def Embed(
        self, request: pb.EmbedRequest, context: grpc.aio.ServicerContext
    ) -> pb.EmbedResponse:
        try:
            embeddings = self._embeddings(request.embeddings_provider)
            vectors = await embed_feature.embed(
                textos=list(request.textos),
                embeddings=embeddings,  # type: ignore[arg-type]
            )
            return pb.EmbedResponse(
                embeddings=[pb.Embedding(valores=v) for v in vectors]
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "Embed", request.tenant_id)

    async def Responder(
        self, request: pb.ResponderRequest, context: grpc.aio.ServicerContext
    ) -> pb.ResponderResponse:
        try:
            _require(request.mensagem, "mensagem")
            llm = self._chat_model(request.llm)
            embeddings = self._embeddings(request.embeddings_provider)
            result = await responder_feature.responder(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                fluxos_disponiveis=_kv_to_dict(request.fluxos_disponiveis),
                dados_empresa=request.dados_empresa,
                dados_treinamento=request.dados_treinamento,
                campos_coletados=[
                    {"slug": c.slug, "nome": c.nome, "valor": c.valor}
                    for c in request.campos_coletados
                ],
                campos_pendentes=[
                    {
                        "slug": c.slug,
                        "nome": c.nome,
                        "descricao": c.descricao,
                        "hint": c.hint,
                    }
                    for c in request.campos_pendentes
                ],
                similarity_threshold=request.similarity_threshold,
                llm=llm,  # type: ignore[arg-type]
                embeddings=embeddings,  # type: ignore[arg-type]
            )
            return pb.ResponderResponse(
                resposta_texto=result.resposta_texto,
                transferir_atendimento=result.transferir_atendimento,
                fluxo_transferencia=result.fluxo_transferencia,
                confiabilidade=result.confiabilidade,
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "Responder", request.tenant_id)

    async def Sentimento(
        self, request: pb.SentimentoRequest, context: grpc.aio.ServicerContext
    ) -> pb.SentimentoResponse:
        try:
            llm = self._chat_model(request.llm)
            result = await sentimento_feature.sentimento(
                historico=_history(request.historico),
                llm=llm,  # type: ignore[arg-type]
            )
            return pb.SentimentoResponse(
                nota=result.nota,
                sentimento=result.sentimento,
                feedback=result.feedback or "",
            )
        except Exception as exc:  # noqa: BLE001
            await self._abort(context, exc, "Sentimento", request.tenant_id)

    # ------------------------------------------------------------- helpers
    def _chat_model(self, config: pb.LlmProviderConfig) -> object:
        return self._chat_model_factory(config)

    def _embeddings(self, config: pb.LlmProviderConfig) -> object:
        return self._embeddings_factory(config)

    async def _abort(
        self,
        context: grpc.aio.ServicerContext,
        exc: BaseException,
        rpc: str,
        tenant_id: str,
    ) -> NoReturn:
        code = _status_for(exc)
        # Log sem segredos: tipo/mensagem de domínio, rpc e tenant apenas.
        logger.warning(
            "RPC {} falhou (tenant={}): {}: {}",
            rpc,
            tenant_id,
            type(exc).__name__,
            exc,
        )
        detail = (
            str(exc)
            if isinstance(exc, IaEngineError)
            else "erro interno no ia_engine"
        )
        await context.abort(code, detail)
        # `context.abort` sempre levanta; defensivo para garantir NoReturn.
        raise IaEngineError(detail)


def _status_for(exc: BaseException) -> grpc.StatusCode:
    if isinstance(exc, (ProviderConfigError, InvalidRequestError)):
        return grpc.StatusCode.INVALID_ARGUMENT
    if isinstance(exc, MediaDownloadError):
        return grpc.StatusCode.FAILED_PRECONDITION
    return grpc.StatusCode.INTERNAL


def _require(value: str, field: str) -> None:
    if not (value or "").strip():
        raise InvalidRequestError(f"campo obrigatório ausente: {field}")


def _history(historico: pb.ChatHistory) -> list[ChatTurnTuple]:
    return [(t.role, t.conteudo) for t in historico.turnos]


def _kv_to_dict(pairs: object) -> dict[str, str]:
    return {kv.key: kv.value for kv in pairs}  # type: ignore[attr-defined]
