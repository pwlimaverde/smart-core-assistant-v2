"""Excluir, reativar e consultar excluídos (doc_dev/planejamento/39).

Desativar e excluir são coisas diferentes, e o agente precisa saber qual está
pedindo:

- **desativar** (as `desativar_*` e `definir_*_ativo`) é reversível — o item sai
  de uso e volta com `reativar_item`;
- **excluir** (`excluir_item`, `excluir_conexao_whatsapp`) é **definitivo**: o
  item some do painel, das seleções, da IA e das estatísticas, não volta, e o
  registro fica só para a auditoria. Se for preciso, cria-se outro.

A confirmação é conferida no servidor: a simulação devolve o nome exato do item,
e a exclusão só acontece se `confirmar` trouxer esse nome.
"""

from __future__ import annotations

from typing import Annotated, Literal

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor, para_dict
from mcp_server.tools.guards import resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

TipoExcluivel = Literal[
    "contato",
    "cliente",
    "atendimento",
    "departamento",
    "fluxo",
    "etapa",
    "atendente",
    "campo",
    "etiqueta",
    "nota",
    "intencao",
    "treinamento",
    "numero_ignorado",
]

TipoComInativo = Literal[
    "contato",
    "cliente",
    "departamento",
    "fluxo",
    "etapa",
    "atendente",
    "campo",
    "etiqueta",
    "numero_ignorado",
]

#: Quem escreve em qualquer um dos tipos. O servidor confere de novo o escopo
#: do tipo pedido — esta lista só decide se a tool aparece.
ESCRITORES = (
    "clientes:write",
    "atendimentos:write",
    "kanban:admin",
    "operacional:admin",
    "configuracoes:write",
    "treinamento:write",
)

TIPO = Field(
    description=(
        "O que excluir. Conexão de WhatsApp não entra aqui: use "
        "`excluir_conexao_whatsapp`."
    )
)
ID = Field(description="Id do item, da `list_*` correspondente.")


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools de exclusão definitiva e de reativação."""

    registro.registrar("excluir_item", Categoria.DESTRUTIVA, ESCRITORES)

    @mcp.tool(
        name="excluir_item", annotations=registro.exigir("excluir_item").anotacoes
    )
    async def excluir_item(
        tipo: Annotated[TipoExcluivel, TIPO],
        id: Annotated[int, ID],
        confirmar: Annotated[
            str,
            Field(
                default="",
                description=(
                    "O nome exato do item, como a simulação (`dry_run=true`) "
                    "mostrou. Sem ele nada é excluído."
                ),
            ),
        ] = "",
        dry_run: Annotated[
            bool,
            Field(default=False, description="Só descrever o que será excluído."),
        ] = False,
    ) -> str:
        """Exclui um item **definitivamente**.

        Excluir não é desativar: o item some do painel, das listas, das
        seleções, da IA e dos relatórios, **não pode ser restaurado** (nem pelo
        dono) e, se for preciso de novo, cria-se outro. O registro fica só para
        a auditoria (`list_excluidos`). Para tirar de uso de forma reversível,
        use as tools de desativar.

        Contato excluído leva junto todas as conversas dele. Departamento,
        fluxo, etapa ou atendente com conversa em andamento não podem ser
        excluídos — o servidor diz o que fazer antes.

        Sempre: `dry_run=true` primeiro, mostre à pessoa o nome e o que vai
        junto, e só então exclua com `confirmar` igual ao nome mostrado.
        """
        tool = registro.exigir("excluir_item")
        if dry_run:
            executor.registrar_simulacao(tool)
            d = await executor.executar(
                "excluir_item",
                "ExcluirMyItem",
                pb.ExcluirMyItemRequest(tipo=tipo, id=id, dry_run=True),
                contabilizar=False,
            )
            if d.em_uso:
                return resultado_dry_run(
                    tool, f"nada — '{d.rotulo}' não pode ser excluído: {d.em_uso}"
                )
            junto = f" e {d.conversas} conversa(s) dele" if d.conversas else ""
            return resultado_dry_run(
                tool,
                f"excluir DEFINITIVAMENTE {tipo} '{d.rotulo}'{junto}. Não há "
                f"restauração. Para confirmar, repita com confirmar='{d.rotulo}'",
            )

        if not confirmar.strip():
            raise ToolError(
                "`excluir_item` é definitivo e exige confirmação. Rode com "
                "`dry_run=true`, mostre o item à pessoa e repita com `confirmar` "
                "igual ao nome que a simulação mostrou."
            )
        r = await executor.executar(
            "excluir_item",
            "ExcluirMyItem",
            pb.ExcluirMyItemRequest(tipo=tipo, id=id, confirmar=confirmar),
        )
        junto = (
            f" com {len(r.atendimentos_excluidos)} conversa(s)"
            if r.atendimentos_excluidos
            else ""
        )
        return (
            f"{tipo} {id} excluído definitivamente{junto}. Não há como restaurar; "
            "o registro fica na auditoria."
        )

    registro.registrar("reativar_item", Categoria.CONFIGURACAO, ESCRITORES)

    @mcp.tool(
        name="reativar_item", annotations=registro.exigir("reativar_item").anotacoes
    )
    async def reativar_item(
        tipo: Annotated[TipoComInativo, Field(description="O tipo do item inativo.")],
        id: Annotated[int, ID],
        dry_run: Annotated[
            bool, Field(default=False, description="Só simular.")
        ] = False,
    ) -> str:
        """Reativa um item **desativado** (volta a ficar em uso).

        Não vale para excluído: a exclusão é definitiva, e o servidor recusa.
        Conversa, nota, intenção e treinamento não têm estado inativo.
        """
        tool = registro.exigir("reativar_item")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"reativar {tipo} {id}")
        await executor.executar(
            "reativar_item",
            "DefinirMyItemAtivo",
            pb.DefinirMyItemAtivoRequest(tipo=tipo, id=id, ativo=True),
        )
        return f"{tipo} {id} reativado."

    registro.registrar("list_excluidos", Categoria.LEITURA, ("tenant:admin",))

    @mcp.tool(
        name="list_excluidos", annotations=registro.exigir("list_excluidos").anotacoes
    )
    async def list_excluidos(
        tipo: Annotated[
            str,
            Field(default="", description="Filtra por tipo. Vazio = todos."),
        ] = "",
    ) -> list[dict[str, object]]:
        """Os itens excluídos do negócio, do mais recente ao mais antigo: tipo,
        nome, quando e por quem. **Somente leitura** — excluído não volta.
        Só administradores."""
        r = await executor.executar(
            "list_excluidos",
            "ListMyExcluidos",
            pb.ListMyExcluidosRequest(tipo=tipo, limite=teto),
        )
        return [para_dict(i) for i in r.itens]
