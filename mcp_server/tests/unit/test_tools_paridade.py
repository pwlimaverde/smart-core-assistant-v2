"""Paridade com o app: as tools que cobrem tudo o que o usuário manipula.

Uma tabela de casos, e não um teste por tool: o que importa verificar em cada
uma é a mesma coisa — o argumento vira o campo certo da mensagem protobuf, e o
RPC chamado é o certo. Um campo trocado aqui não falha: grava a coisa errada em
silêncio.
"""

from __future__ import annotations

import base64
import inspect
import json
import os
from typing import Any

import pytest
from google.protobuf import message_factory
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import (  # noqa: E402
    atendimento,
    cadastros,
    configuracao_tenant,
    equipe_whatsapp,
    leitura,
    treinamento_ia,
)
from mcp_server.tools.base import decodificar_arquivo, para_dict  # noqa: E402
from tests.conftest import como  # noqa: E402
from tests.unit.test_guards import montar_ambiente  # noqa: E402

ADMIN = ["tenant:admin"]
PDF_B64 = base64.b64encode(b"%PDF-1.4 teste").decode()
PNG_B64 = base64.b64encode(b"\x89PNG\r\n\x1a\n").decode()


def _saida_do_rpc(metodo: str) -> Any:
    """Instância vazia do tipo de resposta de um RPC, lida do descritor."""
    servico = pb.DESCRIPTOR.services_by_name["AdminService"]
    return message_factory.GetMessageClass(
        servico.methods_by_name[metodo].output_type
    )()


class Respostas(dict):
    """Responde a qualquer RPC com o tipo certo; os preenchidos têm dados."""

    def __contains__(self, metodo: object) -> bool:
        return True

    def __getitem__(self, metodo: str) -> Any:
        if dict.__contains__(self, metodo):
            return dict.__getitem__(self, metodo)
        return _saida_do_rpc(metodo)


def _respostas() -> Respostas:
    r = Respostas()
    r.update(
        {
            "GetDetalheAtendimento": pb.DetalheAtendimentoResponse(
                catalogo=[pb.Etiqueta(id=3, nome="VIP")],
                notas=[pb.Nota(id=9, texto="ligar")],
            ),
            "ObterContatoDoAtendimento": pb.ObterContatoDoAtendimentoResponse(
                contato_id=5
            ),
            "SolicitarUploadMidia": pb.SolicitarUploadMidiaResponse(
                url_upload="https://r2/upload",
                chave="k1",
                content_type="application/pdf",
            ),
            "SolicitarUploadTreinamento": pb.SolicitarUploadTreinamentoResponse(
                url_upload="https://r2/treino",
                chave="k2",
                content_type="application/pdf",
            ),
            "ListMyCampos": pb.ListMyCamposResponse(
                campos=[pb.MyCampoPersonalizado(id=4, nome="Tamanho")]
            ),
            "ListMyIntents": pb.ListMyIntentsResponse(
                intents=[pb.MyIntent(id=2, tag="saudacao", grupo="basico")]
            ),
            "ListInvites": pb.ListInvitesResponse(
                invites=[pb.TenantInviteItem(id="c1", email="a@b.com")]
            ),
            "ListMyWhatsappInstances": pb.ListMyWhatsappInstancesResponse(
                instancias=[pb.MyWhatsappInstance(id=1, name="Comercial")]
            ),
            "ListMyMensagensNaoEntregues": pb.ListMyMensagensNaoEntreguesResponse(
                itens=[pb.MensagemNaoEntregue(id=1, atendimento_id=7)]
            ),
            "ListMyAtendentes": pb.ListMyAtendentesResponse(
                atendentes=[
                    pb.MyAtendente(
                        id=2,
                        nome="Paulo",
                        cargo="Vendedor",
                        departamento_id=416,
                        fluxo_id=301,
                        ativo=True,
                    )
                ]
            ),
            "ListMyNumerosIgnorados": pb.ListMyNumerosIgnoradosResponse(
                itens=[pb.MyNumeroIgnorado(id=1, telefone="558599")]
            ),
            "GetMyTenantConfig": pb.GetTenantConfigResponse(
                dados_empresa="Ecoprint",
                msg_fallback="volto já",
                api_keys=[
                    pb.ApiKeyEntry(key="openai_api_key", value="••••••••"),
                    pb.ApiKeyEntry(key="groq_api_key", value=""),
                ],
                prompts=[pb.PromptDoTenant(chave="PROMPT_X", texto="y")],
                analise_previa_habilitada=True,
            ),
            "GetMyWhatsappInstanceStatus": pb.GetMyWhatsappInstanceStatusResponse(
                connection_state="connecting",
                qr_code=f"data:image/png;base64,{PNG_B64}",
            ),
        }
    )
    return r


