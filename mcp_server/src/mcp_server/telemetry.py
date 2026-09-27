"""Traces e métricas do `mcp_server`.

Segue o padrão do `ia_engine`: OTLP/gRPC para o mesmo collector, com
`service.name` e `deployment.environment` vindos do ambiente.

# Cardinalidade

`grant_id` **não** entra como label de métrica. Ele é um identificador — uma
série temporal por consentimento faria o Prometheus crescer sem teto, e o que se
quer saber ("quais aplicativos estão mais ativos") já está na auditoria, com
`client_name`, que é cardinalidade baixa.

Os labels são `tool`, `categoria`, `result` e `motivo`, todos de domínio
fechado. `categoria` é o que deixa o alerta de ações destrutivas valer para toda
tool da categoria, e não só para as que casam com um padrão de nome.

# Nome do histograma

`smartcore_mcp_tool_duration_ms` termina em `_ms` de propósito e o collector está
configurado com `add_metric_suffixes: false`. Sem isso o Prometheus receberia
`..._duration_ms_milliseconds_bucket` e o painel não acharia a métrica — foi
exatamente o defeito corrigido no `otel-collector-config.yml`.
"""

from __future__ import annotations

import json
import os
import sys
import traceback
from datetime import UTC
from typing import Any

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


def configurar_logs() -> None:
    """Log em JSON, uma linha por evento, no stdout — como os serviços Rust.

    O Loki recebe o stdout do container pelo promtail, e os painéis e alertas
    consultam com `| json`: texto livre não era filtrável por `level`,
    `tenant_id` nem `trace_id`, e o log de uma tool não levava ao trace dela.
    `SMARTCORE_LOG_FORMAT=texto` volta ao formato legível para rodar local.
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

    Os campos extras (`logger.info(..., tool=...)`) vão para o nível de cima,
    onde o `| json` do Loki os encontra. Exceção sai com o traceback formatado
    — sem os valores das variáveis locais, que podem ter dado de cliente.
    """
    linha: dict[str, Any] = {
        "timestamp": registro["time"]
        .astimezone(UTC)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
        "level": registro["level"].name,
        "service": SERVICO,
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

    def tool_executada(
        self, tool: str, resultado: str, duracao_s: float, categoria: str = ""
    ) -> None:
        self._total.add(1, {"tool": tool, "result": resultado, "categoria": categoria})
        # Simulação não chega ao backend: um zero no histograma puxaria a
        # latência da tool para baixo sem ter medido nada.
        if resultado != "dry_run":
            self._duracao.record(
                duracao_s * 1000.0, {"tool": tool, "categoria": categoria}
            )

    def negada(self, tool: str, motivo: str, categoria: str = "") -> None:
        """Recusa por guard.

        É a métrica que revela um agente em laço antes de o cliente perceber:
        um pico de `motivo="rate_limit"` ou `motivo="escopo"` num só tenant é a
        assinatura disso — e também a de um token vazado sendo sondado.
        """
        self._negadas.add(1, {"tool": tool, "motivo": motivo, "categoria": categoria})


def tracer() -> trace.Tracer:
    return trace.get_tracer(SERVICO)
