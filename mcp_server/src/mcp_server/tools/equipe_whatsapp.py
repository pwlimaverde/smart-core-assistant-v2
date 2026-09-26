"""Tools da equipe (usuários, permissões, convites) e das conexões de WhatsApp.

Fica de fora de propósito: gerenciar os próprios consentimentos MCP. Um agente
que pudesse ampliar as permissões do aplicativo pelo qual ele mesmo age seria
uma escada de privilégio; isso só se faz pela tela "Aplicativos conectados".
"""

from __future__ import annotations

import base64
import binascii
from typing import Annotated

from mcp.server.mcpserver import Image
from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor, limitar_itens, para_dict
from mcp_server.tools.guards import exigir_confirmacao, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

DRY_RUN = Field(default=False, description="Só simular.")
CONEXAO_ID = Field(description="Id da conexão, de `list_conexoes_whatsapp`.")


def imagem_do_qr(qr: str) -> Image | None:
    """O QR vem como imagem em base64 (com ou sem o prefixo `data:`)."""
    bruto = qr.split(",", 1)[1] if qr.startswith("data:") and "," in qr else qr
    try:
        dados = base64.b64decode(bruto, validate=True)
    except (binascii.Error, ValueError):
        return None
    return Image(data=dados, format="png") if dados else None


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools de equipe e de WhatsApp."""

    # -- Equipe ---------------------------------------------------------------

    registro.registrar("list_usuarios", Categoria.LEITURA, ("tenant:admin",))

    @mcp.tool(
        name="list_usuarios", annotations=registro.exigir("list_usuarios").anotacoes
    )
    async def list_usuarios() -> list[dict[str, object]]:
        """Lista os usuários com acesso ao negócio, com papel, permissões e fluxos que
        cada um enxerga. Só administradores. Use antes de mudar acessos com
        `update_usuario`."""
        r = await executor.executar(
            "list_usuarios", "ListTenantUsers", pb.ListTenantUsersRequest()
        )
        return [para_dict(u) for u in limitar_itens(list(r.users), teto)]

    registro.registrar("update_usuario", Categoria.CONFIGURACAO, ("tenant:admin",))

    @mcp.tool(
        name="update_usuario", annotations=registro.exigir("update_usuario").anotacoes
    )
    async def update_usuario(
        user_id: Annotated[int, Field(description="`user_id`, de `list_usuarios`.")],
        papel: Annotated[
            str | None, Field(default=None, description="admin, staff ou viewer.")
        ] = None,
        permissoes: Annotated[
            list[str] | None,
            Field(default=None, description="Escopos, ex.: ['atendimentos:read']."),
        ] = None,
        fluxos: Annotated[
            list[int] | None,
            Field(default=None, description="Ids dos fluxos que a pessoa enxerga."),
        ] = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Muda papel, permissões ou fluxos de um usuário. Só o informado muda.
        Mudança de permissão é auditada."""
        tool = registro.exigir("update_usuario")
        if papel is None and permissoes is None and fluxos is None:
            raise ToolError("Informe papel, permissões ou fluxos.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"alterar o acesso do usuário {user_id}")
        await executor.executar(
            "update_usuario",
            "UpdateTenantUser",
            pb.UpdateTenantUserRequest(
                user_id=user_id,
                set_role=papel is not None,
                role=papel or "",
                set_module_permissions=permissoes is not None,
                module_permissions=permissoes or [],
                set_flow_permissions=fluxos is not None,
                flow_permissions=fluxos or [],
            ),
        )
        return f"Acesso do usuário {user_id} atualizado."

    registro.registrar("list_convites", Categoria.LEITURA, ("tenant:admin",))

    @mcp.tool(
        name="list_convites", annotations=registro.exigir("list_convites").anotacoes
    )
    async def list_convites() -> list[dict[str, object]]:
        """Lista os convites de equipe enviados, com a situação de cada um (usado,
        revogado, expirado). Use antes de convidar de novo alguém, para não
        duplicar."""
        r = await executor.executar(
            "list_convites", "ListInvites", pb.ListInvitesRequest()
        )
        return [para_dict(c) for c in limitar_itens(list(r.invites), teto)]

    registro.registrar("create_convite", Categoria.CONFIGURACAO, ("tenant:admin",))

    @mcp.tool(
        name="create_convite", annotations=registro.exigir("create_convite").anotacoes
    )
    async def create_convite(
        email: Annotated[str, Field(description="E-mail da pessoa convidada.")],
        nome: Annotated[str, Field(description="Nome dela.")],
        papel: Annotated[
            str, Field(default="staff", description="admin, staff ou viewer.")
        ] = "staff",
        permissoes: Annotated[
            list[str], Field(description="Lista; vazia = nenhum.")
        ] = [],  # noqa: B006
        fluxos: Annotated[list[int], Field(description="Lista; vazia = nenhum.")] = [],  # noqa: B006
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Convida alguém para a equipe. O convite chega por e-mail; o link não
        é devolvido aqui (é credencial de acesso)."""
        tool = registro.exigir("create_convite")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"convidar {email} como '{papel}'")
        r = await executor.executar(
            "create_convite",
            "CreateInvite",
            pb.CreateInviteRequest(
                email=email,
                name=nome,
                role=papel,
                module_permissions=permissoes,
                flow_permissions=fluxos,
            ),
        )
        return f"Convite enviado para {r.invite.email} (id {r.invite.id})."

    registro.registrar("reenviar_convite", Categoria.CONFIGURACAO, ("tenant:admin",))

    @mcp.tool(
        name="reenviar_convite",
        annotations=registro.exigir("reenviar_convite").anotacoes,
    )
    async def reenviar_convite(
        convite_id: Annotated[str, Field(description="Id, de `list_convites`.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Reenvia o e-mail de um convite ainda não usado e renova o prazo de validade.
        Use quando a pessoa diz que não recebeu ou o convite expirou."""
        tool = registro.exigir("reenviar_convite")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "reenviar o e-mail do convite")
        await executor.executar(
            "reenviar_convite",
            "ReenviarConvite",
            pb.ReenviarConviteRequest(invite_id=convite_id),
        )
        return "Convite reenviado."

    registro.registrar("revogar_convite", Categoria.DESTRUTIVA, ("tenant:admin",))

    @mcp.tool(
        name="revogar_convite", annotations=registro.exigir("revogar_convite").anotacoes
    )
    async def revogar_convite(
        convite_id: Annotated[str, Field(description="Id, de `list_convites`.")],
        confirmar: Annotated[
            str, Field(default="", description="E-mail exato do convidado.")
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Revoga um convite ainda não usado: o link deixa de funcionar. Não tem
        desfazer (um convite novo teria de ser enviado). Exige o e-mail exato como
        confirmação."""
        tool = registro.exigir("revogar_convite")
        lista = await executor.executar(
            "revogar_convite",
            "ListInvites",
            pb.ListInvitesRequest(),
            contabilizar=False,
        )
        email = next((c.email for c in lista.invites if c.id == convite_id), None)
        if email is None:
            raise ToolError("Convite não encontrado. Confira em `list_convites`.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "revogar o convite")
        exigir_confirmacao(tool, email, confirmar or None)
        await executor.executar(
            "revogar_convite",
            "RevokeInvite",
            pb.RevokeInviteRequest(invite_id=convite_id),
        )
        return "Convite revogado."

    # -- WhatsApp -------------------------------------------------------------

    registro.registrar(
        "create_conexao_whatsapp", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="create_conexao_whatsapp",
        annotations=registro.exigir("create_conexao_whatsapp").anotacoes,
    )
    async def create_conexao_whatsapp(
        nome: Annotated[str, Field(description="Nome da conexão, ex.: 'Comercial'.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria uma conexão de WhatsApp. Em seguida use
        `get_status_conexao_whatsapp` para obter o QR code a escanear."""
        tool = registro.exigir("create_conexao_whatsapp")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar a conexão '{nome}'")
        r = await executor.executar(
            "create_conexao_whatsapp",
            "CreateMyWhatsappInstance",
            pb.CreateMyWhatsappInstanceRequest(instance_name=nome),
        )
        return f"Conexão '{r.instance_name}' criada com o id {r.id}."

    registro.registrar(
        "get_status_conexao_whatsapp", Categoria.LEITURA, ("operacional:read",)
    )

    @mcp.tool(
        name="get_status_conexao_whatsapp",
        annotations=registro.exigir("get_status_conexao_whatsapp").anotacoes,
    )
    async def get_status_conexao_whatsapp(
        conexao_id: Annotated[int, CONEXAO_ID],
    ) -> list[object]:
        """Estado da conexão e, se ela estiver esperando pareamento, o QR code
        para a pessoa escanear no WhatsApp do celular (Aparelhos conectados)."""
        r = await executor.executar(
            "get_status_conexao_whatsapp",
            "GetMyWhatsappInstanceStatus",
            pb.GetMyWhatsappInstanceStatusRequest(id=conexao_id),
        )
        saida: list[object] = [f"Estado: {r.connection_state or 'desconhecido'}."]
        imagem = imagem_do_qr(r.qr_code) if r.qr_code else None
        if imagem is not None:
            saida.append("Escaneie o QR abaixo (ele expira em poucos segundos):")
            saida.append(imagem)
        return saida

    registro.registrar(
        "get_detalhe_conexao_whatsapp", Categoria.LEITURA, ("operacional:read",)
    )

    @mcp.tool(
        name="get_detalhe_conexao_whatsapp",
        annotations=registro.exigir("get_detalhe_conexao_whatsapp").anotacoes,
    )
    async def get_detalhe_conexao_whatsapp(
        conexao_id: Annotated[int, CONEXAO_ID],
    ) -> dict[str, object]:
        """Detalhe da conexão: departamento, se a IA responde, atendimentos
        abertos e mensagens nas últimas 24h."""
        r = await executor.executar(
            "get_detalhe_conexao_whatsapp",
            "DetalheDaConexao",
            pb.DetalheDaConexaoRequest(id=conexao_id),
        )
        return para_dict(r)

    registro.registrar(
        "reconectar_conexao_whatsapp", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="reconectar_conexao_whatsapp",
        annotations=registro.exigir("reconectar_conexao_whatsapp").anotacoes,
    )
    async def reconectar_conexao_whatsapp(
        conexao_id: Annotated[int, CONEXAO_ID],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Pede a reconexão de um número de WhatsApp que caiu, sem novo pareamento. Se
        a sessão foi perdida, não resolve: aí é preciso escanear o QR de novo."""
        tool = registro.exigir("reconectar_conexao_whatsapp")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "pedir a reconexão do WhatsApp")
        await executor.executar(
            "reconectar_conexao_whatsapp",
            "ReconnectMyWhatsappInstance",
            pb.MyWhatsappInstanceIdRequest(id=conexao_id),
        )
        return "Reconexão solicitada. Confira com `get_status_conexao_whatsapp`."

    registro.registrar(
        "desconectar_conexao_whatsapp", Categoria.DESTRUTIVA, ("operacional:admin",)
    )

    @mcp.tool(
        name="desconectar_conexao_whatsapp",
        annotations=registro.exigir("desconectar_conexao_whatsapp").anotacoes,
    )
    async def desconectar_conexao_whatsapp(
        conexao_id: Annotated[int, CONEXAO_ID],
        confirmar: Annotated[str, Field(default="", description="Nome exato.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Desconecta o WhatsApp (sai da sessão). Para voltar é preciso escanear
        o QR de novo. Mensagens de clientes deixam de chegar."""
        tool = registro.exigir("desconectar_conexao_whatsapp")
        lista = await executor.executar(
            "desconectar_conexao_whatsapp",
            "ListMyWhatsappInstances",
            pb.ListMyWhatsappInstancesRequest(),
            contabilizar=False,
        )
        nome = next((i.name for i in lista.instancias if i.id == conexao_id), None)
        if nome is None:
            raise ToolError("Conexão não encontrada. Confira `list_conexoes_whatsapp`.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desconectar '{nome}'")
        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desconectar_conexao_whatsapp",
            "DesconectarMyWhatsappInstance",
            pb.MyWhatsappInstanceIdRequest(id=conexao_id),
        )
        return f"Conexão '{nome}' desconectada."

    registro.registrar(
        "definir_resposta_bot_conexao", Categoria.CONFIGURACAO, ("tenant:admin",)
    )

    @mcp.tool(
        name="definir_resposta_bot_conexao",
        annotations=registro.exigir("definir_resposta_bot_conexao").anotacoes,
    )
    async def definir_resposta_bot_conexao(
        conexao_id: Annotated[int, CONEXAO_ID],
        habilitado: Annotated[bool, Field(description="A IA responde neste número.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Liga ou desliga a IA em **todas** as conversas de um número de WhatsApp.
        Para uma conversa só, use `definir_bot_da_conversa`. Só administradores."""
        tool = registro.exigir("definir_resposta_bot_conexao")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "ligar/desligar a IA em todo o número")
        r = await executor.executar(
            "definir_resposta_bot_conexao",
            "DefinirRespostaBotInstancia",
            pb.DefinirRespostaBotInstanciaRequest(id=conexao_id, habilitado=habilitado),
        )
        return (
            "IA ligada neste número." if r.habilitado else "IA desligada neste número."
        )

    registro.registrar(
        "definir_departamento_da_conexao",
        Categoria.CONFIGURACAO,
        ("operacional:admin",),
    )

    @mcp.tool(
        name="definir_departamento_da_conexao",
        annotations=registro.exigir("definir_departamento_da_conexao").anotacoes,
    )
    async def definir_departamento_da_conexao(
        conexao_id: Annotated[int, CONEXAO_ID],
        departamento_id: Annotated[
            int, Field(description="Departamento que recebe as conversas. 0 = nenhum.")
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Define para qual departamento vão as conversas novas de um número de
        WhatsApp. Use `list_departamentos` para o id; 0 tira o departamento."""
        tool = registro.exigir("definir_departamento_da_conexao")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "mudar o departamento da conexão")
        await executor.executar(
            "definir_departamento_da_conexao",
            "DefinirDepartamentoDaConexao",
            pb.DefinirDepartamentoDaConexaoRequest(
                id=conexao_id, departamento_id=departamento_id
            ),
        )
        return "Departamento da conexão atualizado."

    registro.registrar(
        "list_mensagens_nao_entregues", Categoria.LEITURA, ("operacional:read",)
    )

    @mcp.tool(
        name="list_mensagens_nao_entregues",
        annotations=registro.exigir("list_mensagens_nao_entregues").anotacoes,
    )
    async def list_mensagens_nao_entregues() -> list[dict[str, object]]:
        """Lista as mensagens que não conseguiram sair para o WhatsApp, com o motivo da
        falha. Use quando o cliente diz que não recebeu, e antes de reenviar."""
        r = await executor.executar(
            "list_mensagens_nao_entregues",
            "ListMyMensagensNaoEntregues",
            pb.ListMyMensagensNaoEntreguesRequest(),
        )
        return [para_dict(m) for m in limitar_itens(list(r.itens), teto)]

    registro.registrar(
        "reenviar_mensagem_nao_entregue", Categoria.ENVIO, ("operacional:admin",)
    )

    @mcp.tool(
        name="reenviar_mensagem_nao_entregue",
        annotations=registro.exigir("reenviar_mensagem_nao_entregue").anotacoes,
    )
    async def reenviar_mensagem_nao_entregue(
        item_id: Annotated[
            int, Field(description="Id, de `list_mensagens_nao_entregues`.")
        ],
        confirmar: Annotated[
            str,
            Field(
                default="",
                description="O `atendimento_id` da mensagem, como confirmação.",
            ),
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Tenta enviar de novo uma mensagem que falhou. Ela chega ao cliente:
        confira o texto antes."""
        tool = registro.exigir("reenviar_mensagem_nao_entregue")
        lista = await executor.executar(
            "reenviar_mensagem_nao_entregue",
            "ListMyMensagensNaoEntregues",
            pb.ListMyMensagensNaoEntreguesRequest(),
            contabilizar=False,
        )
        item = next((m for m in lista.itens if m.id == item_id), None)
        if item is None:
            raise ToolError(
                "Mensagem não encontrada. Confira em `list_mensagens_nao_entregues`."
            )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"reenviar a mensagem do atendimento {item.atendimento_id}"
            )
        exigir_confirmacao(tool, str(item.atendimento_id), confirmar or None)
        r = await executor.executar(
            "reenviar_mensagem_nao_entregue",
            "ReenviarMensagemNaoEntregue",
            pb.ReenviarMensagemNaoEntregueRequest(id=item_id),
        )
        return f"Reenvio: {r.status or 'solicitado'}."

    # -- Números ignorados ----------------------------------------------------

    registro.registrar(
        "list_numeros_ignorados", Categoria.LEITURA, ("operacional:read",)
    )

    @mcp.tool(
        name="list_numeros_ignorados",
        annotations=registro.exigir("list_numeros_ignorados").anotacoes,
    )
    async def list_numeros_ignorados() -> list[dict[str, object]]:
        """Números cujas mensagens o sistema ignora (a IA não responde nem abre
        atendimento) — familiares, fornecedores, testes."""
        r = await executor.executar(
            "list_numeros_ignorados",
            "ListMyNumerosIgnorados",
            pb.ListMyNumerosIgnoradosRequest(),
        )
        return [para_dict(n) for n in limitar_itens(list(r.itens), teto)]

    registro.registrar(
        "create_numero_ignorado", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="create_numero_ignorado",
        annotations=registro.exigir("create_numero_ignorado").anotacoes,
    )
    async def create_numero_ignorado(
        nome: Annotated[str, Field(description="De quem é o número.")],
        telefone: Annotated[str, Field(description="Com DDI e DDD.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Passa a ignorar as mensagens de um número: a IA não responde e nenhum
        atendimento é aberto. Use para familiares, fornecedores e números de teste."""
        tool = registro.exigir("create_numero_ignorado")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "passar a ignorar o número")
        r = await executor.executar(
            "create_numero_ignorado",
            "CriarNumeroIgnorado",
            pb.CriarNumeroIgnoradoRequest(nome=nome, telefone=telefone),
        )
        return f"Número ignorado cadastrado (id {r.item.id})."

    registro.registrar(
        "update_numero_ignorado", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="update_numero_ignorado",
        annotations=registro.exigir("update_numero_ignorado").anotacoes,
    )
    async def update_numero_ignorado(
        item_id: Annotated[int, Field(description="Id, de `list_numeros_ignorados`.")],
        nome: str,
        telefone: str,
        ativo: bool = True,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Edita um número ignorado, ou o pausa com `ativo=false` (as mensagens voltam
        a ser atendidas sem apagar o cadastro)."""
        tool = registro.exigir("update_numero_ignorado")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar o número ignorado")
        await executor.executar(
            "update_numero_ignorado",
            "AtualizarNumeroIgnorado",
            pb.AtualizarNumeroIgnoradoRequest(
                id=item_id, nome=nome, telefone=telefone, ativo=ativo
            ),
        )
        return f"Número ignorado {item_id} atualizado."

    registro.registrar(
        "remover_numero_ignorado", Categoria.DESTRUTIVA, ("operacional:admin",)
    )

    @mcp.tool(
        name="remover_numero_ignorado",
        annotations=registro.exigir("remover_numero_ignorado").anotacoes,
    )
    async def remover_numero_ignorado(
        item_id: Annotated[int, Field(description="Id, de `list_numeros_ignorados`.")],
        confirmar: Annotated[
            str, Field(default="", description="O telefone exato do número.")
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Remove um número da lista de ignorados: as mensagens dele voltam a ser
        atendidas pela IA e a abrir atendimento. Exige o telefone exato como
        confirmação."""
        tool = registro.exigir("remover_numero_ignorado")
        lista = await executor.executar(
            "remover_numero_ignorado",
            "ListMyNumerosIgnorados",
            pb.ListMyNumerosIgnoradosRequest(),
            contabilizar=False,
        )
        telefone = next((n.telefone for n in lista.itens if n.id == item_id), None)
        if telefone is None:
            raise ToolError("Número não encontrado. Confira `list_numeros_ignorados`.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"remover o número ignorado {item_id}")
        exigir_confirmacao(tool, telefone, confirmar or None)
        await executor.executar(
            "remover_numero_ignorado",
            "RemoverNumeroIgnorado",
            pb.NumeroIgnoradoIdRequest(id=item_id),
        )
        return f"Número ignorado {item_id} removido."