def _montar() -> tuple[Any, Any, list[tuple[str, str, bytes]]]:
    servidor, registro, executor, cliente, _ = montar_ambiente(_respostas())
    enviados: list[tuple[str, str, bytes]] = []

    async def enviador(url: str, ct: str, dados: bytes) -> None:
        enviados.append((url, ct, dados))

    executor.enviador = enviador
    for modulo in (
        leitura,
        configuracao_tenant,
        cadastros,
        treinamento_ia,
        atendimento,
        equipe_whatsapp,
    ):
        modulo.registrar(servidor, registro, executor)
    return servidor, cliente, enviados


# (tool, argumentos, RPC que deve ser o último chamado, campos esperados no pedido)
CASOS: list[tuple[str, dict[str, Any], str, dict[str, Any]]] = [
    # atendimento — leitura
    (
        "get_ficha_atendimento",
        {"atendimento_id": 7},
        "GetDetalheAtendimento",
        {"atendimento_id": 7},
    ),
    (
        "list_timeline_atendimento",
        {"atendimento_id": 7},
        "ListarTimelineAtendimento",
        {"atendimento_id": 7},
    ),
    (
        "list_atendimentos_do_contato",
        {"contato_id": 5},
        "ListarAtendimentosDoContato",
        {"contato_id": 5},
    ),
    (
        "list_midias_atendimento",
        {"atendimento_id": 7},
        "ListarMidiasAtendimento",
        {"atendimento_id": 7},
    ),
    (
        "get_contato_do_atendimento",
        {"atendimento_id": 7},
        "ObterContatoDoAtendimento",
        {"atendimento_id": 7},
    ),
    ("exportar_quadro", {"busca": "ana"}, "ExportarQuadro", {"busca": "ana"}),
    # atendimento — escrita
    (
        "iniciar_atendimento",
        {"contato_id": 5, "fluxo_id": 2, "etapa_inicial_id": 3},
        "IniciarAtendimentoManual",
        {"contato_id": 5, "etapa_inicial_id": 3},
    ),
    (
        "mover_atendimento_etapa",
        {"atendimento_id": 7, "etapa_destino_id": 4},
        "MoveAtendimentoEtapa",
        {"etapa_destino_id": 4},
    ),
    (
        "set_atendimento_status",
        {"atendimento_id": 7, "status": "resolvido"},
        "SetAtendimentoStatus",
        {"status": "resolvido"},
    ),
    (
        "atribuir_atendimento",
        {"atendimento_id": 7, "atendente_id": 2},
        "AtribuirAtendimento",
        {"atendente_id": 2},
    ),
    (
        "definir_prioridade",
        {"atendimento_id": 7, "prioridade": "alta"},
        "DefinirPrioridade",
        {"prioridade": "alta"},
    ),
    (
        "transferir_para_fluxo",
        {"atendimento_id": 7, "fluxo_id": 2},
        "TransferirParaFluxo",
        {"fluxo_id": 2},
    ),
    (
        "marcar_atendimento_lido",
        {"atendimento_id": 7},
        "MarcarAtendimentoLido",
        {"atendimento_id": 7},
    ),
    ("marcar_revisado", {"atendimento_id": 7}, "MarcarRevisado", {"atendimento_id": 7}),
    (
        "definir_bot_da_conversa",
        {"atendimento_id": 7, "habilitado": True},
        "DefinirBotDaConversa",
        {"habilitado": True},
    ),
    (
        "create_nota",
        {"atendimento_id": 7, "texto": "ligar"},
        "CreateNota",
        {"texto": "ligar"},
    ),
    (
        "remover_nota",
        {"atendimento_id": 7, "nota_id": 9, "confirmar": "9"},
        "RemoverNota",
        {"nota_id": 9},
    ),
    (
        "create_etiqueta",
        {"nome": "VIP", "cor": "#ff0000"},
        "CreateEtiqueta",
        {"nome": "VIP"},
    ),
    (
        "update_etiqueta",
        {"etiqueta_id": 3, "nome": "VIP+"},
        "UpdateEtiqueta",
        {"id": 3, "nome": "VIP+"},
    ),
    (
        "desativar_etiqueta",
        {"etiqueta_id": 3, "atendimento_id": 7, "confirmar": "VIP"},
        "DesativarEtiqueta",
        {"id": 3},
    ),
    (
        "aplicar_etiqueta",
        {"atendimento_id": 7, "etiqueta_id": 3, "aplicar": False},
        "AlternarEtiqueta",
        {"aplicar": False},
    ),
    (
        "set_valor_campo",
        {"atendimento_id": 7, "campo_id": 4, "valor_json": '"A4"'},
        "SetMyValorCampo",
        {"valor_json": '"A4"'},
    ),
    (
        "send_media",
        {
            "atendimento_id": 7,
            "nome_arquivo": "a.pdf",
            "mimetype": "application/pdf",
            "conteudo_base64": PDF_B64,
            "confirmar": "5",
        },
        "EnviarMidiaAtendimento",
        {"chave": "k1"},
    ),
    # cadastros
    (
        "create_contato",
        {"telefone": "5585", "nome": "Ana"},
        "CreateMyContato",
        {"nome_contato": "Ana"},
    ),
    (
        "update_contato",
        {"contato_id": 5, "nome": "Ana", "telefone": "5585"},
        "UpdateMyContato",
        {"id": 5},
    ),
    (
        "definir_contato_ativo",
        {"contato_id": 5, "ativo": False},
        "DefinirMyContatoAtivo",
        {"ativo": False},
    ),
    ("list_clientes", {"busca": "eco"}, "ListMyClientes", {"busca": "eco"}),
    (
        "create_cliente",
        {"nome_fantasia": "Eco", "tipo": "pj", "cidade": "Fortaleza"},
        "CreateMyCliente",
        {},
    ),
    (
        "update_cliente",
        {"cliente_id": 1, "nome_fantasia": "Eco"},
        "UpdateMyCliente",
        {"id": 1},
    ),
    (
        "definir_cliente_ativo",
        {"cliente_id": 1, "ativo": True},
        "DefinirMyClienteAtivo",
        {"ativo": True},
    ),
    (
        "list_contatos_do_cliente",
        {"cliente_id": 1},
        "ListMyContatosDoCliente",
        {"id": 1},
    ),
    (
        "vincular_contato_cliente",
        {"cliente_id": 1, "contato_id": 5},
        "VincularMyContatoCliente",
        {"vincular": True},
    ),
    ("list_campos", {}, "ListMyCampos", {}),
    (
        "create_campo",
        {"nome": "Tamanho", "tipo": "lista", "opcoes": ["A4", "A5"]},
        "CreateMyCampo",
        {"tipo": "lista"},
    ),
    ("update_campo", {"campo_id": 4, "nome": "Tamanho"}, "UpdateMyCampo", {"id": 4}),
    (
        "desativar_campo",
        {"campo_id": 4, "confirmar": "Tamanho"},
        "DesativarMyCampo",
        {"id": 4},
    ),
    (
        "update_etapa_fluxo",
        {"etapa_id": 3, "nome": "Proposta", "tipo_etapa": "trabalho"},
        "UpdateMyEtapaFluxo",
        {"tipo_etapa": "trabalho"},
    ),
    (
        "update_atendente",
        {"atendente_id": 2, "nome": "Paulo", "departamento_id": 1},
        "UpdateMyAtendente",
        {"departamento_id": 1},
    ),
    ("list_auditoria", {"origem": "mcp"}, "ListMyAuditLog", {"origem": "mcp"}),
    # treinamento da IA
    ("get_treinamento", {"treinamento_id": 3}, "GetMyTreinamento", {"id": 3}),
    (
        "create_treinamento_com_arquivo",
        {
            "tag": "tabela",
            "nome_arquivo": "t.pdf",
            "mimetype": "application/pdf",
            "conteudo_base64": PDF_B64,
        },
        "CreateMyTreinamentoComArquivo",
        {"chave": "k2"},
    ),
    ("list_intencoes", {}, "ListMyIntents", {}),
    (
        "create_intencao",
        {
            "tag": "saudacao",
            "grupo": "basico",
            "descricao": "d",
            "exemplo": "oi",
            "comportamento": "c",
        },
        "CreateMyIntent",
        {"tag": "saudacao"},
    ),
    (
        "update_intencao",
        {
            "intencao_id": 2,
            "tag": "t",
            "grupo": "g",
            "descricao": "d",
            "exemplo": "e",
            "comportamento": "c",
        },
        "UpdateMyIntent",
        {"id": 2},
    ),
    (
        "remover_intencao",
        {"intencao_id": 2, "confirmar": "saudacao"},
        "RemoveMyIntent",
        {"id": 2},
    ),
    (
        "testar_pergunta",
        {"pergunta": "quanto custa?"},
        "TestarPergunta",
        {"pergunta": "quanto custa?"},
    ),
    (
        "registrar_avaliacao_teste",
        {"pergunta": "p", "resposta_obtida": "r", "avaliacao": "ruim"},
        "RegistrarFeedbackTeste",
        {"avaliacao": "ruim"},
    ),
    ("list_avaliacoes_de_teste", {}, "ListMyAvaliacoesDeTeste", {}),
    (
        "marcar_avaliacao_tratada",
        {"avaliacao_id": 1, "virou_treinamento": True},
        "MarcarAvaliacaoTratada",
        {"virou_treinamento": True},
    ),
    # configuração do tenant
    (
        "update_config_avancada",
        {"timezone": "America/Fortaleza", "analise_previa_habilitada": False},
        "UpdateMyConfigAvancada",
        {"timezone": "America/Fortaleza", "analise_previa_habilitada": False},
    ),
    (
        "set_prompts",
        {
            "prompts": [
                configuracao_tenant.Prompt(chave="prompt_regras_resposta", texto="x")
            ]
        },
        "UpdateMyConfigAvancada",
        {},
    ),
    # equipe
    ("list_usuarios", {}, "ListTenantUsers", {}),
    (
        "update_usuario",
        {"user_id": 3, "papel": "viewer"},
        "UpdateTenantUser",
        {"set_role": True, "set_module_permissions": False},
    ),
    ("list_convites", {}, "ListInvites", {}),
    (
        "create_convite",
        {"email": "a@b.com", "nome": "Ana"},
        "CreateInvite",
        {"email": "a@b.com"},
    ),
    ("reenviar_convite", {"convite_id": "c1"}, "ReenviarConvite", {"invite_id": "c1"}),
    (
        "revogar_convite",
        {"convite_id": "c1", "confirmar": "a@b.com"},
        "RevokeInvite",
        {"invite_id": "c1"},
    ),
    # WhatsApp
    (
        "create_conexao_whatsapp",
        {"nome": "Comercial"},
        "CreateMyWhatsappInstance",
        {"instance_name": "Comercial"},
    ),
    ("get_detalhe_conexao_whatsapp", {"conexao_id": 1}, "DetalheDaConexao", {"id": 1}),
    (
        "reconectar_conexao_whatsapp",
        {"conexao_id": 1},
        "ReconnectMyWhatsappInstance",
        {"id": 1},
    ),
    (
        "desconectar_conexao_whatsapp",
        {"conexao_id": 1, "confirmar": "Comercial"},
        "DesconectarMyWhatsappInstance",
        {"id": 1},
    ),
    (
        "definir_resposta_bot_conexao",
        {"conexao_id": 1, "habilitado": True},
        "DefinirRespostaBotInstancia",
        {"habilitado": True},
    ),
    (
        "definir_departamento_da_conexao",
        {"conexao_id": 1, "departamento_id": 2},
        "DefinirDepartamentoDaConexao",
        {"departamento_id": 2},
    ),
    ("list_mensagens_nao_entregues", {}, "ListMyMensagensNaoEntregues", {}),
    (
        "reenviar_mensagem_nao_entregue",
        {"item_id": 1, "confirmar": "7"},
        "ReenviarMensagemNaoEntregue",
        {"id": 1},
    ),
    ("list_numeros_ignorados", {}, "ListMyNumerosIgnorados", {}),
    (
        "create_numero_ignorado",
        {"nome": "Mãe", "telefone": "5585"},
        "CriarNumeroIgnorado",
        {"telefone": "5585"},
    ),
    (
        "update_numero_ignorado",
        {"item_id": 1, "nome": "Mãe", "telefone": "5585"},
        "AtualizarNumeroIgnorado",
        {"id": 1},
    ),
    (
        "remover_numero_ignorado",
        {"item_id": 1, "confirmar": "558599"},
        "RemoverNumeroIgnorado",
        {"id": 1},
    ),
]


