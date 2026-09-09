"""Traces e métricas do `mcp_server`.

Segue o padrão do `ia_engine`: OTLP/gRPC para o mesmo collector, com
`service.name` e `deployment.environment` vindos do ambiente.

# Cardinalidade

`grant_id` **não** entra como label de métrica. Ele é um identificador — uma
série temporal por consentimento faria o Prometheus crescer sem teto, e o que se
quer saber ("quais aplicativos estão mais ativos") já está na auditoria, com
`client_name`, que é cardinalidade baixa.

Os labels são `tool`, `result` e `motivo`, todos de domínio fechado.

# Nome do histograma

`smartcore_mcp_tool_duration_ms` termina em `_ms` de propósito e o collector está
configurado com `add_metric_suffixes: false`. Sem isso o Prometheus receberia
`..._duration_ms_milliseconds_bucket` e o painel não acharia a métrica — foi
exatamente o defeito corrigido no `otel-collector-config.yml`.
"""

from __future__ import annotations

import os

from loguru import logger
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

SERVICO = "mcp_server"


def inicializar() -> None:
    """Liga o pipeline OTLP. Desligado por `OTEL_SDK_DISABLED=true`."""
    if os.getenv("OTEL_SDK_DISABLED", "").lower() == "true":
        logger.info("telemetria OTel desativada por OTEL_SDK_DISABLED")
        return

    namespace = os.getenv("OTEL_SERVICE_NAMESPACE", "")
    ambiente = "development" if "dev" in namespace else "production"
    recurso = Resource.create(
        {
            "service.name": SERVICO,
            "service.namespace": namespace or "smart-core-v2",
            "deployment.environment": ambiente,
        }
    )
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

    provider = TracerProvider(resource=recurso)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint)))
    trace.set_tracer_provider(provider)

    leitor = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=endpoint), export_interval_millis=10_000
    )
    metrics.set_meter_provider(MeterProvider(resource=recurso, metric_readers=[leitor]))

    logger.info("telemetria inicializada (OTLP {}, ambiente {})", endpoint, ambiente)


class Metricas:
    """As três métricas do módulo, criadas uma vez."""

    def __init__(self) -> None:
        medidor = metrics.get_meter(SERVICO)
        self._total = medidor.create_counter(
            "smartcore_mcp_tool_total",
            description="Execuções de tool do MCP, por resultado",
        )
        self._duracao = medidor.create_histogram(
            "smartcore_mcp_tool_duration_ms",
            unit="ms",
            description="Duração da execução de uma tool do MCP",
        )
        self._negadas = medidor.create_counter(
            "smartcore_mcp_denied_total",
            description="Execuções recusadas por um guard, por motivo",
        )

    def tool_executada(self, tool: str, resultado: str, duracao_s: float) -> None:
        self._total.add(1, {"tool": tool, "result": resultado})
        self._duracao.record(duracao_s * 1000.0, {"tool": tool})

    def negada(self, tool: str, motivo: str) -> None:
        """Recusa por guard.

        É a métrica que revela um agente em laço antes de o cliente perceber:
        um pico de `motivo="rate_limit"` ou `motivo="escopo"` num só tenant é a
        assinatura disso — e também a de um token vazado sendo sondado.
        """
        self._negadas.add(1, {"tool": tool, "motivo": motivo})


def tracer() -> trace.Tracer:
    return trace.get_tracer(SERVICO)
