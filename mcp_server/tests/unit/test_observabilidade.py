"""Observabilidade do MCP: origem na trilha, trace contínuo, métrica e log.

Cada teste aqui corresponde a uma linha do contrato do doc 29 §3 que chegou a
estar quebrada em produção sem nenhum teste perceber.
"""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from mcp.server.mcpserver.exceptions import ToolError
from opentelemetry.sdk.trace import TracerProvider

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.runtime_client import (  # noqa: E402
    origem_da_chamada,
    traceparent_atual,
)
from mcp_server.telemetry import linha_json  # noqa: E402
from mcp_server.tools.registry import Categoria  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402


async def test_executor_diz_ao_backend_qual_tool_pediu():
    """A trilha mostra a tool, não o RPC: `update_etiqueta`, não `UpdateEtiqueta`."""
    _, registro, executor, cliente, metricas = montar_ambiente({"UpdateEtiqueta": "ok"})
    registro.registrar(
        "update_etiqueta", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    with como(["atendimentos:write"], grant_id="g-9"):
        await executor.executar("update_etiqueta", "UpdateEtiqueta", object())

    assert cliente.tools_recebidas == ["update_etiqueta"]
    assert cliente.grants_recebidos == ["g-9"]
    # A categoria vai na métrica: é por ela que o alerta de destrutivas filtra.
    assert metricas.categorias == ["configuracao"]


async def test_recusa_por_escopo_conta_com_a_categoria():
    _, registro, executor, _, metricas = montar_ambiente()
    registro.registrar("remover_nota", Categoria.DESTRUTIVA, ("atendimentos:write",))

    with como(["atendimentos:read"]), pytest.raises(ToolError):
        await executor.executar("remover_nota", "RemoverNota", object())

    assert metricas.negacoes == [("remover_nota", "escopo")]
    assert metricas.categorias == ["destrutiva"]


def test_origem_segue_o_formato_que_a_trilha_le():
    # `infrastructure_postgres::auditoria::audit_log::origem_e_tool` corta no
    # primeiro espaço depois do prefixo: a tool tem de vir logo após a barra.
    assert origem_da_chamada("send_message", "g-1") == (
        "SmartCoreAssistant-MCP/send_message (grant g-1)"
    )
    assert origem_da_chamada("get_painel", None) == "SmartCoreAssistant-MCP/get_painel"


def _tracer_de_verdade(monkeypatch: pytest.MonkeyPatch):
    # Com `OTEL_SDK_DISABLED` o SDK devolve spans que não gravam nada — e sem
    # contexto válido não há o que propagar nem o que pôr no log.
    monkeypatch.delenv("OTEL_SDK_DISABLED", raising=False)
    return TracerProvider().get_tracer("teste")


def test_traceparent_sai_do_span_em_curso(monkeypatch: pytest.MonkeyPatch):
    """Sem isto o `runtime_api` inventava um trace novo a cada chamada."""
    tracer = _tracer_de_verdade(monkeypatch)

    with tracer.start_as_current_span("mcp.tool.x") as span:
        contexto = span.get_span_context()
        traceparent = traceparent_atual()

    # As flags variam com a versão do SDK (01 = amostrado; 03 também marca o
    # trace id aleatório): o que importa é o trace e o span.
    assert traceparent is not None
    assert traceparent.startswith(
        f"00-{contexto.trace_id:032x}-{contexto.span_id:016x}-"
    )


def test_sem_span_nao_ha_traceparent():
    assert traceparent_atual() is None


def _registro(mensagem: str, **extra: object) -> dict[str, object]:
    """O mínimo de um registro do loguru que `linha_json` lê."""
    return {
        "time": datetime(2026, 9, 27, 3, 0, tzinfo=UTC),
        "level": SimpleNamespace(name="WARNING"),
        "name": "mcp_server.tools.base",
        "message": mensagem,
        "extra": extra,
        "exception": None,
    }


def test_log_em_json_com_os_campos_que_o_loki_filtra():
    linha = json.loads(
        linha_json(
            _registro(
                "tool recusada",
                tool="send_message",
                motivo="rate_limit",
                tenant_id="t-1",
            )
        )
    )

    assert linha["level"] == "WARNING"
    assert linha["service"] == "mcp_server"
    assert linha["message"] == "tool recusada"
    assert linha["tool"] == "send_message"
    assert linha["motivo"] == "rate_limit"
    assert linha["tenant_id"] == "t-1"
    assert linha["timestamp"] == "2026-09-27T03:00:00.000Z"


def test_log_leva_o_trace_do_span_em_curso(monkeypatch: pytest.MonkeyPatch):
    """É o que liga a linha do Loki ao trace no Tempo."""
    tracer = _tracer_de_verdade(monkeypatch)

    with tracer.start_as_current_span("mcp.tool.x") as span:
        linha = json.loads(linha_json(_registro("tool executada")))
        contexto = span.get_span_context()

    assert linha["trace_id"] == f"{contexto.trace_id:032x}"
    assert linha["span_id"] == f"{contexto.span_id:016x}"


def test_extra_nao_serializavel_nao_derruba_o_log():
    linha = json.loads(linha_json(_registro("x", objeto=object())))
    assert linha["objeto"].startswith("<object object")