@pytest.mark.parametrize("nome,args,rpc,campos", CASOS, ids=[c[0] for c in CASOS])
async def test_tool_chama_o_rpc_certo_com_os_campos_certos(nome, args, rpc, campos):
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        resultado = await servidor.funcoes[nome](**args)

    assert resultado is not None
    metodo, req, _ = cliente.chamadas[-1]
    assert metodo == rpc
    for campo, esperado in campos.items():
        assert getattr(req, campo) == esperado, f"{nome}.{campo}"


@pytest.mark.parametrize("nome,args,rpc,_c", CASOS, ids=[c[0] for c in CASOS])
async def test_dry_run_nao_executa_a_escrita(nome, args, rpc, _c):
    servidor, cliente, enviados = _montar()
    fn = servidor.funcoes[nome]
    if "dry_run" not in inspect.signature(fn).parameters:
        pytest.skip("tool de leitura")
    with como(ADMIN):
        r = await fn(**{**args, "dry_run": True})

    assert "SIMULAÇÃO" in r
    assert rpc not in cliente.metodos
    assert enviados == []


async def test_send_media_sobe_o_arquivo_na_url_assinada_antes_de_enviar():
    servidor, cliente, enviados = _montar()
    with como(ADMIN):
        await servidor.funcoes["send_media"](
            atendimento_id=7,
            nome_arquivo="a.pdf",
            mimetype="application/pdf",
            conteudo_base64=f"data:application/pdf;base64,{PDF_B64}",
            confirmar="5",
        )
    assert enviados == [("https://r2/upload", "application/pdf", b"%PDF-1.4 teste")]
    assert cliente.metodos[-2:] == ["SolicitarUploadMidia", "EnviarMidiaAtendimento"]


