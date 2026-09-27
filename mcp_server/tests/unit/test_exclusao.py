"""Excluir é definitivo; desativar é reversível (doc_dev/planejamento/39).

A ferramenta precisa dizer isso ao agente, simular antes, e só excluir com o
nome que o servidor devolveu na simulação.
"""

from __future__ import annotations

import os

import pytest
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import exclusao  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]


def _montar(simulacao: pb.ExcluirMyItemResponse | None = None):
    servidor, registro, executor, cliente, metricas = montar_ambiente(
        {
            "ExcluirMyItem": simulacao
            or pb.ExcluirMyItemResponse(
                sucesso=True, simulacao=True, rotulo="Paulo W", conversas=2
            ),
            "DefinirMyItemAtivo": pb.SimpleOkResponse(sucesso=True),
            "ListMyExcluidos": pb.ListMyExcluidosResponse(
                itens=[
                    pb.ItemExcluido(
                        tipo="contato",
                        id=546,
                        rotulo="Paulo W",
                        excluido_em=1790500000000,
                        excluido_por="dono@x.com",
                    )
                ]
            ),
        }
    )
    exclusao.registrar(servidor, registro, executor)
    return servidor, cliente, metricas


def test_a_descricao_diz_que_excluir_e_definitivo():
    servidor, _, _ = _montar()
    doc = servidor.funcoes["excluir_item"].__doc__ or ""
    assert "definitivamente" in doc
    assert "não pode ser restaurado" in doc
    assert "desativar" in doc


async def test_dry_run_mostra_o_nome_a_digitar_e_o_que_vai_junto():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["excluir_item"](tipo="contato", id=546, dry_run=True)
    assert "SIMULAÇÃO" in r
    assert "DEFINITIVAMENTE" in r
    assert "2 conversa(s)" in r
    assert "confirmar='Paulo W'" in r
    _, req, _ = cliente.chamadas[-1]
    assert req.dry_run is True
    assert req.confirmar == ""


async def test_item_em_uso_nao_e_oferecido_para_exclusao():
    servidor, _, _ = _montar(
        pb.ExcluirMyItemResponse(
            sucesso=True, simulacao=True, rotulo="Vendas", em_uso="há 2 conversa(s)"
        )
    )
    with como(ADMIN):
        r = await servidor.funcoes["excluir_item"](tipo="fluxo", id=3, dry_run=True)
    assert "não pode ser excluído" in r
    assert "há 2 conversa(s)" in r


async def test_sem_confirmacao_nada_chega_ao_servidor():
    servidor, cliente, _ = _montar()
    with como(ADMIN), pytest.raises(ToolError, match="confirmação"):
        await servidor.funcoes["excluir_item"](tipo="nota", id=9)
    assert cliente.metodos == []


async def test_exclusao_leva_o_nome_para_o_servidor_conferir():
    servidor, cliente, _ = _montar(
        pb.ExcluirMyItemResponse(sucesso=True, atendimentos_excluidos=[462, 463])
    )
    with como(ADMIN):
        r = await servidor.funcoes["excluir_item"](
            tipo="contato", id=546, confirmar="Paulo W"
        )
    _, req, _ = cliente.chamadas[-1]
    assert (req.tipo, req.id, req.confirmar, req.dry_run) == (
        "contato",
        546,
        "Paulo W",
        False,
    )
    assert "definitivamente com 2 conversa(s)" in r
    assert "Não há como restaurar" in r


async def test_reativar_nao_serve_para_excluido():
    servidor, _, _ = _montar()
    doc = servidor.funcoes["reativar_item"].__doc__ or ""
    assert "excluído" in doc
    with como(ADMIN):
        r = await servidor.funcoes["reativar_item"](tipo="etiqueta", id=4)
    assert "reativado" in r


async def test_lista_de_excluidos_traz_a_data_legivel():
    servidor, _, _ = _montar()
    with como(ADMIN):
        itens = await servidor.funcoes["list_excluidos"]()
    assert itens[0]["rotulo"] == "Paulo W"
    assert str(itens[0]["excluido_em"]).endswith("Z")
