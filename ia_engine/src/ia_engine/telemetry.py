"""Observabilidade OTLP: TracerProvider + interceptor gRPC (traceparent W3C).

O interceptor de servidor extrai o `traceparent` do metadata gRPC de entrada e
inicia o span sob esse contexto (mesma convenção W3C do lado Rust). Usa o
interceptor oficial de `opentelemetry-instrumentation-grpc`, que já faz a
extração do contexto de propagação a partir do metadata.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from loguru import logger
from opentelemetry import trace
from opentelemetry.instrumentation.grpc import aio_server_interceptor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

if TYPE_CHECKING:
    import grpc.aio

    from ia_engine.settings import Settings

_SERVICE_NAME = "ia_engine"


def setup_telemetry(settings: Settings) -> list[grpc.aio.ServerInterceptor]:
    """Configura o TracerProvider e retorna os interceptors do servidor.

    Se `OTEL_EXPORTER_OTLP_ENDPOINT` não estiver definido, os spans são criados
    mas não exportados (sem exporter) — o serviço não depende do coletor.
    """
    resource = Resource.create(
        {
            "service.name": _SERVICE_NAME,
            "deployment.environment": settings.smartcore_env,
        }
    )
    provider = TracerProvider(resource=resource)

    endpoint = settings.otel_exporter_otlp_endpoint
    if endpoint:
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
            OTLPSpanExporter,
        )

        provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
        )
        logger.info("OTLP tracing habilitado (endpoint={})", endpoint)
    else:
        logger.info("OTLP endpoint não configurado; tracing sem exporter")

    trace.set_tracer_provider(provider)
    return [aio_server_interceptor()]
