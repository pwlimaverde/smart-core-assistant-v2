"""Caminho felizado das tools de configuração e destrutivas.

O `test_guards.py` cobre as recusas — escopo, confirmação, `dry_run`, rate limit.
Aqui está o oposto: o que acontece quando **tudo está certo**. Vale testar porque
é onde mora a conversão de argumento para mensagem protobuf, e um campo trocado
ali não falha: grava a coisa errada em silêncio.
"""

from __future__ import annotations

import os

import pytest
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import configuracao, destrutivas  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]


# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------


async def test_create_departamento_manda_nome_e_descricao():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "CreateMyDepartamento": pb.CreateMyDepartamentoResponse(
                id=4, nome="Comercial"
            )
        }
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        r = await servidor.funcoes["create_departamento"](
            nome="Comercial", descricao="Vendas e propostas"
        )

    assert "Comercial" in r and "4" in r
    _, req, _ = cliente.chamadas[-1]
    assert req.nome == "Comercial"
    assert req.descricao == "Vendas e propostas"


async def test_create_fluxo_amarra_o_departamento_informado():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "CreateMyFluxo": pb.MyFluxoResponse(
                fluxo=pb.MyFluxo(id=9, nome="Funil de Vendas")
            )
        }
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        r = await servidor.funcoes["create_fluxo"](
            departamento_id=4, nome="Funil de Vendas"
        )

    assert "Funil de Vendas" in r and "9" in r
    _, req, _ = cliente.chamadas[-1]
    assert req.departamento_id == 4


async def test_create_etapa_usa_o_tipo_informado_e_nao_um_default_silencioso():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "CreateMyEtapaFluxo": pb.MyEtapaFluxoResponse(
                etapa=pb.MyEtapaFluxo(id=2, nome="Proposta enviada")
            )
        }
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["create_etapa_fluxo"](
            fluxo_id=9, nome="Proposta enviada", tipo_etapa="final", cor="#2E7D32"
        )

    _, req, _ = cliente.chamadas[-1]
    assert req.fluxo_id == 9
    assert req.tipo_etapa == "final"
    assert req.cor == "#2E7D32"


async def test_mover_etapa_respeita_a_direcao():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"MoverMyEtapaFluxo": pb.SimpleOkResponse(sucesso=True)}
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["mover_etapa_fluxo"](etapa_id=2, para_cima=True)

    _, req, _ = cliente.chamadas[-1]
    assert req.para_cima is True


async def test_create_treinamento_avisa_que_falta_finalizar():
    """O conteúdo só vale nas respostas depois de finalizado e vetorizado.

    Sem esta frase no retorno, o agente relata "treinamento criado" e quem pediu
    acha que o assistente já sabe o assunto.
    """
    servidor, registro, executor, _, _ = montar_ambiente(
        {
            "CreateMyTreinamento": pb.MyTreinamentoResponse(
                treinamento=pb.MyTreinamento(id=3, tag="politica-troca")
            )
        }
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        r = await servidor.funcoes["create_treinamento"](
            tag="politica-troca", conteudo="Trocas em até 7 dias."
        )

    assert "finalizado" in r


async def test_set_bot_persona_substitui_e_manda_o_nome_do_agente():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"SetMyBotPersona": pb.SetMyBotPersonaResponse(success=True)}
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["set_bot_persona"](
            persona="Atendente objetivo e cordial.", nome_do_agente="Ana"
        )

    _, req, _ = cliente.chamadas[-1]
    assert req.persona_bot == "Atendente objetivo e cordial."
    assert req.bot_agent_name == "Ana"


async def test_create_atendente_leva_departamento_e_fluxo():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "CreateMyAtendente": pb.MyAtendenteResponse(
                atendente=pb.MyAtendente(id=11, nome="João")
            )
        }
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["create_atendente"](
            nome="João", email="joao@exemplo.com", departamento_id=4, fluxo_id=9
        )

    _, req, _ = cliente.chamadas[-1]
    assert req.departamento_id == 4
    assert req.fluxo_id == 9


async def test_update_departamento_exige_os_campos_porque_substitui():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"UpdateMyDepartamento": pb.SimpleOkResponse(sucesso=True)}
    )
    configuracao.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["update_departamento"](
            departamento_id=4, nome="Comercial B2B", descricao="Contas grandes"
        )

    _, req, _ = cliente.chamadas[-1]
    assert req.id == 4
    assert req.nome == "Comercial B2B"
    assert req.ativo is True


# ---------------------------------------------------------------------------
# Destrutivas — o alvo é resolvido NO SERVIDOR
# ---------------------------------------------------------------------------


async def test_desativar_fluxo_com_confirmacao_correta_executa():
    fluxos = pb.ListMyFluxosResponse(
        fluxos=[pb.MyFluxo(id=3, nome="Funil de Vendas", atendimentos_abertos=12)]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"ListMyFluxos": fluxos, "DesativarMyFluxo": pb.SimpleOkResponse(sucesso=True)}
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        r = await servidor.funcoes["desativar_fluxo"](
            fluxo_id=3, confirmar="Funil de Vendas"
        )

    assert "desativado" in r
    assert "DesativarMyFluxo" in cliente.metodos


async def test_desativar_fluxo_inexistente_ensina_a_listar():
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"ListMyFluxos": pb.ListMyFluxosResponse(fluxos=[])}
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN), pytest.raises(ToolError, match="não existe"):
        await servidor.funcoes["desativar_fluxo"](fluxo_id=404, confirmar="qualquer")

    assert "DesativarMyFluxo" not in cliente.metodos


