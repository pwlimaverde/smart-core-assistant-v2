"""Tools de cadastro: contatos, clientes (empresas), campos personalizados,
edição de etapa e de atendente, e a trilha de auditoria do negócio.

Desativar contato, cliente ou campo é reversível (o registro continua lá e
volta com `ativo=true`), por isso fica em CONFIGURACAO — exceto o campo, que
some das fichas e do prompt da IA e por isso pede confirmação pelo nome.
"""

from __future__ import annotations

from typing import Annotated, Any, Literal

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor, limitar_itens, para_dict
from mcp_server.tools.guards import exigir_confirmacao, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

DRY_RUN = Field(default=False, description="Só simular.")
TipoCampo = Literal["texto", "numero", "booleano", "data", "lista"]


def _dados_cliente(**campos: str) -> pb.DadosMyCliente:
    return pb.DadosMyCliente(**{k: v for k, v in campos.items() if v is not None})


def _opcoes(opcoes: list[str]) -> list[pb.OpcaoCampo]:
    """Opções de campo `lista`: o id é o próprio rótulo normalizado."""
    return [
        pb.OpcaoCampo(id=o.strip().lower().replace(" ", "_"), rotulo=o.strip())
        for o in opcoes
        if o.strip()
    ]


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools de cadastro."""

    # -- Contatos ------------------------------------------------------------

    registro.registrar("create_contato", Categoria.CONFIGURACAO, ("clientes:write",))

    @mcp.tool(
        name="create_contato", annotations=registro.exigir("create_contato").anotacoes
    )
    async def create_contato(
        telefone: Annotated[
            str, Field(description="Telefone com DDI e DDD, ex.: '5585999998888'.")
        ],
        nome: Annotated[str, Field(default="", description="Nome do contato.")] = "",
        email: Annotated[str, Field(default="", description="E-mail.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cadastra um contato (pessoa com quem o negócio conversa no WhatsApp).
        Busque antes com `list_contatos` para não duplicar."""
        tool = registro.exigir("create_contato")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "cadastrar um contato novo")
        r = await executor.executar(
            "create_contato",
            "CreateMyContato",
            pb.CreateMyContatoRequest(
                telefone=telefone, nome_contato=nome, email=email
            ),
        )
        return f"Contato cadastrado com o id {r.contato.id}."

    registro.registrar("update_contato", Categoria.CONFIGURACAO, ("clientes:write",))

    @mcp.tool(
        name="update_contato", annotations=registro.exigir("update_contato").anotacoes
    )
    async def update_contato(
        contato_id: Annotated[int, Field(description="Id, de `list_contatos`.")],
        nome: Annotated[str, Field(description="Nome (envie o atual para manter).")],
        telefone: Annotated[str, Field(description="Telefone (envie o atual).")],
        email: Annotated[str, Field(default="", description="E-mail.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Corrige nome, telefone ou e-mail de um contato. Todos os campos são
        gravados: leia o contato antes e reenvie o que não muda."""
        tool = registro.exigir("update_contato")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar o contato")
        await executor.executar(
            "update_contato",
            "UpdateMyContato",
            pb.UpdateMyContatoRequest(
                id=contato_id, nome_contato=nome, email=email, telefone=telefone
            ),
        )
        return f"Contato {contato_id} atualizado."

    registro.registrar(
        "definir_contato_ativo", Categoria.CONFIGURACAO, ("clientes:write",)
    )

    @mcp.tool(
        name="definir_contato_ativo",
        annotations=registro.exigir("definir_contato_ativo").anotacoes,
    )
    async def definir_contato_ativo(
        contato_id: Annotated[int, Field(description="Id do contato.")],
        ativo: Annotated[bool, Field(description="false = desativar.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Ativa ou desativa um contato. É reversível: o histórico fica, e o contato
        volta com `ativo=true`. Use para tirar da lista quem não é mais cliente, não
        para apagar dados."""
        tool = registro.exigir("definir_contato_ativo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "ativar/desativar o contato")
        await executor.executar(
            "definir_contato_ativo",
            "DefinirMyContatoAtivo",
            pb.DefinirMyContatoAtivoRequest(id=contato_id, ativo=ativo),
        )
        return f"Contato {contato_id} {'ativado' if ativo else 'desativado'}."

    # -- Clientes (empresas) -------------------------------------------------

    registro.registrar("list_clientes", Categoria.LEITURA, ("clientes:read",))

    @mcp.tool(
        name="list_clientes", annotations=registro.exigir("list_clientes").anotacoes
    )
    async def list_clientes(
        busca: Annotated[
            str, Field(default="", description="Nome, razão social ou documento.")
        ] = "",
        incluir_inativos: Annotated[bool, Field(default=False)] = False,
    ) -> list[dict[str, object]]:
        """Lista os clientes (empresas ou pessoas com cadastro completo) e
        quantos contatos cada um tem."""
        r = await executor.executar(
            "list_clientes",
            "ListMyClientes",
            pb.ListMyClientesRequest(
                busca=busca, incluir_inativos=incluir_inativos, limite=teto
            ),
        )
        return [para_dict(c) for c in limitar_itens(list(r.clientes), teto)]

    registro.registrar("create_cliente", Categoria.CONFIGURACAO, ("clientes:write",))

    @mcp.tool(
        name="create_cliente", annotations=registro.exigir("create_cliente").anotacoes
    )
    async def create_cliente(
        nome_fantasia: Annotated[str, Field(description="Nome como é conhecido.")],
        tipo: Annotated[
            Literal["pj", "pf", ""], Field(default="", description="pj, pf ou vazio.")
        ] = "",
        razao_social: str = "",
        cnpj: str = "",
        cpf: str = "",
        telefone: str = "",
        site: str = "",
        ramo_atividade: str = "",
        observacoes: str = "",
        cep: str = "",
        logradouro: str = "",
        numero: str = "",
        complemento: str = "",
        bairro: str = "",
        cidade: str = "",
        uf: str = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cadastra um cliente (empresa ou pessoa com dados completos). Contatos
        são ligados a ele depois, com `vincular_contato_cliente`."""
        tool = registro.exigir("create_cliente")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"cadastrar o cliente '{nome_fantasia}'")
        r = await executor.executar(
            "create_cliente",
            "CreateMyCliente",
            pb.CreateMyClienteRequest(
                dados=_dados_cliente(
                    nome_fantasia=nome_fantasia,
                    tipo=tipo,
                    razao_social=razao_social,
                    cnpj=cnpj,
                    cpf=cpf,
                    telefone=telefone,
                    site=site,
                    ramo_atividade=ramo_atividade,
                    observacoes=observacoes,
                    cep=cep,
                    logradouro=logradouro,
                    numero=numero,
                    complemento=complemento,
                    bairro=bairro,
                    cidade=cidade,
                    uf=uf,
                )
            ),
        )
        return f"Cliente '{nome_fantasia}' cadastrado com o id {r.cliente.id}."

    registro.registrar("update_cliente", Categoria.CONFIGURACAO, ("clientes:write",))

    @mcp.tool(
        name="update_cliente", annotations=registro.exigir("update_cliente").anotacoes
    )
    async def update_cliente(
        cliente_id: Annotated[int, Field(description="Id, de `list_clientes`.")],
        nome_fantasia: str,
        tipo: Literal["pj", "pf", ""] = "",
        razao_social: str = "",
        cnpj: str = "",
        cpf: str = "",
        telefone: str = "",
        site: str = "",
        ramo_atividade: str = "",
        observacoes: str = "",
        cep: str = "",
        logradouro: str = "",
        numero: str = "",
        complemento: str = "",
        bairro: str = "",
        cidade: str = "",
        uf: str = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Atualiza o cadastro de um cliente. Todos os campos são gravados: leia
        com `list_clientes` e reenvie o que não muda."""
        tool = registro.exigir("update_cliente")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar o cliente")
        await executor.executar(
            "update_cliente",
            "UpdateMyCliente",
            pb.UpdateMyClienteRequest(
                id=cliente_id,
                dados=_dados_cliente(
                    nome_fantasia=nome_fantasia,
                    tipo=tipo,
                    razao_social=razao_social,
                    cnpj=cnpj,
                    cpf=cpf,
                    telefone=telefone,
                    site=site,
                    ramo_atividade=ramo_atividade,
                    observacoes=observacoes,
                    cep=cep,
                    logradouro=logradouro,
                    numero=numero,
                    complemento=complemento,
                    bairro=bairro,
                    cidade=cidade,
                    uf=uf,
                ),
            ),
        )
        return f"Cliente {cliente_id} atualizado."

    registro.registrar(
        "definir_cliente_ativo", Categoria.CONFIGURACAO, ("clientes:write",)
    )

    @mcp.tool(
        name="definir_cliente_ativo",
        annotations=registro.exigir("definir_cliente_ativo").anotacoes,
    )
    async def definir_cliente_ativo(
        cliente_id: Annotated[int, Field(description="Id do cliente.")],
        ativo: Annotated[bool, Field(description="false = desativar.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Ativa ou desativa um cliente (empresa). É reversível: o cadastro e os
        contatos ligados continuam lá. Use quando o cliente deixou de comprar, não
        para corrigir dados."""
        tool = registro.exigir("definir_cliente_ativo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "ativar/desativar o cliente")
        await executor.executar(
            "definir_cliente_ativo",
            "DefinirMyClienteAtivo",
            pb.DefinirMyClienteAtivoRequest(id=cliente_id, ativo=ativo),
        )
        return f"Cliente {cliente_id} {'ativado' if ativo else 'desativado'}."

    registro.registrar(
        "list_contatos_do_cliente", Categoria.LEITURA, ("clientes:read",)
    )

    @mcp.tool(
        name="list_contatos_do_cliente",
        annotations=registro.exigir("list_contatos_do_cliente").anotacoes,
    )
    async def list_contatos_do_cliente(
        cliente_id: Annotated[int, Field(description="Id do cliente.")],
    ) -> list[dict[str, object]]:
        """Lista os contatos (pessoas) ligados a um cliente. Use para saber com quem
        falar numa empresa, ou antes de ligar/desligar um contato com
        `vincular_contato_cliente`."""
        r = await executor.executar(
            "list_contatos_do_cliente",
            "ListMyContatosDoCliente",
            pb.MyClienteIdRequest(id=cliente_id),
        )
        return [para_dict(c) for c in limitar_itens(list(r.contatos), teto)]

    registro.registrar(
        "vincular_contato_cliente", Categoria.CONFIGURACAO, ("clientes:write",)
    )

    @mcp.tool(
        name="vincular_contato_cliente",
        annotations=registro.exigir("vincular_contato_cliente").anotacoes,
    )
    async def vincular_contato_cliente(
        cliente_id: Annotated[int, Field(description="Id do cliente.")],
        contato_id: Annotated[int, Field(description="Id do contato.")],
        vincular: Annotated[
            bool, Field(default=True, description="false = desligar.")
        ] = True,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Liga um contato (pessoa) a um cliente (empresa), ou desliga com
        `vincular=false`. Um contato pode estar em mais de um cliente. Busque os
        dois ids antes."""
        tool = registro.exigir("vincular_contato_cliente")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "ligar/desligar o contato do cliente")
        await executor.executar(
            "vincular_contato_cliente",
            "VincularMyContatoCliente",
            pb.VincularMyContatoClienteRequest(
                cliente_id=cliente_id, contato_id=contato_id, vincular=vincular
            ),
        )
        return "Vínculo criado." if vincular else "Vínculo desfeito."

    # -- Campos personalizados ------------------------------------------------

    registro.registrar("list_campos", Categoria.LEITURA, ("configuracoes:read",))

    @mcp.tool(name="list_campos", annotations=registro.exigir("list_campos").anotacoes)
    async def list_campos(
        fluxo_id: Annotated[
            int, Field(default=0, description="Filtra por fluxo. 0 = todos.")
        ] = 0,
    ) -> list[dict[str, object]]:
        """Lista os campos personalizados do cartão (o que a IA extrai das
        conversas e o que o atendente preenche)."""
        r = await executor.executar(
            "list_campos",
            "ListMyCampos",
            pb.ListMyCamposRequest(fluxo_id=fluxo_id or None),
        )
        return [para_dict(c) for c in limitar_itens(list(r.campos), teto)]

    registro.registrar("create_campo", Categoria.CONFIGURACAO, ("configuracoes:write",))

    @mcp.tool(
        name="create_campo", annotations=registro.exigir("create_campo").anotacoes
    )
    async def create_campo(
        nome: Annotated[str, Field(description="Nome, ex.: 'Tamanho do material'.")],
        tipo: Annotated[TipoCampo, Field(description="Tipo do valor.")] = "texto",
        descricao: str = "",
        escopo: Annotated[
            Literal["GLOBAL", "FLUXO"],
            Field(description="GLOBAL = todos os quadros; FLUXO = só um."),
        ] = "GLOBAL",
        fluxo_id: Annotated[
            int, Field(default=0, description="Obrigatório se escopo=FLUXO.")
        ] = 0,
        opcoes: Annotated[list[str], Field(description="Para tipo 'lista'.")] = [],  # noqa: B006 — o pydantic copia o default a cada chamada
        obrigatorio: bool = False,
        extrair_automaticamente: Annotated[
            bool, Field(default=True, description="A IA preenche sozinha.")
        ] = True,
        extrair_hint: Annotated[
            str, Field(default="", description="Dica para a IA achar o valor.")
        ] = "",
        mostrar_no_card: bool = True,
        ordem: int = 0,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria um campo personalizado no cartão do atendimento. Cada campo com
        extração automática entra no prompt de toda mensagem: crie só o que o
        negócio vai usar."""
        tool = registro.exigir("create_campo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar o campo '{nome}' ({tipo})")
        r = await executor.executar(
            "create_campo",
            "CreateMyCampo",
            pb.CreateMyCampoRequest(
                nome=nome,
                descricao=descricao,
                escopo=escopo,
                fluxo_id=fluxo_id or None,
                tipo=tipo,
                opcoes=_opcoes(opcoes),
                obrigatorio=obrigatorio,
                extrair_automaticamente=extrair_automaticamente,
                extrair_hint=extrair_hint,
                mostrar_no_card=mostrar_no_card,
                ordem=ordem,
            ),
        )
        return f"Campo '{r.campo.nome}' criado com o id {r.campo.id}."

    registro.registrar("update_campo", Categoria.CONFIGURACAO, ("configuracoes:write",))

    @mcp.tool(
        name="update_campo", annotations=registro.exigir("update_campo").anotacoes
    )
    async def update_campo(
        campo_id: Annotated[int, Field(description="Id, de `list_campos`.")],
        nome: str,
        tipo: TipoCampo = "texto",
        descricao: str = "",
        opcoes: Annotated[list[str], Field(description="Lista; vazia = nenhum.")] = [],  # noqa: B006
        obrigatorio: bool = False,
        extrair_automaticamente: bool = True,
        extrair_hint: str = "",
        mostrar_no_card: bool = True,
        ordem: int = 0,
        ativo: bool = True,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Edita um campo personalizado. Todos os atributos são gravados: leia
        com `list_campos` e reenvie o que não muda. Escopo e fluxo não mudam."""
        tool = registro.exigir("update_campo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar o campo personalizado")
        await executor.executar(
            "update_campo",
            "UpdateMyCampo",
            pb.UpdateMyCampoRequest(
                id=campo_id,
                nome=nome,
                descricao=descricao,
                tipo=tipo,
                opcoes=_opcoes(opcoes),
                obrigatorio=obrigatorio,
                extrair_automaticamente=extrair_automaticamente,
                extrair_hint=extrair_hint,
                mostrar_no_card=mostrar_no_card,
                ordem=ordem,
                ativo=ativo,
            ),
        )
        return f"Campo {campo_id} atualizado."

    registro.registrar(
        "desativar_campo", Categoria.DESTRUTIVA, ("configuracoes:write",)
    )

    @mcp.tool(
        name="desativar_campo", annotations=registro.exigir("desativar_campo").anotacoes
    )
    async def desativar_campo(
        campo_id: Annotated[int, Field(description="Id, de `list_campos`.")],
        confirmar: Annotated[str, Field(default="", description="Nome exato.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Desativa um campo personalizado: some das fichas novas e a IA para de
        extraí-lo nas conversas. Os valores já gravados ficam. Exige confirmação com
        o nome exato do campo."""
        tool = registro.exigir("desativar_campo")
        lista = await executor.executar(
            "desativar_campo",
            "ListMyCampos",
            pb.ListMyCamposRequest(),
            contabilizar=False,
        )
        nome = next((c.nome for c in lista.campos if c.id == campo_id), None)
        if nome is None:
            raise ToolError(f"O campo {campo_id} não existe. Confira em `list_campos`.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desativar o campo '{nome}'")
        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desativar_campo", "DesativarMyCampo", pb.MyCampoIdRequest(id=campo_id)
        )
        return f"Campo '{nome}' desativado."

    # -- Estrutura: edição que faltava ---------------------------------------

    registro.registrar("update_etapa_fluxo", Categoria.CONFIGURACAO, ("kanban:admin",))

    @mcp.tool(
        name="update_etapa_fluxo",
        annotations=registro.exigir("update_etapa_fluxo").anotacoes,
    )
    async def update_etapa_fluxo(
        etapa_id: Annotated[int, Field(description="Id, de `list_etapas_fluxo`.")],
        nome: str,
        tipo_etapa: Literal["fila", "trabalho", "espera", "finalizacao"],
        descricao: str = "",
        cor: Annotated[str, Field(default="", description="#RRGGBB.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Renomeia uma etapa ou muda descrição, cor e tipo. Para reordenar use
        `mover_etapa_fluxo`."""
        tool = registro.exigir("update_etapa_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar a etapa")
        await executor.executar(
            "update_etapa_fluxo",
            "UpdateMyEtapaFluxo",
            pb.UpdateMyEtapaFluxoRequest(
                id=etapa_id,
                nome=nome,
                descricao=descricao,
                cor=cor,
                tipo_etapa=tipo_etapa,
            ),
        )
        return f"Etapa {etapa_id} atualizada."

    registro.registrar(
        "update_atendente", Categoria.CONFIGURACAO, ("operacional:admin",)
    )

    @mcp.tool(
        name="update_atendente",
        annotations=registro.exigir("update_atendente").anotacoes,
    )
    async def update_atendente(
        atendente_id: Annotated[int, Field(description="Id, de `list_atendentes`.")],
        nome: str | None = None,
        cargo: str | None = None,
        departamento_id: int | None = None,
        fluxo_id: Annotated[
            int | None, Field(default=None, description="0 = todos os fluxos.")
        ] = None,
        ativo: bool | None = None,
        disponivel: bool | None = None,
        max_atendimentos_simultaneos: int | None = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Edita um atendente: nome, cargo, departamento, fluxo, disponibilidade
        e limite de atendimentos simultâneos. Só o que for informado muda — o
        resto (inclusive o fluxo) é mantido como está."""
        tool = registro.exigir("update_atendente")
        lista = await executor.executar(
            "update_atendente",
            "ListMyAtendentes",
            pb.ListMyAtendentesRequest(),
            contabilizar=False,
        )
        atual = next((a for a in lista.atendentes if a.id == atendente_id), None)
        if atual is None:
            raise ToolError(
                f"O atendente {atendente_id} não existe. Confira em `list_atendentes`."
            )
        pedidos = {
            "nome": nome,
            "cargo": cargo,
            "departamento_id": departamento_id,
            "fluxo_id": fluxo_id,
            "ativo": ativo,
            "disponivel": disponivel,
            "max_atendimentos_simultaneos": max_atendimentos_simultaneos,
        }
        novo: dict[str, Any] = {
            k: (getattr(atual, k) if v is None else v) for k, v in pedidos.items()
        }
        mudancas = [k for k, v in novo.items() if v != getattr(atual, k)]
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool,
                f"alterar {', '.join(mudancas)} de '{atual.nome}'"
                if mudancas
                else f"nada — '{atual.nome}' já está assim",
            )
        await executor.executar(
            "update_atendente",
            "UpdateMyAtendente",
            pb.UpdateMyAtendenteRequest(id=atendente_id, **novo),
        )
        return f"Atendente '{novo['nome']}' atualizado."

    # -- Auditoria ------------------------------------------------------------

    registro.registrar("list_auditoria", Categoria.LEITURA, ("tenant:admin",))

    @mcp.tool(
        name="list_auditoria", annotations=registro.exigir("list_auditoria").anotacoes
    )
    async def list_auditoria(
        origem: Annotated[
            Literal["", "painel", "mcp"],
            Field(default="", description="Filtra quem agiu. Vazio = todos."),
        ] = "",
    ) -> list[dict[str, object]]:
        """A trilha de auditoria do negócio: quem fez o quê e quando, inclusive
        o que agentes de IA fizeram por este conector."""
        r = await executor.executar(
            "list_auditoria",
            "ListMyAuditLog",
            pb.ListMyAuditLogRequest(origem=origem, limit=teto),
        )
        return [para_dict(e) for e in limitar_itens(list(r.entries), teto)]
