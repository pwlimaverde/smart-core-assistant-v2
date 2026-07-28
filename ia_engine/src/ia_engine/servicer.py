"""Camada fina gRPC: valida request, compõe e executa usecases, converte proto.

Ponto de composição das features (padrão py-return-success-or-error): cada RPC
monta `DataSource → Repository → Usecase` com as fábricas injetadas e consome o
resultado com `match Success/Failure` — os erros de domínio (`AppError`) são
mapeados para `grpc.StatusCode`. Nunca loga `api_key`.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import NoReturn, assert_never

import grpc
from langchain_core.embeddings import Embeddings
from langchain_core.language_models.chat_models import BaseChatModel
from loguru import logger
from py_return_success_or_error import (
    AppError,
    ErrorGeneric,
    Failure,
    Success,
)

from ia_engine.config import (
    ConfigIndisponivelError,
    RuntimeConfig,
    TenantConfigCache,
)
from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.domain.errors import (
    ConfigTenantAusenteError,
    InvalidRequestError,
    MediaDownloadError,
    ProviderConfigError,
)
from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.analyse import (
    AnalyseDataSource,
    AnalyseParameters,
    AnalyseRepository,
    AnalyseUsecase,
)
from ia_engine.features.embed import (
    EmbedDataSource,
    EmbedParameters,
    EmbedRepository,
    EmbedUsecase,
)
from ia_engine.features.interpret_media import (
    InterpretMediaDataSource,
    InterpretMediaParameters,
    InterpretMediaRepository,
    InterpretMediaUsecase,
)
from ia_engine.features.responder import (
    CampoColetado,
    CampoPendente,
    ResponderDataSource,
    ResponderParameters,
    ResponderRepository,
    ResponderUsecase,
)
from ia_engine.features.sentimento import (
    SentimentoDataSource,
    SentimentoParameters,
    SentimentoRepository,
    SentimentoUsecase,
)
from ia_engine.features.transcribe import (
    AudioTranscriber,
    TranscribeDataSource,
    TranscribeParameters,
    TranscribeRepository,
    TranscribeUsecase,
    build_transcriber,
)
from ia_engine.llm.embeddings_factory import build_embeddings
from ia_engine.llm.provider_factory import build_chat_model
from ia_engine.shared.history import ChatTurnTuple

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]
EmbeddingsFactory = Callable[[LlmProviderSpec], Embeddings]
TranscriberFactory = Callable[[LlmProviderSpec], AudioTranscriber]


class IaEngineServicer(pbg.IaEngineServiceServicer):
    """Implementação do serviço gRPC IaEngineService."""

    def __init__(
        self,
        *,
        chat_model_factory: ChatModelFactory = build_chat_model,
        embeddings_factory: EmbeddingsFactory = build_embeddings,
        transcriber_factory: TranscriberFactory = build_transcriber,
        transcription_enabled: bool = False,
        config_cache: TenantConfigCache | None = None,
    ) -> None:
        self._chat_model_factory = chat_model_factory
        self._embeddings_factory = embeddings_factory
        self._transcriber_factory = transcriber_factory
        self._transcription_enabled = transcription_enabled
        self._config_cache = config_cache

    # ---------------------------------------------------------------- RPCs
    async def Transcribe(
        self, request: pb.TranscribeRequest, context: grpc.aio.ServicerContext
    ) -> pb.TranscribeResponse:
        await self._require(
            context, request.media.url, "media.url", "Transcribe", request.tenant_id
        )
        config = await self._config(context, "Transcribe", request.tenant_id)
        # Kill-switch por tenant (config) OU global do processo (env): qualquer
        # um desligado curto-circuita. O do tenant é decidido pelo worker antes
        # de chamar, mas repetir aqui evita gasto se alguém chamar direto.
        if not self._transcription_enabled or not config.transcription_enabled:
            # Kill-switch global off: transcrição desligada por custo/latência.
            # Curto-circuita graciosamente (resposta vazia, sem erro).
            return pb.TranscribeResponse(transcricao="", resumo="")
        usecase = TranscribeUsecase(
            TranscribeRepository(
                TranscribeDataSource(
                    transcriber_factory=self._transcriber_factory,
                    chat_model_factory=self._chat_model_factory,
                )
            )
        )
        result = await usecase(
            TranscribeParameters(
                url=request.media.url,
                mimetype=request.media.mimetype,
                language=request.language,
                transcription_provider=config.spec_transcription(),
            )
        )
        match result:
            case Success(analysis):
                return pb.TranscribeResponse(
                    transcricao=analysis.analise, resumo=analysis.resumo
                )
            case Failure(error):
                await self._abort(context, error, "Transcribe", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def InterpretMedia(
        self,
        request: pb.InterpretMediaRequest,
        context: grpc.aio.ServicerContext,
    ) -> pb.InterpretMediaResponse:
        await self._require(
            context,
            request.media.url,
            "media.url",
            "InterpretMedia",
            request.tenant_id,
        )
        config = await self._config(context, "InterpretMedia", request.tenant_id)
        usecase = InterpretMediaUsecase(
            InterpretMediaRepository(
                InterpretMediaDataSource(
                    chat_model_factory=self._chat_model_factory
                )
            )
        )
        result = await usecase(
            InterpretMediaParameters(
                url=request.media.url,
                mimetype=request.media.mimetype,
                media_type=request.media_type,
                file_name=request.media.file_name,
                vision_provider=config.spec_vision(),
                prompts=dict(config.prompts),
            )
        )
        match result:
            case Success(analysis):
                return pb.InterpretMediaResponse(
                    analise=analysis.analise, resumo=analysis.resumo
                )
            case Failure(error):
                await self._abort(
                    context, error, "InterpretMedia", request.tenant_id
                )
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def Analyse(
        self, request: pb.AnalyseRequest, context: grpc.aio.ServicerContext
    ) -> pb.AnalyseResponse:
        await self._require(
            context, request.mensagem, "mensagem", "Analyse", request.tenant_id
        )
        config = await self._config(context, "Analyse", request.tenant_id)
        usecase = AnalyseUsecase(
            AnalyseRepository(
                AnalyseDataSource(chat_model_factory=self._chat_model_factory)
            )
        )
        result = await usecase(
            AnalyseParameters(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                valid_intent_types=request.valid_intent_types,
                valid_entity_types=tuple(request.valid_entity_types),
                llm=config.spec_llm(),
                prompts=dict(config.prompts),
            )
        )
        match result:
            case Success(analise):
                return pb.AnalyseResponse(
                    intents=[
                        pb.Intent(tipo=i.tipo, confianca=i.confianca)
                        for i in analise.intents
                    ],
                    entidades=[
                        pb.Entidade(
                            tipo=e.tipo, valor=e.valor, confianca=e.confianca
                        )
                        for e in analise.entidades
                    ],
                )
            case Failure(error):
                await self._abort(context, error, "Analyse", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def Embed(
        self, request: pb.EmbedRequest, context: grpc.aio.ServicerContext
    ) -> pb.EmbedResponse:
        if not list(request.textos):
            await self._abort(
                context,
                InvalidRequestError(
                    message="nenhum texto informado para embeddings"
                ),
                "Embed",
                request.tenant_id,
            )
        config = await self._config(context, "Embed", request.tenant_id)
        usecase = EmbedUsecase(
            EmbedRepository(
                EmbedDataSource(embeddings_factory=self._embeddings_factory)
            )
        )
        result = await usecase(
            EmbedParameters(
                textos=tuple(request.textos),
                embeddings_provider=config.spec_embeddings(),
            )
        )
        match result:
            case Success(vectors):
                return pb.EmbedResponse(
                    embeddings=[pb.Embedding(valores=v) for v in vectors]
                )
            case Failure(error):
                await self._abort(context, error, "Embed", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def Responder(
        self, request: pb.ResponderRequest, context: grpc.aio.ServicerContext
    ) -> pb.ResponderResponse:
        await self._require(
            context, request.mensagem, "mensagem", "Responder", request.tenant_id
        )
        config = await self._config(context, "Responder", request.tenant_id)
        usecase = ResponderUsecase(
            ResponderRepository(
                ResponderDataSource(
                    chat_model_factory=self._chat_model_factory,
                    embeddings_factory=self._embeddings_factory,
                )
            )
        )
        result = await usecase(
            ResponderParameters(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                fluxos_disponiveis=tuple(
                    (kv.key, kv.value) for kv in request.fluxos_disponiveis
                ),
                dados_empresa=config.dados_empresa,
                persona_bot=config.persona_bot,
                bot_agent_name=config.bot_agent_name,
                msg_transferencia=config.msg_transferencia,
                dados_treinamento=request.dados_treinamento,
                similarity_threshold=config.similarity_threshold,
                llm=config.spec_llm(),
                embeddings_provider=config.spec_embeddings(),
                prompts=dict(config.prompts),
                campos_coletados=tuple(
                    CampoColetado(slug=c.slug, nome=c.nome, valor=c.valor)
                    for c in request.campos_coletados
                ),
                campos_pendentes=tuple(
                    CampoPendente(
                        slug=c.slug,
                        nome=c.nome,
                        descricao=c.descricao,
                        hint=c.hint,
                    )
                    for c in request.campos_pendentes
                ),
            )
        )
        match result:
            case Success(final):
                return pb.ResponderResponse(
                    resposta_texto=final.resposta_texto,
                    transferir_atendimento=final.transferir_atendimento,
                    fluxo_transferencia=final.fluxo_transferencia,
                    confiabilidade=final.confiabilidade,
                )
            case Failure(error):
                await self._abort(context, error, "Responder", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def Sentimento(
        self, request: pb.SentimentoRequest, context: grpc.aio.ServicerContext
    ) -> pb.SentimentoResponse:
        # Sem histórico não há resposta do cliente para avaliar: o prompt iria
        # ao LLM com `chat_history` vazio e voltaria uma nota inventada. Falha
        # cedo, como `Embed` faz com `textos` vazio.
        if not list(request.historico.turnos):
            await self._abort(
                context,
                InvalidRequestError(
                    message="histórico vazio: nada a avaliar"
                ),
                "Sentimento",
                request.tenant_id,
            )
        config = await self._config(context, "Sentimento", request.tenant_id)
        usecase = SentimentoUsecase(
            SentimentoRepository(
                SentimentoDataSource(
                    chat_model_factory=self._chat_model_factory
                )
            )
        )
        result = await usecase(
            SentimentoParameters(
                historico=_history(request.historico),
                llm=config.spec_llm(),
                prompts=dict(config.prompts),
            )
        )
        match result:
            case Success(avaliacao):
                return pb.SentimentoResponse(
                    nota=avaliacao.nota,
                    sentimento=avaliacao.sentimento,
                    feedback=avaliacao.feedback or "",
                )
            case Failure(error):
                await self._abort(context, error, "Sentimento", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    # ------------------------------------------------------------- helpers
    async def _config(
        self, context: grpc.aio.ServicerContext, rpc: str, tenant_id: str
    ) -> RuntimeConfig:
        """Config do tenant, publicada pelo Rust no Redis.

        Aborta o RPC quando não há config: chamar o LLM sem chave gastaria uma
        requisição para falhar com erro do provedor, mascarando o que é um
        problema de provisionamento (`data_postgres` fora do ar, ou tenant novo
        que ainda não passou pelo pre-warm).
        """
        if self._config_cache is None:
            await self._abort(
                context,
                ProviderConfigError(
                    message="ia_engine sem cache de config (Redis não configurado)"
                ),
                rpc,
                tenant_id,
            )
        if not (tenant_id or "").strip():
            await self._abort(
                context,
                InvalidRequestError(message="campo obrigatório ausente: tenant_id"),
                rpc,
                tenant_id,
            )
        try:
            return await self._config_cache.get_config(tenant_id)
        except ConfigIndisponivelError as exc:
            await self._abort(
                context, ConfigTenantAusenteError(message=str(exc)), rpc, tenant_id
            )

    async def _require(
        self,
        context: grpc.aio.ServicerContext,
        value: str,
        field: str,
        rpc: str,
        tenant_id: str,
    ) -> None:
        """Validação de transporte: campo obrigatório ausente aborta o RPC."""
        if not (value or "").strip():
            await self._abort(
                context,
                InvalidRequestError(
                    message=f"campo obrigatório ausente: {field}"
                ),
                rpc,
                tenant_id,
            )

    async def _abort(
        self,
        context: grpc.aio.ServicerContext,
        error: AppError,
        rpc: str,
        tenant_id: str,
    ) -> NoReturn:
        code = _status_for(error)
        # Log sem segredos: tipo/mensagem do erro de domínio, rpc e tenant.
        logger.warning(
            "RPC {} falhou (tenant={}): {}: {}",
            rpc,
            tenant_id,
            type(error).__name__,
            error.message,
        )
        # `ErrorGeneric` embute a exceção inesperada original — não expor ao
        # cliente; os demais casos carregam mensagem de domínio sanitizada.
        detail = (
            "erro interno no ia_engine"
            if isinstance(error, ErrorGeneric)
            else error.message
        )
        await context.abort(code, detail)
        # `context.abort` sempre levanta; defensivo para garantir NoReturn.
        raise RuntimeError(detail)


def _status_for(error: AppError) -> grpc.StatusCode:
    match error:
        case ProviderConfigError() | InvalidRequestError():
            return grpc.StatusCode.INVALID_ARGUMENT
        case MediaDownloadError() | ConfigTenantAusenteError():
            return grpc.StatusCode.FAILED_PRECONDITION
        case _:
            return grpc.StatusCode.INTERNAL


def _history(historico: pb.ChatHistory) -> tuple[ChatTurnTuple, ...]:
    return tuple((t.role, t.conteudo) for t in historico.turnos)
