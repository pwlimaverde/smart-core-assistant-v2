"""Observabilidade do `ia_engine_jev`: desfecho de cada RPC e log estruturado.

O contrato (doc 17 §2): span por feature com `tenant_id`, métrica por RPC e
nenhum conteúdo de mensagem, prompt ou chave em span ou log.
"""

from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any

import grpc
import pytest

from ia_engine_jev import telemetry
from ia_engine_jev.telemetry import linha_json, observar_rpc


class _Contador:
    def __init__(self) -> None:
        self.chamadas: list[tuple[float, dict[str, str]]] = []

    def add(self, valor: float, atributos: dict[str, str]) -> None:
        self.chamadas.append((valor, atributos))

    record = add


@pytest.fixture
def metricas(monkeypatch: pytest.MonkeyPatch) -> SimpleNamespace:
    falsas = SimpleNamespace(total=_Contador(), duracao=_Contador())
    monkeypatch.setattr(telemetry, "_metricas", falsas)
    return falsas


class _Contexto:
    def __init__(self, codigo: grpc.StatusCode | None = None) -> None:
        self._codigo = codigo

    def code(self) -> grpc.StatusCode | None:
        return self._codigo


class _Servicer:
    @observar_rpc("Responder", "ia.responder")
    async def Responder(self, request: Any, context: Any) -> str:  # noqa: N802
        if request.falhar:
            raise RuntimeError("abortado")
        return "resposta"


def _request(falhar: bool = False) -> SimpleNamespace:
    return SimpleNamespace(
        tenant_id="t-1", mensagem="conteúdo do cliente", falhar=falhar
    )


async def test_rpc_ok_conta_sucesso_e_mede(metricas: SimpleNamespace) -> None:
    resposta = await _Servicer().Responder(_request(), _Contexto())

    assert resposta == "resposta"
    assert metricas.total.chamadas == [
        (1, {"rpc": "Responder", "result": "ok", "codigo": "OK"})
    ]
    ((duracao, atributos),) = metricas.duracao.chamadas
    assert duracao >= 0
    # Sem tenant na métrica: uma série por tenant cresceria sem teto.
    assert atributos == {"rpc": "Responder"}


async def test_rpc_abortado_conta_o_codigo_do_abort(
    metricas: SimpleNamespace,
) -> None:
    contexto = _Contexto(grpc.StatusCode.FAILED_PRECONDITION)

    with pytest.raises(RuntimeError):
        await _Servicer().Responder(_request(falhar=True), contexto)

    assert metricas.total.chamadas == [
        (
            1,
            {"rpc": "Responder", "result": "erro", "codigo": "FAILED_PRECONDITION"},
        )
    ]


async def test_falha_sem_codigo_e_interna(metricas: SimpleNamespace) -> None:
    with pytest.raises(RuntimeError):
        await _Servicer().Responder(_request(falhar=True), _Contexto())

    assert metricas.total.chamadas[0][1]["codigo"] == "INTERNAL"


async def test_cancelamento_nao_conta_como_falha_da_ia(
    metricas: SimpleNamespace,
) -> None:
    class _Lento:
        @observar_rpc("Responder", "ia.responder")
        async def Responder(self, request: Any, context: Any) -> str:  # noqa: N802
            raise asyncio.CancelledError

    with pytest.raises(asyncio.CancelledError):
        await _Lento().Responder(_request(), _Contexto())

    assert metricas.total.chamadas[0][1]["codigo"] == "CANCELLED"


def _registro(mensagem: str, **extra: object) -> dict[str, object]:
    return {
        "time": datetime(2026, 9, 27, 3, 0, tzinfo=UTC),
        "level": SimpleNamespace(name="INFO"),
        "name": "ia_engine_jev.telemetry",
        "message": mensagem,
        "extra": extra,
        "exception": None,
    }


def test_log_json_plano_com_os_campos_extras() -> None:
    linha = json.loads(
        linha_json(_registro("rpc concluído", rpc="Responder", tenant_id="t-1"))
    )

    assert linha["service"] == "ia_engine_jev"
    assert linha["level"] == "INFO"
    assert linha["rpc"] == "Responder"
    assert linha["tenant_id"] == "t-1"
    assert linha["timestamp"] == "2026-09-27T03:00:00.000Z"


def test_log_json_com_excecao_leva_o_traceback() -> None:
    try:
        raise ValueError("falha")
    except ValueError as exc:
        erro = exc
    registro = _registro("x", objeto=object())
    registro["exception"] = SimpleNamespace(
        type=ValueError, value=erro, traceback=erro.__traceback__
    )

    linha = json.loads(linha_json(registro))

    assert "ValueError: falha" in linha["exception"]
    assert linha["objeto"].startswith("<object object")
