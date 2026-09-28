"""Camada fina gRPC: valida request, compõe e executa usecases, converte proto.

Ponto de composição das features (padrão py-return-success-or-error): cada RPC
monta `DataSource → Repository → Usecase` com as fábricas injetadas e consome o
resultado com `match Success/Failure` — os erros de domínio (`AppError`) são
mapeados para `grpc.StatusCode`. Nunca loga `api_key`.
"""

from __future__ import annotations

import json
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

from ia_engine_jev.config import (
    ConfigIndisponivelError,
    RuntimeConfig,
    TenantConfigCache,
)
from ia_engine_jev.contracts import ai_engine_pb2 as pb
from ia_engine_jev.contracts import ai_engine_pb2_grpc as pbg
from ia_engine_jev.conversao import (
    entidades_da_config,
    fluxos_do_proto,
    intents_do_proto,
    trechos_do_proto,
    usa_jev,
)
from ia_engine_jev.decisoes.limiares import limiares_de, sinais_de
from ia_engine_jev.domain.errors import (
    ConfigTenantAusenteError,
    InvalidRequestError,
    JevIndisponivelError,
    JevNaoConfiguradoError,
    JevPerguntaInvalidaError,
    MediaDownloadError,
    ProviderConfigError,
)
from ia_engine_jev.domain.models import LlmProviderSpec
from ia_engine_jev.features.analise_jev import (
    AnaliseJevDataSource,
    AnaliseJevParameters,
    AnaliseJevRepository,
    AnaliseJevUsecase,
)
from ia_engine_jev.features.analyse import (
    AnalyseDataSource,
    AnalyseParameters,
    AnalyseRepository,
    AnalyseUsecase,
)
from ia_engine_jev.features.embed import (
    EmbedDataSource,
    EmbedParameters,
    EmbedRepository,
    EmbedUsecase,
)
from ia_engine_jev.features.extrair_texto import (
    DocumentoIlegivelError,
    ExtrairTextoDataSource,
    ExtrairTextoParameters,
    ExtrairTextoRepository,
    ExtrairTextoUsecase,
    FormatoNaoSuportadoError,
    TextoVazioError,
)
from ia_engine_jev.features.interpret_media import (
    InterpretMediaDataSource,
    InterpretMediaParameters,
    InterpretMediaRepository,
    InterpretMediaUsecase,
)
from ia_engine_jev.features.responder import (
    CampoColetado,
    CampoPendente,
    ResponderDataSource,
    ResponderParameters,
    ResponderRepository,
    ResponderUsecase,
)
from ia_engine_jev.features.responder_jev import (
    ResponderJevDataSource,
    ResponderJevParameters,
    ResponderJevRepository,
    ResponderJevUsecase,
)
from ia_engine_jev.features.sentimento import (
    SentimentoDataSource,
    SentimentoParameters,
    SentimentoRepository,
    SentimentoUsecase,
)
from ia_engine_jev.features.sentimento_jev import (
    SentimentoJevDataSource,
    SentimentoJevParameters,
    SentimentoJevRepository,
    SentimentoJevUsecase,
)
from ia_engine_jev.features.testar_regra import (
    ProvaDeRegraDataSource,
    ProvaDeRegraParameters,
    ProvaDeRegraRepository,
    ProvaDeRegraUsecase,
)
from ia_engine_jev.features.transcribe import (
    AudioTranscriber,
    TranscribeDataSource,
    TranscribeParameters,
    TranscribeRepository,
    TranscribeUsecase,
    build_transcriber,
)
from ia_engine_jev.llm.embeddings_factory import build_embeddings
from ia_engine_jev.llm.provider_factory import build_chat_model
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.telemetry import (
    contar_reserva,
    contar_transferencia,
    observar_rpc,
)
from ia_engine_jev.typesafe import ClienteJev, FabricaJev, JevNaoConfigurado

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]
EmbeddingsFactory = Callable[[LlmProviderSpec], Embeddings]
TranscriberFactory = Callable[[LlmProviderSpec], AudioTranscriber]
JevFactory = Callable[[str, str], ClienteJev]


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
        jev_factory: JevFactory | None = None,
    ) -> None:
        self._chat_model_factory = chat_model_factory
        self._embeddings_factory = embeddings_factory
        self._transcriber_factory = transcriber_factory
        self._transcription_enabled = transcription_enabled
        self._config_cache = config_cache
        self._jev_factory: JevFactory = jev_factory or FabricaJev()

    def _jev(self, config: RuntimeConfig) -> ClienteJev:
        return self._jev_factory(config.typesafe_api_key, config.jev_modelo)

    # ---------------------------------------------------------------- RPCs
    @observar_rpc("Transcribe", "ia.transcrever")
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

    @observar_rpc("InterpretMedia", "ia.interpretar_midia")
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
                InterpretMediaDataSource(chat_model_factory=self._chat_model_factory)
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
                await self._abort(context, error, "InterpretMedia", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    @observar_rpc("Analyse", "ia.analisar")
    async def Analyse(
        self, request: pb.AnalyseRequest, context: grpc.aio.ServicerContext
    ) -> pb.AnalyseResponse:
        await self._require(
            context, request.mensagem, "mensagem", "Analyse", request.tenant_id
        )
        config = await self._config(context, "Analyse", request.tenant_id)
        if usa_jev(config) and (
            list(request.intents) or config.entity_descricoes or list(request.entidades)
        ):
            return await self._analyse_jev(request, context, config)
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
                        pb.Entidade(tipo=e.tipo, valor=e.valor, confianca=e.confianca)
                        for e in analise.entidades
                    ],
                    motor="llm",
                )
            case Failure(error):
                await self._abort(context, error, "Analyse", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def _analyse_jev(
        self,
        request: pb.AnalyseRequest,
        context: grpc.aio.ServicerContext,
        config: RuntimeConfig,
    ) -> pb.AnalyseResponse:
        """Análise pelo Jev. Falha = mensagem sem análise, como no motor atual."""
        try:
            jev = self._jev(config)
        except JevNaoConfigurado as exc:
            await self._abort(
                context,
                JevNaoConfiguradoError(message=str(exc)),
                "Analyse",
                request.tenant_id,
            )
        usecase = AnaliseJevUsecase(
            AnaliseJevRepository(
                AnaliseJevDataSource(chat_model_factory=self._chat_model_factory)
            )
        )
        result = await usecase(
            AnaliseJevParameters(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                intents=intents_do_proto(request.intents),
                entidades=entidades_da_config(config, request.entidades),
                jev=jev,
                llm=config.spec_llm(),
                limiares=limiares_de(config.jev_config),
                dados_empresa=config.dados_empresa,
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
                        pb.Entidade(tipo=e.tipo, valor=e.valor, confianca=e.confianca)
                        for e in analise.entidades
                    ],
                    intent_principal=analise.intent_principal,
                    confianca_principal=analise.confianca_principal,
                    intents_a_revisar=list(analise.intents_a_revisar),
                    motor="jev",
                    modelo=analise.modelo,
                    uso=pb.UsoDoMotor(
                        tokens_entrada=analise.tokens_entrada,
                        requisicoes=analise.requisicoes,
                        duracao_ms=analise.duracao_ms,
                    ),
                )
            case Failure(error):
                await self._abort(context, error, "Analyse", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    @observar_rpc("Embed", "ia.rag.embed")
    async def Embed(
        self, request: pb.EmbedRequest, context: grpc.aio.ServicerContext
    ) -> pb.EmbedResponse:
        if not list(request.textos):
            await self._abort(
                context,
                InvalidRequestError(message="nenhum texto informado para embeddings"),
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

    @observar_rpc("Responder", "ia.responder")
    async def Responder(
        self, request: pb.ResponderRequest, context: grpc.aio.ServicerContext
    ) -> pb.ResponderResponse:
        await self._require(
            context, request.mensagem, "mensagem", "Responder", request.tenant_id
        )
        config = await self._config(context, "Responder", request.tenant_id)
        if usa_jev(config):
            resposta_jev = await self._responder_jev(request, config)
            if resposta_jev is not None:
                return resposta_jev
            reserva = True
        else:
            reserva = False
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
                msg_sem_info=config.msg_sem_info,
                dados_treinamento=request.dados_treinamento,
                similarity_threshold=config.similarity_threshold,
                confianca_minima_transferencia=config.confianca_minima_transferencia,
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
                if reserva and final.transferir_atendimento:
                    contar_transferencia("reserva")
                return pb.ResponderResponse(
                    resposta_texto=final.resposta_texto,
                    transferir_atendimento=final.transferir_atendimento,
                    fluxo_transferencia=final.fluxo_transferencia,
                    confiabilidade=final.confiabilidade,
                    # C1 — o valor vai como JSON porque o campo é tipado do
                    # outro lado (texto, número, data, lista) e o contrato não
                    # carrega o tipo. Serializar aqui deixa a conversão num
                    # lugar só: quem conhece o `tipo` é o catálogo, no servidor.
                    campos_extraidos=[
                        pb.CampoExtraido(
                            slug=c.slug,
                            valor_json=json.dumps(c.valor, ensure_ascii=False),
                            confianca=c.confianca,
                        )
                        for c in final.campos_extraidos
                    ],
                    # Motor Jev fora do ar: o caminho atual responde, e a
                    # decisão sai marcada como reserva.
                    motor="jev" if reserva else "llm",
                    decisao="reserva" if reserva else "",
                )
            case Failure(error):
                await self._abort(context, error, "Responder", request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    async def _responder_jev(
        self, request: pb.ResponderRequest, config: RuntimeConfig
    ) -> pb.ResponderResponse | None:
        """Resposta pelo motor Jev; `None` = cair na reserva (LLM com schema).

        Só falha do Jev leva à reserva: o cliente nunca fica sem resposta por
        causa do fornecedor novo. Erro da LLM de geração segue como erro.
        """
        try:
            jev = self._jev(config)
        except JevNaoConfigurado:
            contar_reserva("jev_nao_configurado")
            return None
        usecase = ResponderJevUsecase(
            ResponderJevRepository(
                ResponderJevDataSource(chat_model_factory=self._chat_model_factory)
            )
        )
        result = await usecase(
            ResponderJevParameters(
                mensagem=request.mensagem,
                historico=_history(request.historico),
                jev=jev,
                llm=config.spec_llm(),
                fluxos=fluxos_do_proto(request.fluxos_disponiveis),
                intents=intents_do_proto(request.intents),
                trechos=trechos_do_proto(request.trechos, request.dados_treinamento),
                comportamento_vetor=request.comportamento,
                campos_coletados=tuple(
                    CampoColetado(slug=c.slug, nome=c.nome, valor=c.valor)
                    for c in request.campos_coletados
                ),
                campos_pendentes=tuple(
                    CampoPendente(
                        slug=c.slug, nome=c.nome, descricao=c.descricao, hint=c.hint
                    )
                    for c in request.campos_pendentes
                ),
                regras=tuple(config.regras_transferencia),
                sinais=sinais_de(config.transferencia_sinais),
                limiares=limiares_de(config.jev_config),
                fluxo_padrao_id=config.transferencia_fluxo_padrao_id,
                piso_b4=config.confianca_minima_transferencia,
                dados_empresa=config.dados_empresa,
                persona_bot=config.persona_bot,
                bot_agent_name=config.bot_agent_name,
                msg_transferencia=config.msg_transferencia,
                msg_sem_info=config.msg_sem_info,
                prompts=dict(config.prompts),
            )
        )
        match result:
            case Success(d):
                if d.transferir:
                    contar_transferencia(d.motivo)
                return pb.ResponderResponse(
                    resposta_texto=d.resposta_texto,
                    transferir_atendimento=d.transferir,
                    fluxo_transferencia=d.fluxo_transferencia,
                    confiabilidade=d.confiabilidade,
                    campos_extraidos=[
                        pb.CampoExtraido(slug=s, valor_json=v, confianca=c)
                        for s, v, c in d.campos_extraidos
                    ],
                    motivo_transferencia=d.motivo,
                    sinais=[
                        pb.SinalDaDecisao(nome=s.nome, valor=s.valor, limiar=s.limiar)
                        for s in d.sinais
                    ],
                    motor="jev",
                    modelo=d.modelo,
                    uso=pb.UsoDoMotor(
                        tokens_entrada=d.tokens_entrada,
                        requisicoes=d.requisicoes,
                        duracao_ms=d.duracao_ms,
                    ),
                    trechos=[
                        pb.TrechoAvaliado(
                            id=t.id, aprovado=t.aprovado, conflito=t.conflito
                        )
                        for t in d.trechos
                    ],
                    intencao_principal=d.intencao_principal,
                    confianca_intencao=d.confianca_intencao,
                    decisao=d.decisao,
                    regra_id=d.regra_id,
                    regerada=d.regerada,
                )
            case Failure(
                JevIndisponivelError()
                | JevNaoConfiguradoError()
                | JevPerguntaInvalidaError() as erro
            ):
                logger.warning(
                    "Responder pelo Jev falhou; caindo na reserva",
                    tenant_id=request.tenant_id,
                    error_code=type(erro).__name__,
                )
                contar_reserva(type(erro).__name__)
                return None
            case Failure(error):
                # Erro da LLM de geração ou inesperado no caminho novo: a
                # reserva tenta com a LLM com schema, que é o caminho atual.
                logger.warning(
                    "Responder pelo Jev falhou fora do Jev",
                    tenant_id=request.tenant_id,
                    erro=type(error).__name__,
                )
                contar_reserva("outro")
                return None
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    @observar_rpc("Sentimento", "ia.sentimento")
    async def Sentimento(
        self, request: pb.SentimentoRequest, context: grpc.aio.ServicerContext
    ) -> pb.SentimentoResponse:
        # Sem histórico não há resposta do cliente para avaliar: o prompt iria
        # ao LLM com `chat_history` vazio e voltaria uma nota inventada. Falha
        # cedo, como `Embed` faz com `textos` vazio.
        if not list(request.historico.turnos):
            await self._abort(
                context,
                InvalidRequestError(message="histórico vazio: nada a avaliar"),
                "Sentimento",
                request.tenant_id,
            )
        config = await self._config(context, "Sentimento", request.tenant_id)
        if usa_jev(config):
            avaliacao_jev = await self._sentimento_jev(request, config)
            if avaliacao_jev is not None:
                return avaliacao_jev
        usecase = SentimentoUsecase(
            SentimentoRepository(
                SentimentoDataSource(chat_model_factory=self._chat_model_factory)
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

    async def _sentimento_jev(
        self, request: pb.SentimentoRequest, config: RuntimeConfig
    ) -> pb.SentimentoResponse | None:
        """Nota e sentimento pelo Jev; `None` = cair no caminho da LLM."""
        try:
            jev = self._jev(config)
        except JevNaoConfigurado:
            return None
        usecase = SentimentoJevUsecase(
            SentimentoJevRepository(SentimentoJevDataSource())
        )
        result = await usecase(
            SentimentoJevParameters(historico=_history(request.historico), jev=jev)
        )
        match result:
            case Success(avaliacao):
                return pb.SentimentoResponse(
                    nota=avaliacao.nota,
                    sentimento=avaliacao.sentimento,
                    feedback=avaliacao.feedback,
                )
            case Failure(error):
                logger.warning(
                    "Sentimento pelo Jev falhou; usando a LLM",
                    tenant_id=request.tenant_id,
                    erro=type(error).__name__,
                )
                return None
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    @observar_rpc("TestarRegraTransferencia", "ia.testar_regra")
    async def TestarRegraTransferencia(
        self,
        request: pb.TestarRegraTransferenciaRequest,
        context: grpc.aio.ServicerContext,
    ) -> pb.TestarRegraTransferenciaResponse:
        """Uma frase contra uma regra de transferência. Nada é gravado."""
        rpc = "TestarRegraTransferencia"
        await self._require(context, request.frase, "frase", rpc, request.tenant_id)
        await self._require(
            context, request.condicao, "condicao", rpc, request.tenant_id
        )
        config = await self._config(context, rpc, request.tenant_id)
        try:
            jev = self._jev(config)
        except JevNaoConfigurado as exc:
            await self._abort(
                context,
                JevNaoConfiguradoError(message=str(exc)),
                rpc,
                request.tenant_id,
            )
        usecase = ProvaDeRegraUsecase(ProvaDeRegraRepository(ProvaDeRegraDataSource()))
        result = await usecase(
            ProvaDeRegraParameters(
                frase=request.frase,
                condicao=request.condicao,
                exemplos_sim=tuple(request.exemplos_sim),
                exemplos_nao=tuple(request.exemplos_nao),
                sensibilidade=request.sensibilidade or "media",
                jev=jev,
                limiares=limiares_de(config.jev_config),
            )
        )
        match result:
            case Success(prova):
                return pb.TestarRegraTransferenciaResponse(
                    probabilidade=prova.probabilidade,
                    limiar=prova.limiar,
                    dispararia=prova.dispararia,
                    modelo=prova.modelo,
                )
            case Failure(error):
                await self._abort(context, error, rpc, request.tenant_id)
            case _:  # pragma: no cover - provado pelo mypy
                assert_never(result)

    @observar_rpc("ExtrairTextoDocumento", "ia.extrair_texto")
    async def ExtrairTextoDocumento(
        self,
        request: pb.ExtrairTextoDocumentoRequest,
        context: grpc.aio.ServicerContext,
    ) -> pb.ExtrairTextoDocumentoResponse:
        """B9 (N10 E5) — texto de um documento de treinamento.

        Sem LLM: não precisa de chave de provedor nem da config do tenant, por
        isso não passa por `_config`. O tenant só identifica o log.
        """
        await self._require(
            context,
            request.media.url,
            "media.url",
            "ExtrairTextoDocumento",
            request.tenant_id,
        )
        usecase = ExtrairTextoUsecase(ExtrairTextoRepository(ExtrairTextoDataSource()))
        result = await usecase(
            ExtrairTextoParameters(
                url=request.media.url,
                mimetype=request.media.mimetype,
                nome_arquivo=request.media.file_name,
            )
        )
        match result:
            case Success(extraido):
                # Só a contagem vai para o log: o texto pode ter dado sensível.
                logger.info(
                    "ExtrairTextoDocumento ok (tenant={}): formato={} caracteres={}",
                    request.tenant_id,
                    extraido.formato,
                    len(extraido.texto),
                )
                return pb.ExtrairTextoDocumentoResponse(
                    texto=extraido.texto,
                    formato=extraido.formato,
                    caracteres=len(extraido.texto),
                )
            case Failure(error):
                await self._abort(
                    context, error, "ExtrairTextoDocumento", request.tenant_id
                )
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
                    message="ia_engine_jev sem cache de config (Redis não configurado)"
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
                InvalidRequestError(message=f"campo obrigatório ausente: {field}"),
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
            "erro interno no ia_engine_jev"
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
        # Motor Jev: fornecedor fora é transitório; chave ausente é
        # configuração da plataforma, não falha da IA.
        case JevIndisponivelError():
            return grpc.StatusCode.UNAVAILABLE
        case JevNaoConfiguradoError():
            return grpc.StatusCode.FAILED_PRECONDITION
        # B9: o arquivo é o problema, não o serviço — quem enviou pode corrigir.
        case FormatoNaoSuportadoError() | DocumentoIlegivelError() | TextoVazioError():
            return grpc.StatusCode.INVALID_ARGUMENT
        case _:
            return grpc.StatusCode.INTERNAL


def _history(historico: pb.ChatHistory) -> tuple[ChatTurnTuple, ...]:
    return tuple((t.role, t.conteudo) for t in historico.turnos)