async def test_send_media_recusa_confirmacao_de_outro_contato():
    servidor, cliente, enviados = _montar()
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["send_media"](
            atendimento_id=7,
            nome_arquivo="a.pdf",
            mimetype="application/pdf",
            conteudo_base64=PDF_B64,
            confirmar="999",
        )
    assert "EnviarMidiaAtendimento" not in cliente.metodos
    assert enviados == []


async def test_update_tenant_config_so_muda_o_pedido_e_preserva_o_resto():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        await servidor.funcoes["update_tenant_config"](msg_sem_info="não sei ainda")

    metodo, req, _ = cliente.chamadas[-1]
    assert metodo == "UpdateMyTenantConfig"
    assert req.msg_sem_info == "não sei ainda"
    # O que não foi pedido volta como estava — inclusive a chave mascarada,
    # que é o que o servidor lê como "manter".
    assert req.dados_empresa == "Ecoprint"
    assert req.msg_fallback == "volto já"
    chaves = {e.key: e.value for e in req.api_keys}
    assert chaves["openai_api_key"] == "••••••••"


async def test_update_tenant_config_sem_campo_e_recusado():
    servidor, _, _ = _montar()
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["update_tenant_config"]()


async def test_definir_chave_api_troca_so_a_chave_pedida():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        r = await servidor.funcoes["definir_chave_api"](provedor="groq", chave="gsk_x")

    assert "gsk_x" not in r
    _, req, _ = cliente.chamadas[-1]
    chaves = {e.key: e.value for e in req.api_keys}
    assert chaves == {"openai_api_key": "••••••••", "groq_api_key": "gsk_x"}


