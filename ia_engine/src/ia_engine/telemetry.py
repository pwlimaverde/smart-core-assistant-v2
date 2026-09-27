"""Observabilidade OTLP: traces, métricas, log JSON e o span de cada RPC.

O interceptor de servidor extrai o `traceparent` do metadata gRPC de entrada e
inicia o span sob esse contexto (mesma convenção W3C do lado Rust). Usa o
interceptor oficial de `opentelemetry-instrumentation-grpc`, que já faz a
extração do contexto de propagação a partir do metadata.

Abaixo do span do interceptor, cada RPC abre o span da feature (`ia.responder`,
`ia.rag.embed`, ...) com o `tenant_id` — o interceptor não conhece o tenant, e
sem ele o Tempo não responde "por que a IA do tenant X está lenta".

# Métricas

`smartcore_ia_rpc_total{rpc,result,codigo}` e
`smartcore_ia_rpc_duration_ms{rpc}`. `tenant_id` **não** é label: uma série por
tenant cresceria sem teto — ele está no span e no log. O histograma termina em
`_ms` e o collector roda com `add_metric_suffixes: false` (ver
`otel-collector-config.yml`), então o nome chega ao Prometheus como está.
"""

from __future__ import annotations

import asyncio
import functools
import json
import os
import sys
import time
import traceback
from collections.abc import Awaitable, Callable
from datetime import UTC
from typing import TYPE_CHECKING, Any, Protocol, TypeVar

import grpc
from loguru import logger
from opentelemetry import metrics, trace
from opentelemetry.instrumentation.grpc import aio_server_interceptor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import Status, StatusCode

if TYPE_CHECKING:
    import grpc.aio

    from ia_engine.settings import Settings

_SERVICE_NAME = "ia_engine"


def _ambiente(settings: Settings) -> tuple[str, str]:
    """`service.namespace` e `deployment.environment`, como os serviços Rust.

    O namespace vem de `OTEL_SERVICE_NAMESPACE` (`smartcore-dev`/`smartcore-prod`)
    e decide o ambiente — é o mesmo critério de `observability::init_telemetry`,
    para que um filtro `deployment_environment="development"` pegue a stack
    inteira, e não todos os serviços menos a IA.
    """
    namespace = os.getenv("OTEL_SERVICE_NAMESPACE", "")
    if namespace:
        return namespace, "development" if "dev" in namespace else "production"
    return "smart-core-v2", settings.smartcore_env


def setup_telemetry(settings: Settings) -> list[grpc.aio.ServerInterceptor]:
    """Configura traces e métricas e retorna os interceptors do servidor.

    Se `OTEL_EXPORTER_OTLP_ENDPOINT` não estiver definido, os spans são criados
    mas não exportados (sem exporter) — o serviço não depende do coletor.
    """
    namespace, ambiente = _ambiente(settings)
    resource = Resource.create(
        {
            "service.name": _SERVICE_NAME,
            "service.namespace": namespace,
            "deployment.environment": ambiente,
        }
    )
    provider = TracerProvider(resource=resource)

    endpoint = settings.otel_exporter_otlp_endpoint
    if endpoint:
        from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import (
            OTLPMetricExporter,
        )
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

        provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
        )
        leitor = PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=endpoint), export_interval_millis=10_000
        )
        metrics.set_meter_provider(
            MeterProvider(resource=resource, metric_readers=[leitor])
        )
        logger.info("OTLP traces e métricas habilitados (endpoint={})", endpoint)
    else:
        logger.info("OTLP endpoint não configurado; tracing sem exporter")

    trace.set_tracer_provider(provider)
    return [aio_server_interceptor()]


# ------------------------------------------------------------------- logs


def configurar_logs() -> None:
    """Log em JSON, uma linha por evento, no stdout — como os serviços Rust.

    O Loki recebe o stdout do container pelo promtail, e os painéis consultam
    com `| json`: texto livre não era filtrável por `level` nem `tenant_id`, e o
    log de uma falha não levava ao trace dela. `SMARTCORE_LOG_FORMAT=texto`
    volta ao formato legível para rodar local.
    """
    if os.getenv("SMARTCORE_LOG_FORMAT", "").lower() == "texto":
        return
    logger.remove()
    logger.add(_escrever_json, level=os.getenv("LOG_LEVEL", "INFO").upper())


def _escrever_json(mensagem: Any) -> None:
    sys.stdout.write(linha_json(mensagem.record) + "\n")
    sys.stdout.flush()


