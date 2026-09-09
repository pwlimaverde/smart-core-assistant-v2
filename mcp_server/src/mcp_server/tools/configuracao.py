"""Tools de configuração — escrevem, mas nada aqui é irreversível.

Criar um fluxo a mais é chato de limpar; enviar mensagem a um cliente errado não
tem desfazer. Por isso esta categoria tem `dry_run` mas **não** exige
confirmação: pedir confirmação para toda criação tornaria o agente inutilizável
para a tarefa que ele existe para fazer — configurar um funil do zero.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor
from mcp_server.tools.guards import resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro


def registrar(mcp, registro: Registro, executor: Executor) -> None:
    """Registra as tools de configuração no servidor."""

    # -- Departamentos -------------------------------------------------------

    registro.registrar(
        "create_departamento", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="create_departamento",
        annotations=registro.exigir("create_departamento").anotacoes,
    )
    async def create_departamento(
        nome: Annotated[
            str, Field(description="Nome do departamento, ex.: 'Comercial'.")
        ],
        descricao: Annotated[
            str, Field(default="", description="O que ele atende.")
        ] = "",
        dry_run: Annotated[
            bool,
            Field(
                default=False,
                description=(
                    "Se true, apenas descreve o que seria criado, sem criar nada."
                ),
            ),
        ] = False,
    ) -> str:
        """Cria um departamento (uma área do negócio, como Comercial ou Suporte).

        Use antes de criar fluxos e atendentes: os dois pedem um departamento.

        NÃO use para criar um departamento por cliente ou por campanha — a
        estrutura é da empresa, não do atendimento.
        """
        tool = registro.exigir("create_departamento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar o departamento '{nome}'")

        resposta = await executor.executar(
            "create_departamento",
            "CreateMyDepartamento",
            pb.CreateMyDepartamentoRequest(nome=nome, descricao=descricao),
        )
        return f"Departamento '{resposta.nome}' criado com o id {resposta.id}."

    registro.registrar(
        "update_departamento", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="update_departamento",
        annotations=registro.exigir("update_departamento").anotacoes,
    )
    async def update_departamento(
        departamento_id: Annotated[
            int, Field(description="Id, obtido em `list_departamentos`.")
        ],
        nome: Annotated[str, Field(description="Novo nome.")],
        descricao: Annotated[
            str, Field(default="", description="Nova descrição.")
        ] = "",
        ativo: Annotated[bool, Field(default=True, description="Manter ativo.")] = True,
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Altera nome, descrição ou situação de um departamento existente.

        Passe todos os campos, não só o que muda: esta tool **substitui** os
        valores, então omitir a descrição a apaga. Leia o valor atual em
        `list_departamentos` antes.
        """
        tool = registro.exigir("update_departamento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"renomear o departamento {departamento_id}")

        await executor.executar(
            "update_departamento",
            "UpdateMyDepartamento",
            pb.UpdateMyDepartamentoRequest(
                id=departamento_id, nome=nome, descricao=descricao, ativo=ativo
            ),
        )
        return f"Departamento {departamento_id} atualizado."

    # -- Fluxos --------------------------------------------------------------

    registro.registrar("create_fluxo", Categoria.CONFIGURACAO, ("kanban:admin",))

    @mcp.tool(
        name="create_fluxo", annotations=registro.exigir("create_fluxo").anotacoes
    )
    async def create_fluxo(
        departamento_id: Annotated[
            int,
            Field(description="Departamento dono do fluxo, de `list_departamentos`."),
        ],
        nome: Annotated[
            str, Field(description="Nome do fluxo, ex.: 'Funil de Vendas'.")
        ],
        descricao: Annotated[
            str, Field(default="", description="Para que serve.")
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Cria um fluxo de atendimento — um quadro Kanban onde os atendimentos
        caminham por etapas.

        Depois de criar, use `create_etapa_fluxo` para montar as colunas: um
        fluxo sem etapas não serve para nada.
        """
        tool = registro.exigir("create_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"criar o fluxo '{nome}' no departamento {departamento_id}"
            )

        resposta = await executor.executar(
            "create_fluxo",
            "CreateMyFluxo",
            pb.CreateMyFluxoRequest(
                departamento_id=departamento_id, nome=nome, descricao=descricao
            ),
        )
        return f"Fluxo '{resposta.fluxo.nome}' criado com o id {resposta.fluxo.id}."

    registro.registrar("update_fluxo", Categoria.CONFIGURACAO, ("kanban:admin",))

    @mcp.tool(
        name="update_fluxo", annotations=registro.exigir("update_fluxo").anotacoes
    )
    async def update_fluxo(
        fluxo_id: Annotated[int, Field(description="Id do fluxo, de `list_fluxos`.")],
        nome: Annotated[str, Field(description="Novo nome.")],
        descricao: Annotated[
            str, Field(default="", description="Nova descrição.")
        ] = "",
        ativo: Annotated[bool, Field(default=True, description="Manter ativo.")] = True,
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Altera nome, descrição ou situação de um fluxo.

        Para desativar um fluxo use `desativar_fluxo`, que pede confirmação — é
        uma ação com consequência para os atendimentos abertos nele.
        """
        tool = registro.exigir("update_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"atualizar o fluxo {fluxo_id}")

        await executor.executar(
            "update_fluxo",
            "UpdateMyFluxo",
            pb.UpdateMyFluxoRequest(
                id=fluxo_id, nome=nome, descricao=descricao, ativo=ativo
            ),
        )
        return f"Fluxo {fluxo_id} atualizado."

    # -- Etapas --------------------------------------------------------------

    registro.registrar("create_etapa_fluxo", Categoria.CONFIGURACAO, ("kanban:admin",))

    @mcp.tool(
        name="create_etapa_fluxo",
        annotations=registro.exigir("create_etapa_fluxo").anotacoes,
    )
    async def create_etapa_fluxo(
        fluxo_id: Annotated[int, Field(description="Fluxo que recebe a etapa.")],
        nome: Annotated[
            str, Field(description="Nome da etapa, ex.: 'Proposta enviada'.")
        ],
        tipo_etapa: Annotated[
            str,
            Field(
                default="intermediaria",
                description=(
                    "Papel da etapa no funil: 'inicial' para a primeira, "
                    "'intermediaria' para o meio, 'final' para a conclusão."
                ),
            ),
        ] = "intermediaria",
        cor: Annotated[
            str, Field(default="", description="Cor em hexadecimal, ex.: '#2E7D32'.")
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Cria uma etapa (coluna) num fluxo. A etapa entra no fim da ordem
        existente; use `mover_etapa_fluxo` para reposicioná-la.

        Ao montar um funil do zero, crie as etapas na ordem em que elas
        acontecem — assim não é preciso reordenar depois.
        """
        tool = registro.exigir("create_etapa_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"criar a etapa '{nome}' no fluxo {fluxo_id}"
            )

        resposta = await executor.executar(
            "create_etapa_fluxo",
            "CreateMyEtapaFluxo",
            pb.CreateMyEtapaFluxoRequest(
                fluxo_id=fluxo_id, nome=nome, tipo_etapa=tipo_etapa, cor=cor
            ),
        )
        return f"Etapa '{resposta.etapa.nome}' criada com o id {resposta.etapa.id}."

    registro.registrar("mover_etapa_fluxo", Categoria.CONFIGURACAO, ("kanban:admin",))

    @mcp.tool(
        name="mover_etapa_fluxo",
        annotations=registro.exigir("mover_etapa_fluxo").anotacoes,
    )
    async def mover_etapa_fluxo(
        etapa_id: Annotated[
            int, Field(description="Id da etapa, de `list_etapas_fluxo`.")
        ],
        para_cima: Annotated[
            bool,
            Field(
                description=(
                    "True move a etapa uma posição para trás no funil; "
                    "false, para a frente."
                )
            ),
        ],
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Move uma etapa uma posição na ordem do fluxo.

        Move **uma** posição por chamada: para deslocar mais, chame de novo.
        """
        tool = registro.exigir("mover_etapa_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"mover a etapa {etapa_id}")

        await executor.executar(
            "mover_etapa_fluxo",
            "MoverMyEtapaFluxo",
            pb.MoverMyEtapaFluxoRequest(id=etapa_id, para_cima=para_cima),
        )
        return f"Etapa {etapa_id} movida."

    # -- Atendentes ----------------------------------------------------------

    registro.registrar(
        "create_atendente", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="create_atendente",
        annotations=registro.exigir("create_atendente").anotacoes,
    )
    async def create_atendente(
        nome: Annotated[str, Field(description="Nome da pessoa.")],
        email: Annotated[str, Field(description="E-mail dela.")],
        departamento_id: Annotated[
            int, Field(description="Departamento em que ela atua.")
        ],
        cargo: Annotated[
            str, Field(default="", description="Cargo, ex.: 'Vendedor'.")
        ] = "",
        fluxo_id: Annotated[
            int,
            Field(default=0, description="Fluxo a que ela fica restrita. 0 = todos."),
        ] = 0,
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Cadastra um atendente — uma pessoa que atende clientes no sistema.

        Confira com `list_atendentes` antes: cadastrar a mesma pessoa duas vezes
        divide o histórico dela e é chato de desfazer.
        """
        tool = registro.exigir("create_atendente")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"cadastrar o atendente '{nome}'")

        resposta = await executor.executar(
            "create_atendente",
            "CreateMyAtendente",
            pb.CreateMyAtendenteRequest(
                nome=nome,
                email=email,
                cargo=cargo,
                fluxo_id=fluxo_id,
                departamento_id=departamento_id,
            ),
        )
        return f"Atendente cadastrado com o id {resposta.atendente.id}."

    # -- Base de conhecimento ------------------------------------------------

    registro.registrar(
        "create_treinamento", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="create_treinamento",
        annotations=registro.exigir("create_treinamento").anotacoes,
    )
    async def create_treinamento(
        tag: Annotated[
            str, Field(description="Rótulo curto do assunto, ex.: 'politica-troca'.")
        ],
        conteudo: Annotated[
            str, Field(description="O texto que o assistente vai usar para responder.")
        ],
        grupo: Annotated[
            str, Field(default="", description="Agrupamento, ex.: 'atendimento'.")
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Acrescenta um texto à base de conhecimento do assistente.

        O conteúdo só passa a valer nas respostas depois de finalizado e
        vetorizado — criar não basta.

        NÃO use para guardar dado de cliente: a base é conhecimento do negócio
        (políticas, preços, procedimentos), e o conteúdo pode aparecer numa
        resposta a qualquer cliente.
        """
        tool = registro.exigir("create_treinamento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar o treinamento com a tag '{tag}'")

        resposta = await executor.executar(
            "create_treinamento",
            "CreateMyTreinamento",
            pb.CreateMyTreinamentoRequest(tag=tag, grupo=grupo, conteudo=conteudo),
        )
        return (
            f"Treinamento '{resposta.treinamento.tag}' criado com o id "
            f"{resposta.treinamento.id}. Ainda precisa ser finalizado para valer."
        )

    registro.registrar(
        "finalizar_treinamento", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="finalizar_treinamento",
        annotations=registro.exigir("finalizar_treinamento").anotacoes,
    )
    async def finalizar_treinamento(
        treinamento_id: Annotated[
            int, Field(description="Id, de `list_treinamentos`.")
        ],
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Finaliza um treinamento, colocando-o na fila de vetorização.

        É este passo que faz o conteúdo começar a ser usado nas respostas ao
        cliente.
        """
        tool = registro.exigir("finalizar_treinamento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"finalizar o treinamento {treinamento_id}")

        await executor.executar(
            "finalizar_treinamento",
            "FinalizarMyTreinamento",
            pb.FinalizarMyTreinamentoRequest(id=treinamento_id),
        )
        return (
            f"Treinamento {treinamento_id} finalizado; "
            "a vetorização acontece em seguida."
        )

    # -- Persona do bot ------------------------------------------------------

    registro.registrar(
        "set_bot_persona", Categoria.CONFIGURACAO, ("configuracoes:write",)
    )

    @mcp.tool(
        name="set_bot_persona", annotations=registro.exigir("set_bot_persona").anotacoes
    )
    async def set_bot_persona(
        persona: Annotated[
            str,
            Field(
                description=(
                    "Como o assistente deve se comportar com o cliente: tom, o que "
                    "pode e o que não pode dizer."
                )
            ),
        ],
        nome_do_agente: Annotated[
            str,
            Field(default="", description="Nome com que o assistente se apresenta."),
        ] = "",
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Define a persona do assistente — o texto que orienta o tom e os limites
        de tudo o que ele responde aos clientes.

        Leia a persona atual com `get_tenant_config` antes de trocar: esta tool
        **substitui** o texto inteiro, não acrescenta a ele.
        """
        tool = registro.exigir("set_bot_persona")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "substituir a persona do assistente")

        await executor.executar(
            "set_bot_persona",
            "SetMyBotPersona",
            pb.SetMyBotPersonaRequest(
                persona_bot=persona, bot_agent_name=nome_do_agente
            ),
        )
        return "Persona do assistente atualizada."