async def test_set_prompts_manda_chave_e_texto():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        await servidor.funcoes["set_prompts"](
            prompts=[configuracao_tenant.Prompt(chave="PROMPT_A", texto="")]
        )
    _, req, _ = cliente.chamadas[-1]
    assert [(p.chave, p.texto) for p in req.prompts] == [("PROMPT_A", "")]


async def test_config_avancada_sem_campo_e_recusada():
    servidor, _, _ = _montar()
    with como(ADMIN), pytest.raises(ToolError):
        await servidor.funcoes["update_config_avancada"]()


async def test_get_tenant_config_traz_prompts_e_o_que_herda_do_global():
    servidor, _, _ = _montar()
    with como(ADMIN):
        cfg = await servidor.funcoes["get_tenant_config"]()
    assert cfg["prompts_do_negocio"] == {"PROMPT_X": "y"}
    assert cfg["analise_previa_habilitada"] is True
    # Não configurado = herda o global: `None`, e não `False`.
    assert cfg["pesquisa_satisfacao_ativa"] is None
    assert cfg["provedores_configurados"] == ["openai_api_key"]


async def test_status_da_conexao_devolve_o_qr_como_imagem():
    servidor, _, _ = _montar()
    with como(ADMIN):
        saida = await servidor.funcoes["get_status_conexao_whatsapp"](conexao_id=1)
    assert "connecting" in saida[0]
    assert saida[-1].to_image_content().mime_type == "image/png"


