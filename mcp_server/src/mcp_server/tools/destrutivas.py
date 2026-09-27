"""Tools destrutivas — desativam ou removem algo que alguém configurou.

Todas exigem confirmação casada com o **nome** do alvo, resolvido no servidor.
Exigir o nome, e não o id, é o que impede um id alucinado de passar: o modelo só
consegue preencher se tiver listado o objeto antes, e a lista é que traz o nome.

Diferente de `send_message`, aqui o nome do alvo **pode** ir na mensagem de erro:
nome de fluxo, de departamento ou de treinamento é dado de configuração do
negócio, não PII de cliente.
"""

from __future__ import annotations

from typing import Annotated

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor
from mcp_server.tools.guards import exigir_confirmacao, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro


def registrar(mcp, registro: Registro, executor: Executor) -> None:
    """Registra as tools destrutivas no servidor."""

    # -- Fluxo ---------------------------------------------------------------

    registro.registrar("desativar_fluxo", Categoria.DESTRUTIVA, ("kanban:admin",))

    @mcp.tool(
        name="desativar_fluxo", annotations=registro.exigir("desativar_fluxo").anotacoes
    )
    async def desativar_fluxo(
        fluxo_id: Annotated[int, Field(description="Id do fluxo, de `list_fluxos`.")],
        confirmar: Annotated[
            str,
            Field(
                default="",
                description=(
                    "Nome exato do fluxo, como aparece em `list_fluxos`. É a "
                    "confirmação — preencha só depois de conferir com a pessoa que "
                    "você está ajudando."
                ),
            ),
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Desativa um fluxo de atendimento. O quadro some da operação e os
        atendimentos abertos nele ficam sem lugar visível.

        Antes de chamar, veja em `list_fluxos` quantos atendimentos estão abertos
        no fluxo e diga esse número à pessoa que pediu — é a informação que muda
        a decisão dela.

        NÃO use para "limpar" fluxos de teste sem confirmar: pode haver conversa
        real dentro.
        """
        tool = registro.exigir("desativar_fluxo")
        alvo = await _fluxo(executor, fluxo_id)

        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool,
                f"desativar o fluxo '{alvo['nome']}', que tem "
                f"{alvo['atendimentos_abertos']} atendimento(s) aberto(s)",
            )

        exigir_confirmacao(tool, str(alvo["nome"]), confirmar or None)
        await executor.executar(
            "desativar_fluxo", "DesativarMyFluxo", pb.MyFluxoIdRequest(id=fluxo_id)
        )
        return f"Fluxo '{alvo['nome']}' desativado."

    # -- Etapa ---------------------------------------------------------------

    registro.registrar("desativar_etapa_fluxo", Categoria.DESTRUTIVA, ("kanban:admin",))

    @mcp.tool(
        name="desativar_etapa_fluxo",
        annotations=registro.exigir("desativar_etapa_fluxo").anotacoes,
    )
    async def desativar_etapa_fluxo(
        fluxo_id: Annotated[int, Field(description="Fluxo a que a etapa pertence.")],
        etapa_id: Annotated[
            int, Field(description="Id da etapa, de `list_etapas_fluxo`.")
        ],
        confirmar: Annotated[
            str,
            Field(
                default="", description="Nome exato da etapa, de `list_etapas_fluxo`."
            ),
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Desativa uma etapa (coluna) de um fluxo.

        Atendimentos parados nessa etapa deixam de aparecer nela. Confira em
        `list_atendimentos` se há algum antes de desativar.
        """
        tool = registro.exigir("desativar_etapa_fluxo")
        nome = await _nome_da_etapa(executor, fluxo_id, etapa_id)

        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desativar a etapa '{nome}'")

        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desativar_etapa_fluxo",
            "DesativarMyEtapaFluxo",
            pb.MyEtapaFluxoIdRequest(id=etapa_id),
        )
        return f"Etapa '{nome}' desativada."

    # -- Departamento --------------------------------------------------------

    registro.registrar(
        "desativar_departamento", Categoria.DESTRUTIVA, ("operacional:admin",)
    )

    @mcp.tool(
        name="desativar_departamento",
        annotations=registro.exigir("desativar_departamento").anotacoes,
    )
    async def desativar_departamento(
        departamento_id: Annotated[
            int, Field(description="Id, de `list_departamentos`.")
        ],
        confirmar: Annotated[
            str, Field(default="", description="Nome exato do departamento.")
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Desativa um departamento. Os fluxos e atendentes ligados a ele
        continuam existindo, mas o departamento some das listas de escolha.
        """
        tool = registro.exigir("desativar_departamento")
        nome = await _nome_do_departamento(executor, departamento_id)

        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desativar o departamento '{nome}'")

        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desativar_departamento",
            "DesativarMyDepartamento",
            pb.MyDepartamentoIdRequest(id=departamento_id),
        )
        return f"Departamento '{nome}' desativado."

    # -- Atendente -----------------------------------------------------------

    registro.registrar(
        "desativar_atendente", Categoria.DESTRUTIVA, ("operacional:admin",)
    )

    @mcp.tool(
        name="desativar_atendente",
        annotations=registro.exigir("desativar_atendente").anotacoes,
    )
    async def desativar_atendente(
        atendente_id: Annotated[int, Field(description="Id, de `list_atendentes`.")],
        confirmar: Annotated[
            str,
            Field(
                default="", description="Nome exato do atendente, de `list_atendentes`."
            ),
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Desativa um atendente. Ele para de receber atendimentos novos.

        Use quando alguém sai da equipe. Os atendimentos que já estão com ele
        continuam onde estão — trate-os antes.
        """
        tool = registro.exigir("desativar_atendente")
        nome = await _nome_do_atendente(executor, atendente_id)

        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desativar o atendente '{nome}'")

        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desativar_atendente",
            "DesativarMyAtendente",
            pb.MyAtendenteIdRequest(id=atendente_id),
        )
        return f"Atendente '{nome}' desativado."

    # -- Conexão de WhatsApp -------------------------------------------------

    registro.registrar(
        "excluir_conexao_whatsapp", Categoria.DESTRUTIVA, ("operacional:admin",)
    )

    @mcp.tool(
        name="excluir_conexao_whatsapp",
        annotations=registro.exigir("excluir_conexao_whatsapp").anotacoes,
    )
    async def excluir_conexao_whatsapp(
        conexao_id: Annotated[
            int, Field(description="Id, de `list_conexoes_whatsapp`.")
        ],
        confirmar: Annotated[
            str, Field(default="", description="Nome exato da conexão.")
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Exclui uma conexão de WhatsApp do negócio. **Definitivo.**

        **É a ação mais grave deste servidor.** A sessão é apagada no WhatsApp,
        o número para de receber e de enviar mensagens na hora, e a conexão não
        volta: para usar o número de novo, cria-se outra e lê-se o QR Code do
        celular. O registro fica só para a auditoria. Se a intenção é só
        reiniciar uma conexão travada, use `reconectar_conexao_whatsapp`.
        """
        tool = registro.exigir("excluir_conexao_whatsapp")
        nome = await _nome_da_conexao(executor, conexao_id)

        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool,
                f"excluir DEFINITIVAMENTE a conexão '{nome}', o que derruba o "
                "número; para voltar, só criando outra conexão e lendo novo QR Code",
            )

        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "excluir_conexao_whatsapp",
            "DeleteMyWhatsappInstance",
            pb.MyWhatsappInstanceIdRequest(id=conexao_id),
        )
        return (
            f"Conexão '{nome}' excluída definitivamente. "
            "Para usar o número de novo, crie outra conexão e leia o QR Code."
        )


# ---------------------------------------------------------------------------
# Resolução do alvo — sempre no servidor, nunca a partir do que o agente disse
# ---------------------------------------------------------------------------


def _nao_encontrado(o_que: str, item_id: int, tool_de_lista: str) -> ToolError:
    return ToolError(
        f"{o_que} {item_id} não existe. Liste com `{tool_de_lista}` e use um id de lá."
    )


async def _fluxo(executor: Executor, fluxo_id: int) -> dict[str, object]:
    resposta = await executor.executar(
        "desativar_fluxo",
        "ListMyFluxos",
        pb.ListMyFluxosRequest(),
        contabilizar=False,
    )
    for f in resposta.fluxos:
        if f.id == fluxo_id:
            return {"nome": f.nome, "atendimentos_abertos": f.atendimentos_abertos}
    raise _nao_encontrado("O fluxo", fluxo_id, "list_fluxos")


async def _nome_da_etapa(executor: Executor, fluxo_id: int, etapa_id: int) -> str:
    resposta = await executor.executar(
        "desativar_etapa_fluxo",
        "ListMyEtapasFluxo",
        pb.MyFluxoIdRequest(id=fluxo_id),
        contabilizar=False,
    )
    for e in resposta.etapas:
        if e.id == etapa_id:
            return str(e.nome)
    raise _nao_encontrado("A etapa", etapa_id, "list_etapas_fluxo")


async def _nome_do_departamento(executor: Executor, departamento_id: int) -> str:
    resposta = await executor.executar(
        "desativar_departamento",
        "ListMyDepartamentos",
        pb.ListMyDepartamentosRequest(),
        contabilizar=False,
    )
    for d in resposta.departamentos:
        if d.id == departamento_id:
            return str(d.nome)
    raise _nao_encontrado("O departamento", departamento_id, "list_departamentos")


async def _nome_do_atendente(executor: Executor, atendente_id: int) -> str:
    resposta = await executor.executar(
        "desativar_atendente",
        "ListMyAtendentes",
        pb.ListMyAtendentesRequest(),
        contabilizar=False,
    )
    for a in resposta.atendentes:
        if a.id == atendente_id:
            return str(a.nome)
    raise _nao_encontrado("O atendente", atendente_id, "list_atendentes")


async def _nome_da_conexao(executor: Executor, conexao_id: int) -> str:
    resposta = await executor.executar(
        "excluir_conexao_whatsapp",
        "ListMyWhatsappInstances",
        pb.ListMyWhatsappInstancesRequest(),
        contabilizar=False,
    )
    for i in resposta.instancias:
        if i.id == conexao_id:
            return str(i.name)
    raise _nao_encontrado("A conexão", conexao_id, "list_conexoes_whatsapp")