def linha_json(registro: dict[str, Any]) -> str:
    """Um registro do loguru como objeto JSON plano.

    Os campos extras vão para o nível de cima, onde o `| json` do Loki os
    encontra. Exceção sai com o traceback formatado — sem os valores das
    variáveis locais, que podem ter prompt, mensagem ou chave de provedor.
    """
    linha: dict[str, Any] = {
        "timestamp": registro["time"]
        .astimezone(UTC)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
        "level": registro["level"].name,
        "service": _SERVICE_NAME,
        "target": registro["name"],
        "message": registro["message"],
    }
    contexto = trace.get_current_span().get_span_context()
    if contexto.is_valid:
        linha["trace_id"] = format(contexto.trace_id, "032x")
        linha["span_id"] = format(contexto.span_id, "016x")
    for chave, valor in registro["extra"].items():
        if isinstance(valor, str | int | float | bool) or valor is None:
            linha.setdefault(chave, valor)
        else:
            linha.setdefault(chave, str(valor))
    excecao = registro["exception"]
    if excecao is not None and excecao.type is not None:
        linha["exception"] = "".join(
            traceback.format_exception(excecao.type, excecao.value, excecao.traceback)
        )
    return json.dumps(linha, ensure_ascii=False)


# -------------------------------------------------------------- por RPC


class _Metricas:
    def __init__(self) -> None:
        medidor = metrics.get_meter(_SERVICE_NAME)
        self.total = medidor.create_counter(
            "smartcore_ia_rpc_total",
            description="RPCs do ia_engine, por resultado e código gRPC",
        )
        self.duracao = medidor.create_histogram(
            "smartcore_ia_rpc_duration_ms",
            unit="ms",
            description="Duração de um RPC do ia_engine (inclui a chamada ao LLM)",
        )


_metricas: _Metricas | None = None


def _obter_metricas() -> _Metricas:
    # Preguiçoso: criado depois de `setup_telemetry`, senão os instrumentos
    # ficariam presos ao provider no-op do import.
    global _metricas
    if _metricas is None:
        _metricas = _Metricas()
    return _metricas


class _ComTenant(Protocol):
    tenant_id: str


_Req = TypeVar("_Req", bound=_ComTenant)
_Resp = TypeVar("_Resp")
_Metodo = Callable[[Any, _Req, "grpc.aio.ServicerContext"], Awaitable[_Resp]]


def observar_rpc(
    rpc: str, span: str
) -> Callable[[_Metodo[_Req, _Resp]], _Metodo[_Req, _Resp]]:
    """Span da feature, métrica e log de desfecho de um RPC do servicer.

    O desfecho vem do `context.code()`: o servicer encerra falhas com
    `context.abort`, que levanta e já deixou o código gravado. Exceção sem
    código é falha inesperada (`INTERNAL`). Nada do request além do
    `tenant_id` entra no span ou no log — mensagem, prompt e mídia ficam fora.
    """

    def decorar(metodo: _Metodo[_Req, _Resp]) -> _Metodo[_Req, _Resp]:
        @functools.wraps(metodo)
        async def envolvido(
            self: Any, request: _Req, context: grpc.aio.ServicerContext
        ) -> _Resp:
            inicio = time.perf_counter()
            tenant_id = request.tenant_id
            with trace.get_tracer(_SERVICE_NAME).start_as_current_span(span) as s:
                s.set_attribute("ia.rpc", rpc)
                s.set_attribute("tenant_id", tenant_id)
                codigo = "OK"
                try:
                    return await metodo(self, request, context)
                except asyncio.CancelledError:
                    # Cliente desistiu (deadline do worker) — não é falha da IA.
                    codigo = grpc.StatusCode.CANCELLED.name
                    raise
                except BaseException:
                    codigo = _codigo_do_contexto(context)
                    s.set_status(Status(StatusCode.ERROR, codigo))
                    raise
                finally:
                    duracao_ms = (time.perf_counter() - inicio) * 1000
                    s.set_attribute("rpc.grpc.status", codigo)
                    resultado = "ok" if codigo == "OK" else "erro"
                    m = _obter_metricas()
                    m.total.add(1, {"rpc": rpc, "result": resultado, "codigo": codigo})
                    m.duracao.record(duracao_ms, {"rpc": rpc})
                    logger.info(
                        "rpc concluído",
                        rpc=rpc,
                        tenant_id=tenant_id,
                        codigo=codigo,
                        duracao_ms=round(duracao_ms, 1),
                    )

        return envolvido

    return decorar


def _codigo_do_contexto(context: grpc.aio.ServicerContext) -> str:
    try:
        codigo = context.code()
    except Exception:  # noqa: BLE001 — contexto de teste sem `code()`
        codigo = None
    if isinstance(codigo, grpc.StatusCode) and codigo is not grpc.StatusCode.OK:
        return codigo.name
    return grpc.StatusCode.INTERNAL.name