async def test_alvo_inexistente_e_recusado_antes_de_agir():
    servidor, cliente, _ = _montar()
    casos = [
        ("desativar_etiqueta", {"etiqueta_id": 99, "atendimento_id": 7}),
        ("remover_nota", {"atendimento_id": 7, "nota_id": 99}),
        ("desativar_campo", {"campo_id": 99}),
        ("remover_intencao", {"intencao_id": 99}),
        ("revogar_convite", {"convite_id": "x"}),
        ("desconectar_conexao_whatsapp", {"conexao_id": 99}),
        ("reenviar_mensagem_nao_entregue", {"item_id": 99}),
        ("remover_numero_ignorado", {"item_id": 99}),
    ]
    for nome, args in casos:
        with como(ADMIN), pytest.raises(ToolError):
            await servidor.funcoes[nome](**args)


def test_decodificar_arquivo_ensina_o_formato():
    assert decodificar_arquivo(f"data:x;base64,{PDF_B64}") == b"%PDF-1.4 teste"
    for ruim in ("não é base64!", ""):
        with pytest.raises(ToolError):
            decodificar_arquivo(ruim)


def test_para_dict_inclui_campos_com_valor_padrao():
    d = para_dict(pb.MyContato(id=1, ativo=False))
    assert d["ativo"] is False
    assert d["id"] == 1