async def test_desativar_departamento_casa_com_o_nome_real():
    deps = pb.ListMyDepartamentosResponse(
        departamentos=[pb.MyDepartamento(id=4, nome="Comercial")]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListMyDepartamentos": deps,
            "DesativarMyDepartamento": pb.SimpleOkResponse(sucesso=True),
        }
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["desativar_departamento"](
            departamento_id=4, confirmar="Comercial"
        )
    assert "DesativarMyDepartamento" in cliente.metodos

    # E o nome errado não passa, mesmo com o id certo.
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["desativar_departamento"](
            departamento_id=4, confirmar="Comercia"
        )


async def test_desativar_atendente_resolve_pelo_nome():
    atendentes = pb.ListMyAtendentesResponse(
        atendentes=[pb.MyAtendente(id=11, nome="João Silva")]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListMyAtendentes": atendentes,
            "DesativarMyAtendente": pb.SimpleOkResponse(sucesso=True),
        }
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["desativar_atendente"](
            atendente_id=11, confirmar="João Silva"
        )
    assert "DesativarMyAtendente" in cliente.metodos


async def test_remover_treinamento_confirma_pela_tag():
    treinos = pb.ListMyTreinamentosResponse(
        treinamentos=[pb.MyTreinamento(id=3, tag="politica-troca")]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListMyTreinamentos": treinos,
            "RemoverMyTreinamento": pb.SimpleOkResponse(sucesso=True),
        }
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        r = await servidor.funcoes["remover_treinamento"](
            treinamento_id=3, confirmar="politica-troca"
        )

    assert "politica-troca" in r
    assert "RemoverMyTreinamento" in cliente.metodos


async def test_desativar_etapa_resolve_dentro_do_fluxo_informado():
    etapas = pb.ListMyEtapasFluxoResponse(
        etapas=[pb.MyEtapaFluxo(id=2, nome="Proposta enviada")]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListMyEtapasFluxo": etapas,
            "DesativarMyEtapaFluxo": pb.SimpleOkResponse(sucesso=True),
        }
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        await servidor.funcoes["desativar_etapa_fluxo"](
            fluxo_id=9, etapa_id=2, confirmar="Proposta enviada"
        )
    assert "DesativarMyEtapaFluxo" in cliente.metodos


async def test_remover_conexao_avisa_do_qr_code_no_dry_run_e_no_sucesso():
    """A ação mais grave do servidor. O aviso do QR Code não é detalhe.

    Quem remove uma conexão achando que está "reiniciando" descobre o custo
    quando precisa do celular de volta.
    """
    instancias = pb.ListMyWhatsappInstancesResponse(
        instancias=[pb.MyWhatsappInstance(id=7, name="Comercial")]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListMyWhatsappInstances": instancias,
            "DeleteMyWhatsappInstance": pb.SimpleOkResponse(sucesso=True),
        }
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(ADMIN):
        simulado = await servidor.funcoes["remover_conexao_whatsapp"](
            conexao_id=7, dry_run=True
        )
        assert "QR Code" in simulado
        assert "DeleteMyWhatsappInstance" not in cliente.metodos

        feito = await servidor.funcoes["remover_conexao_whatsapp"](
            conexao_id=7, confirmar="Comercial"
        )

    assert "QR Code" in feito
    assert "DeleteMyWhatsappInstance" in cliente.metodos


async def test_toda_destrutiva_recusa_sem_confirmacao():
    """Varredura: nenhuma tool destrutiva pode agir sem confirmação.

    Um teste por tool seria mais legível, mas este pega a tool NOVA que alguém
    acrescentar sem lembrar do guard — que é o caso que importa.
    """
    respostas = {
        "ListMyFluxos": pb.ListMyFluxosResponse(fluxos=[pb.MyFluxo(id=1, nome="F")]),
        "ListMyEtapasFluxo": pb.ListMyEtapasFluxoResponse(
            etapas=[pb.MyEtapaFluxo(id=1, nome="E")]
        ),
        "ListMyDepartamentos": pb.ListMyDepartamentosResponse(
            departamentos=[pb.MyDepartamento(id=1, nome="D")]
        ),
        "ListMyAtendentes": pb.ListMyAtendentesResponse(
            atendentes=[pb.MyAtendente(id=1, nome="A")]
        ),
        "ListMyTreinamentos": pb.ListMyTreinamentosResponse(
            treinamentos=[pb.MyTreinamento(id=1, tag="T")]
        ),
        "ListMyWhatsappInstances": pb.ListMyWhatsappInstancesResponse(
            instancias=[pb.MyWhatsappInstance(id=1, name="C")]
        ),
    }
    servidor, registro, executor, cliente, _ = montar_ambiente(respostas)
    destrutivas.registrar(servidor, registro, executor)

    argumentos = {
        "desativar_fluxo": {"fluxo_id": 1},
        "desativar_etapa_fluxo": {"fluxo_id": 1, "etapa_id": 1},
        "desativar_departamento": {"departamento_id": 1},
        "desativar_atendente": {"atendente_id": 1},
        "remover_treinamento": {"treinamento_id": 1},
        "remover_conexao_whatsapp": {"conexao_id": 1},
    }
    destrutivas_registradas = [
        r.nome for r in registro.todos() if r.categoria.value == "destrutiva"
    ]
    assert set(argumentos) == set(destrutivas_registradas), (
        "tool destrutiva sem cobertura neste teste: "
        f"{set(destrutivas_registradas) - set(argumentos)}"
    )

    for nome, args in argumentos.items():
        with como(ADMIN), pytest.raises(ToolError, match="confirmação"):
            await servidor.funcoes[nome](**args)

    # Nenhuma escrita chegou ao backend — só as leituras que resolvem o alvo.
    escritas = [m for m in cliente.metodos if not m.startswith("List")]
    assert escritas == []
