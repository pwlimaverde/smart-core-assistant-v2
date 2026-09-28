"""Transferência para atendente (plano ia-engine-jev): o agente faz o que a tela
faz, simula antes, não duplica regra e só desativa com o nome confirmado."""

from __future__ import annotations

import os

import pytest
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import transferencia  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]

REGRA = pb.RegraTransferencia(
    id=7,
    nome="Fechar pedido",
    gatilho_tipo="condicao",
    condicao="o cliente quer fechar o pedido",
    exemplos_sim=["pode fechar"],
    momento="imediato",
    destino_tipo="padrao",
    sensibilidade="media",
    ativa=False,
)


def _montar():
    servidor, registro, executor, cliente, metricas = montar_ambiente(
        {
            "ListMyRegrasTransferencia": pb.ListMyRegrasTransferenciaResponse(
                regras=[REGRA]
            ),
            "SalvarMyRegraTransferencia": pb.SalvarMyRegraTransferenciaResponse(
                regra=REGRA, campos_alterados=["condicao"]
            ),
            "SetMyRegraTransferenciaAtiva": pb.SetMyRegraTransferenciaAtivaResponse(
                regra=REGRA
            ),
            "GetMyConfigTransferencia": pb.ConfigTransferenciaResponse(
                config=pb.ConfigTransferencia(
                    sinais=[
                        pb.SinalTransferencia(
                            nome="irritacao", ativo=True, sensibilidade="media"
                        )
                    ],
                    motor_analise="sombra",
                )
            ),
            "SetMySinaisTransferencia": pb.ConfigTransferenciaResponse(
                config=pb.ConfigTransferencia(motor_analise="sombra")
            ),
            "ListMyTransferencias": pb.ListMyTransferenciasResponse(
                transferencias=[
                    pb.TransferenciaIa(id=1, motivo="regra:Fechar pedido", fluxo_id=3)
                ]
            ),
            "TestarMyRegraTransferencia": pb.TestarMyRegraTransferenciaResponse(
                probabilidade=0.91, limiar=0.8, dispararia=True, modelo="jev-1.13.0"
            ),
            "GerarMySugestoesTransferencia": pb.GerarMySugestoesTransferenciaResponse(
                criadas=3
            ),
        }
    )
    transferencia.registrar(servidor, registro, executor)
    return servidor, cliente


async def test_leituras():
    servidor, cliente = _montar()
    with como(ADMIN):
        cfg = await servidor.funcoes["get_config_transferencia"]()
        regras = await servidor.funcoes["list_regras_transferencia"]()
        transf = await servidor.funcoes["list_transferencias"]()
    assert cfg["motor_analise"] == "sombra"
    assert regras[0]["nome"] == "Fechar pedido"
    assert transf[0]["motivo"] == "regra:Fechar pedido"


async def test_criar_duplicada_nao_chega_ao_servidor():
    servidor, cliente = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["create_regra_transferencia"](
            nome=" fechar PEDIDO ",
            gatilho_tipo="condicao",
            condicao="o cliente quer fechar o pedido",
            dry_run=True,
        )
        with pytest.raises(ToolError):
            await servidor.funcoes["create_regra_transferencia"](
                nome="Fechar pedido",
                gatilho_tipo="condicao",
                condicao="o cliente quer fechar o pedido",
            )
    assert "nada" in r
    assert "SalvarMyRegraTransferencia" not in cliente.metodos


async def test_criar_simula_no_servidor_e_depois_cria():
    servidor, cliente = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["create_regra_transferencia"](
            nome="Reclamação",
            gatilho_tipo="condicao",
            condicao="o cliente reclama de um pedido entregue",
            exemplos_sim=["veio errado"],
            dry_run=True,
        )
        assert "SIMULAÇÃO" in r and "INATIVA" in r
        _, req, _ = cliente.chamadas[-1]
        assert req.dry_run is True and req.regra.exemplos_sim == ["veio errado"]
        await servidor.funcoes["create_regra_transferencia"](
            nome="Reclamação",
            gatilho_tipo="condicao",
            condicao="o cliente reclama de um pedido entregue",
        )
    _, req, _ = cliente.chamadas[-1]
    assert req.dry_run is False and req.id == 0


async def test_update_muda_so_o_pedido():
    servidor, cliente = _montar()
    with como(ADMIN):
        await servidor.funcoes["update_regra_transferencia"](
            regra_id=7, condicao="o cliente quer confirmar o pedido"
        )
    metodo, req, _ = cliente.chamadas[-1]
    assert metodo == "SalvarMyRegraTransferencia"
    assert req.id == 7
    assert req.regra.condicao == "o cliente quer confirmar o pedido"
    assert req.regra.exemplos_sim == ["pode fechar"]
    assert req.regra.nome == "Fechar pedido"


async def test_update_de_regra_inexistente():
    servidor, _ = _montar()
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["update_regra_transferencia"](regra_id=99, nome="x")


async def test_desativar_exige_o_nome():
    servidor, cliente = _montar()
    with como(ADMIN):
        simulado = await servidor.funcoes["desativar_regra_transferencia"](
            regra_id=7, dry_run=True
        )
        assert "confirmar='Fechar pedido'" in simulado
        with pytest.raises(ToolError):
            await servidor.funcoes["desativar_regra_transferencia"](regra_id=7)
        await servidor.funcoes["desativar_regra_transferencia"](
            regra_id=7, confirmar="Fechar pedido"
        )
    _, req, _ = cliente.chamadas[-1]
    assert req.ativa is False and req.confirmar == "Fechar pedido"


async def test_ativar_e_sinais():
    servidor, cliente = _montar()
    with como(ADMIN):
        await servidor.funcoes["ativar_regra_transferencia"](regra_id=7)
        _, req, _ = cliente.chamadas[-1]
        assert req.ativa is True
        await servidor.funcoes["set_sinais_transferencia"](
            sinal="irritacao", sensibilidade="alta"
        )
        _, req, _ = cliente.chamadas[-1]
        assert req.sinais[0].nome == "irritacao"
        assert req.sinais[0].ativo is True  # preservado do atual
        assert req.sinais[0].sensibilidade == "alta"
        assert req.alterar_fluxo_padrao is False
        await servidor.funcoes["set_sinais_transferencia"](fluxo_padrao_id=0)
        _, req, _ = cliente.chamadas[-1]
        assert req.alterar_fluxo_padrao is True and req.fluxo_padrao_id == 0
        with pytest.raises(ToolError):
            await servidor.funcoes["set_sinais_transferencia"]()


async def test_testar_regra_e_sugestoes():
    servidor, cliente = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["testar_regra_transferencia"](
            frase="pode fechar", condicao="o cliente quer fechar o pedido"
        )
        assert r["dispararia"] is True
        _, req, _ = cliente.chamadas[-1]
        assert req.regra.condicao == "o cliente quer fechar o pedido"
        with pytest.raises(ToolError):
            await servidor.funcoes["testar_regra_transferencia"](frase="oi")
        s = await servidor.funcoes["gerar_sugestoes_transferencia"]()
    assert "3 sugestão" in s