async def test_update_atendente_nao_zera_o_fluxo():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        await servidor.funcoes["update_atendente"](atendente_id=2, cargo="Gerente")
    _, req, _ = cliente.chamadas[-1]
    assert req.cargo == "Gerente"
    # O que não foi informado continua como estava — o fluxo inclusive.
    assert req.fluxo_id == 301
    assert req.departamento_id == 416
    assert req.nome == "Paulo"


def test_tipos_de_entidade_aceitam_objeto_texto_e_formato_da_v1():
    normalizar = configuracao_tenant.normalizar_tipos_de_entidade
    assert json.loads(normalizar({"cidade": "onde mora"})) == {"cidade": "onde mora"}
    assert json.loads(normalizar(["cpf"])) == ["cpf"]
    # Texto JSON, e texto JSON codificado duas vezes.
    assert json.loads(normalizar('{"cpf": "doc"}')) == {"cpf": "doc"}
    assert json.loads(normalizar(json.dumps('{"cpf": "doc"}'))) == {"cpf": "doc"}
    # Backup da v1: embrulhado e com categorias.
    v1 = {"entity_types": {"produto": {"dimensoes": "tamanho"}}}
    assert json.loads(normalizar(v1)) == {"dimensoes": "tamanho [produto]"}
    for ruim in ("não é json", 42):
        with pytest.raises(ToolError):
            normalizar(ruim)


async def test_dry_run_valida_como_a_chamada_real():
    """A simulação não pode aprovar o que a chamada real recusaria."""
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        with pytest.raises(ToolError):
            await servidor.funcoes["update_config_avancada"](
                primary_color="verde", dry_run=True
            )
        with pytest.raises(ToolError):
            await servidor.funcoes["update_config_avancada"](
                entity_types_json="{quebrado", dry_run=True
            )
        with pytest.raises(ToolError):
            await servidor.funcoes["set_prompts"](
                prompts=[configuracao_tenant.Prompt(chave="OPENAI_API_KEY", texto="x")],
                dry_run=True,
            )
        ok = await servidor.funcoes["update_config_avancada"](
            entity_types_json={"entity_types": {"p": {"cor": "c"}}}, dry_run=True
        )
    assert "SIMULAÇÃO" in ok
    assert "UpdateMyConfigAvancada" not in cliente.metodos


async def test_tipos_de_entidade_chegam_normalizados_ao_backend():
    servidor, cliente, _ = _montar()
    with como(ADMIN):
        await servidor.funcoes["update_config_avancada"](
            entity_types_json={"dimensoes": "tamanho"}
        )
    _, req, _ = cliente.chamadas[-1]
    assert json.loads(req.entity_types_json) == {"dimensoes": "tamanho"}


def test_datas_saem_em_iso():
    d = para_dict(pb.MyIntent(id=1, criado_em=1789260542401, atualizado_em=0))
    assert d["criado_em"].startswith("2026-")
    assert d["criado_em"].endswith("Z")
    # Zero é "sem data", e não 1970.
    assert d["atualizado_em"] is None


async def test_list_atendentes_traz_o_fluxo():
    servidor, _, _ = _montar()
    with como(ADMIN):
        ats = await servidor.funcoes["list_atendentes"]()
    assert ats[0]["fluxo_id"] == 301


async def test_get_tenant_config_explica_a_heranca_do_global():
    servidor, _, _ = _montar()
    with como(ADMIN):
        cfg = await servidor.funcoes["get_tenant_config"]()
    assert "padrão global" in cfg["observacao"]
