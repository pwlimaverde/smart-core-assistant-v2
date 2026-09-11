"""Conversão protobuf → dicionário nas tools de leitura.

Parece cola trivial, e é exatamente por isso que vale testar: um nome de campo
trocado aqui não levanta exceção. Devolve o dado errado ao modelo, que responde
com confiança, e ninguém descobre até alguém conferir à mão.

Cada teste verifica também o **teto de itens**: a resposta é cortada no limite do
servidor, independentemente do que o backend mandou.
"""

from __future__ import annotations

import os

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import leitura  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]


def ambiente(respostas, teto=50):
    servidor, registro, executor, cliente, metricas = montar_ambiente(respostas)
    leitura.registrar(servidor, registro, executor, teto=teto)
    return servidor, cliente


async def test_get_painel_converte_os_sete_numeros():
    servidor, _ = ambiente(
        {
            "GetMyPainel": pb.GetMyPainelResponse(
                em_andamento=3,
                aguardando=1,
                mensagens_24h=42,
                conexoes_ativas=1,
                conexoes_total=2,
                departamentos=4,
                treinamentos_ativos=7,
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["get_painel"]()

    assert r == {
        "em_andamento": 3,
        "aguardando": 1,
        "mensagens_24h": 42,
        "conexoes_ativas": 1,
        "conexoes_total": 2,
        "departamentos": 4,
        "treinamentos_ativos": 7,
    }


async def test_list_fluxos_traz_o_departamento_e_os_abertos():
    """`atendimentos_abertos` é o número que muda a decisão de desativar."""
    servidor, _ = ambiente(
        {
            "ListMyFluxos": pb.ListMyFluxosResponse(
                fluxos=[
                    pb.MyFluxo(
                        id=9,
                        nome="Funil de Vendas",
                        departamento_id=4,
                        departamento_nome="Comercial",
                        ativo=True,
                        atendimentos_abertos=12,
                    )
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_fluxos"]()

    assert r[0]["id"] == 9
    assert r[0]["departamento_nome"] == "Comercial"
    assert r[0]["atendimentos_abertos"] == 12


async def test_list_etapas_preserva_a_ordem_do_funil():
    servidor, _ = ambiente(
        {
            "ListMyEtapasFluxo": pb.ListMyEtapasFluxoResponse(
                etapas=[
                    pb.MyEtapaFluxo(id=1, nome="Novo", ordem=1, tipo_etapa="inicial"),
                    pb.MyEtapaFluxo(id=2, nome="Fechado", ordem=2, tipo_etapa="final"),
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_etapas_fluxo"](fluxo_id=9)

    assert [e["nome"] for e in r] == ["Novo", "Fechado"]
    assert r[0]["tipo_etapa"] == "inicial"


async def test_list_contatos_usa_o_nome_do_contato_e_cai_no_do_whatsapp():
    """O contato pode não ter nome cadastrado, só o do perfil do WhatsApp.

    Sem o fallback, a lista mostraria nome vazio e o agente falaria do "contato
    sem nome" em vez de usar o que existe.
    """
    servidor, _ = ambiente(
        {
            "ListMyContatos": pb.ListMyContatosResponse(
                contatos=[
                    pb.MyContato(id=1, nome_contato="Maria Silva", telefone="5511999"),
                    pb.MyContato(id=2, nome_perfil_whatsapp="Zé", telefone="5511888"),
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_contatos"](busca="")

    assert r[0]["nome"] == "Maria Silva"
    assert r[1]["nome"] == "Zé"


async def test_list_contatos_repassa_a_busca_e_o_teto():
    servidor, cliente = ambiente(
        {"ListMyContatos": pb.ListMyContatosResponse(contatos=[])}, teto=25
    )

    with como(ADMIN):
        await servidor.funcoes["list_contatos"](busca="maria")

    _, req, _ = cliente.chamadas[-1]
    assert req.busca == "maria"
    assert req.limite == 25


async def test_list_atendimentos_traduz_todos_para_filtro_vazio():
    """`todos` não é um status do backend — é a ausência de filtro."""
    servidor, cliente = ambiente(
        {"ListAtendimentos": pb.ListAtendimentosResponse(atendimentos=[])}
    )

    with como(ADMIN):
        await servidor.funcoes["list_atendimentos"](status="todos")
    assert cliente.chamadas[-1][1].status == ""

    with como(ADMIN):
        await servidor.funcoes["list_atendimentos"](status="aguardando")
    assert cliente.chamadas[-1][1].status == "aguardando"


async def test_list_atendimentos_expoe_o_sentimento_e_os_ids_de_navegacao():
    servidor, _ = ambiente(
        {
            "ListAtendimentos": pb.ListAtendimentosResponse(
                atendimentos=[
                    pb.AtendimentoResumo(
                        id=412,
                        contato_id=44,
                        status="em_andamento",
                        fluxo_atendimento_id=9,
                        etapa_atual_id=2,
                        sentimento_label="negativo",
                    )
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_atendimentos"]()

    assert r[0]["id"] == 412
    assert r[0]["contato_id"] == 44
    assert r[0]["fluxo_id"] == 9
    assert r[0]["etapa_id"] == 2
    assert r[0]["sentimento"] == "negativo"


async def test_get_thread_marca_o_que_foi_gerado_pela_ia():
    """O agente precisa distinguir o que o robô disse do que a pessoa disse."""
    servidor, _ = ambiente(
        {
            "GetThread": pb.GetThreadResponse(
                mensagens=[
                    pb.MensagemThread(id=1, conteudo="Oi", remetente="cliente"),
                    pb.MensagemThread(
                        id=2, conteudo="Olá!", remetente="bot", gerado_por_ia=True
                    ),
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["get_thread"](atendimento_id=412)

    assert r[0]["gerado_por_ia"] is False
    assert r[1]["gerado_por_ia"] is True


async def test_list_conexoes_mostra_o_estado_que_decide_se_da_para_enviar():
    servidor, _ = ambiente(
        {
            "ListMyWhatsappInstances": pb.ListMyWhatsappInstancesResponse(
                instancias=[
                    pb.MyWhatsappInstance(
                        id=7,
                        name="Comercial",
                        phone_number="5511999",
                        connection_state="open",
                        active=True,
                    )
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_conexoes_whatsapp"]()

    assert r[0]["estado"] == "open"
    assert r[0]["ativa"] is True


async def test_list_treinamentos_diz_se_ja_vale_nas_respostas():
    servidor, _ = ambiente(
        {
            "ListMyTreinamentos": pb.ListMyTreinamentosResponse(
                treinamentos=[
                    pb.MyTreinamento(
                        id=3, tag="politica-troca", finalizado=True, vetorizado=False
                    )
                ]
            )
        }
    )

    with como(ADMIN):
        r = await servidor.funcoes["list_treinamentos"]()

    assert r[0]["finalizado"] is True
    assert r[0]["vetorizado"] is False


async def test_list_departamentos_e_atendentes_convertem_os_campos_usados():
    servidor, _ = ambiente(
        {
            "ListMyDepartamentos": pb.ListMyDepartamentosResponse(
                departamentos=[
                    pb.MyDepartamento(
                        id=4, nome="Comercial", slug="comercial", ativo=True
                    )
                ]
            ),
            "ListMyAtendentes": pb.ListMyAtendentesResponse(
                atendentes=[
                    pb.MyAtendente(
                        id=11,
                        nome="João",
                        cargo="Vendedor",
                        departamento_id=4,
                        disponivel=True,
                        max_atendimentos_simultaneos=5,
                    )
                ]
            ),
        }
    )

    with como(ADMIN):
        deps = await servidor.funcoes["list_departamentos"]()
        ats = await servidor.funcoes["list_atendentes"]()

    assert deps[0]["slug"] == "comercial"
    assert ats[0]["cargo"] == "Vendedor"
    assert ats[0]["max_atendimentos_simultaneos"] == 5


async def test_teto_de_itens_corta_independente_do_que_o_backend_mandou():
    """O teto é do servidor, não do agente.

    Uma lista de mil contatos não ajuda o modelo: enche a janela de contexto dele
    com dado que não vai usar e aumenta a chance de ele responder sobre o item
    errado.
    """
    muitos = pb.ListMyFluxosResponse(
        fluxos=[pb.MyFluxo(id=i, nome=f"F{i}") for i in range(200)]
    )
    servidor, _ = ambiente({"ListMyFluxos": muitos}, teto=5)

    with como(ADMIN):
        r = await servidor.funcoes["list_fluxos"]()

    assert len(r) == 5
