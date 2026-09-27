"""Excluir é desativar: contato e conversa somem do painel e voltam pela auditoria.

Cada teste corresponde a uma parte do combinado: a ferramenta deixa claro que
excluir desativa, pede confirmação pelo nome e aponta o caminho de volta.
"""

from __future__ import annotations

import os

import pytest
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import atendimento, cadastros  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]


def _montar():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListarAtendimentosDoContato": pb.ListarAtendimentosDoContatoResponse(
                atendimentos=[
                    pb.AtendimentoResumo(id=462),
                    pb.AtendimentoResumo(id=463),
                ]
            ),
            "ListMyContatos": pb.ListMyContatosResponse(
                contatos=[
                    pb.MyContato(
                        id=546, nome_contato="", nome_perfil_whatsapp="Paulo W"
                    ),
                    pb.MyContato(id=9, nome_contato="Outro"),
                ]
            ),
            "DefinirMyContatoAtivo": pb.SimpleOkResponse(sucesso=True),
            "ObterContatoDoAtendimento": pb.ObterContatoDoAtendimentoResponse(
                contato_id=546, nome="Paulo W", telefone="5588"
            ),
            "DefinirMyAtendimentoAtivo": pb.SimpleOkResponse(sucesso=True),
        }
    )
    cadastros.registrar(servidor, registro, executor)
    atendimento.registrar(servidor, registro, executor)
    return servidor, cliente


def test_as_ferramentas_dizem_que_excluir_e_desativar():
    servidor, _ = _montar()
    for nome in ("excluir_contato", "excluir_atendimento"):
        doc = servidor.funcoes[nome].__doc__ or ""
        assert "Excluir aqui é desativar" in doc
        assert "list_auditoria" in doc
        assert "restaurar_" in doc


async def test_dry_run_do_contato_conta_as_conversas_e_nao_escreve():
    servidor, cliente = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["excluir_contato"](contato_id=546, dry_run=True)
    assert "SIMULAÇÃO" in r
    assert "2 conversa(s)" in r
    assert "DefinirMyContatoAtivo" not in cliente.metodos


async def test_excluir_contato_exige_o_nome_e_desativa():
    servidor, cliente = _montar()
    with como(ADMIN):
        with pytest.raises(ToolError):
            await servidor.funcoes["excluir_contato"](contato_id=546)
        # O nome do perfil do WhatsApp também vale: é o que o painel mostra
        # quando não há nome cadastrado.
        r = await servidor.funcoes["excluir_contato"](
            contato_id=546, confirmar="Paulo W"
        )

    metodo, req, _ = cliente.chamadas[-1]
    assert metodo == "DefinirMyContatoAtivo"
    assert (req.id, req.ativo) == (546, False)
    assert "restaurar_contato" in r


async def test_nome_de_outro_contato_nao_confirma():
    servidor, cliente = _montar()
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["excluir_contato"](contato_id=546, confirmar="Outro")
    assert "DefinirMyContatoAtivo" not in cliente.metodos


async def test_excluir_atendimento_confirma_pelo_contato_e_desativa():
    servidor, cliente = _montar()
    with como(ADMIN):
        simulado = await servidor.funcoes["excluir_atendimento"](
            atendimento_id=463, dry_run=True
        )
        assert "Paulo W" in simulado
        with pytest.raises(ToolError):
            await servidor.funcoes["excluir_atendimento"](
                atendimento_id=463, confirmar="errado"
            )
        await servidor.funcoes["excluir_atendimento"](
            atendimento_id=463, confirmar="Paulo W"
        )

    metodo, req, _ = cliente.chamadas[-1]
    assert metodo == "DefinirMyAtendimentoAtivo"
    assert (req.atendimento_id, req.ativo) == (463, False)
