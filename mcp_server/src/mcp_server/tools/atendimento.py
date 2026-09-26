"""Tools do atendimento: a ficha, o histórico e tudo o que o atendente faz no
quadro e na conversa.

Paridade com o app: cada ação que uma pessoa faz na tela de conversa ou no
cartão do Kanban tem aqui a sua tool, com o mesmo escopo que o `runtime_api`
exige para ela. Presença ("digitando…") fica de fora de propósito: é sinal de
interface, não ação sobre o atendimento.
"""

from __future__ import annotations

from typing import Annotated, Literal

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import (
    Executor,
    decodificar_arquivo,
    limitar_itens,
    para_dict,
)
from mcp_server.tools.guards import (
    exigir_confirmacao,
    resultado_dry_run,
)
from mcp_server.tools.registry import Categoria, Registro

ATENDIMENTO_ID = Field(description="Id do atendimento, de `list_atendimentos`.")
DRY_RUN = Field(default=False, description="Só simular.")


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools do atendimento."""

    # -- Leitura -------------------------------------------------------------

    registro.registrar(
        "get_ficha_atendimento", Categoria.LEITURA, ("atendimentos:read",)
    )

    @mcp.tool(
        name="get_ficha_atendimento",
        annotations=registro.exigir("get_ficha_atendimento").anotacoes,
    )
    async def get_ficha_atendimento(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
    ) -> dict[str, object]:
        """A ficha de um atendimento: etiquetas aplicadas (e o catálogo de
        etiquetas do negócio), notas internas, campos personalizados com valor,
        dados do contato que a IA encontrou e se o bot responde nesta conversa.

        Use antes de etiquetar, anotar ou preencher campo: é daqui que saem os
        ids de etiqueta e de campo.
        """
        r = await executor.executar(
            "get_ficha_atendimento",
            "GetDetalheAtendimento",
            pb.AtendimentoIdRequest(atendimento_id=atendimento_id),
        )
        return para_dict(r)

    registro.registrar(
        "list_timeline_atendimento", Categoria.LEITURA, ("atendimentos:read",)
    )

    @mcp.tool(
        name="list_timeline_atendimento",
        annotations=registro.exigir("list_timeline_atendimento").anotacoes,
    )
    async def list_timeline_atendimento(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
    ) -> list[dict[str, object]]:
        """O que aconteceu com o atendimento, em ordem: mudanças de etapa, de
        status, de responsável, transferências — e se foi pessoa ou automação.

        Use para responder "por que esta conversa está aqui" ou "quem mexeu".
        """
        r = await executor.executar(
            "list_timeline_atendimento",
            "ListarTimelineAtendimento",
            pb.ListarTimelineRequest(atendimento_id=atendimento_id),
        )
        return [para_dict(e) for e in limitar_itens(list(r.eventos), teto)]

    registro.registrar(
        "list_atendimentos_do_contato", Categoria.LEITURA, ("atendimentos:read",)
    )

    @mcp.tool(
        name="list_atendimentos_do_contato",
        annotations=registro.exigir("list_atendimentos_do_contato").anotacoes,
    )
    async def list_atendimentos_do_contato(
        contato_id: Annotated[int, Field(description="Id do contato.")],
    ) -> list[dict[str, object]]:
        """Os atendimentos anteriores de um contato, do mais recente ao mais
        antigo. Use para ver o histórico de relacionamento com um cliente."""
        r = await executor.executar(
            "list_atendimentos_do_contato",
            "ListarAtendimentosDoContato",
            pb.ListarAtendimentosDoContatoRequest(contato_id=contato_id, limit=teto),
        )
        return [para_dict(a) for a in limitar_itens(list(r.atendimentos), teto)]

    registro.registrar(
        "list_midias_atendimento", Categoria.LEITURA, ("atendimentos:read",)
    )

    @mcp.tool(
        name="list_midias_atendimento",
        annotations=registro.exigir("list_midias_atendimento").anotacoes,
    )
    async def list_midias_atendimento(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
    ) -> list[dict[str, object]]:
        """Fotos, áudios, vídeos e documentos trocados na conversa, com um link
        temporário para abrir cada um.

        O link expira em minutos e é credencial: não o repita para terceiros nem
        o guarde.
        """
        r = await executor.executar(
            "list_midias_atendimento",
            "ListarMidiasAtendimento",
            pb.ListarMidiasAtendimentoRequest(
                atendimento_id=atendimento_id, limit=teto, offset=0
            ),
        )
        return [para_dict(m) for m in limitar_itens(list(r.midias), teto)]

    registro.registrar(
        "get_contato_do_atendimento", Categoria.LEITURA, ("atendimentos:read",)
    )

    @mcp.tool(
        name="get_contato_do_atendimento",
        annotations=registro.exigir("get_contato_do_atendimento").anotacoes,
    )
    async def get_contato_do_atendimento(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
    ) -> dict[str, object]:
        """Nome, telefone e foto do contato de um atendimento. Use para saber com quem
        é a conversa antes de responder, sem precisar buscar em `list_contatos`."""
        r = await executor.executar(
            "get_contato_do_atendimento",
            "ObterContatoDoAtendimento",
            pb.ObterContatoDoAtendimentoRequest(atendimento_id=atendimento_id),
        )
        return para_dict(r)

    registro.registrar("exportar_quadro", Categoria.LEITURA, ("tenant:admin",))

    @mcp.tool(
        name="exportar_quadro", annotations=registro.exigir("exportar_quadro").anotacoes
    )
    async def exportar_quadro(
        status: Annotated[
            str, Field(default="", description="Filtro de status. Vazio = todos.")
        ] = "",
        departamento_id: Annotated[
            int, Field(default=0, description="0 = todos os departamentos.")
        ] = 0,
        busca: Annotated[str, Field(default="", description="Texto livre.")] = "",
    ) -> dict[str, object]:
        """Exporta o quadro de atendimentos em CSV (o mesmo arquivo do botão
        "Exportar" do app). Só para administradores do negócio."""
        r = await executor.executar(
            "exportar_quadro",
            "ExportarQuadro",
            pb.ExportarQuadroRequest(
                status=status, departamento_id=departamento_id, busca=busca
            ),
        )
        return {"linhas": r.linhas, "csv": bytes(r.csv).decode("utf-8", "replace")}

    # -- Ações no quadro -----------------------------------------------------

    registro.registrar(
        "iniciar_atendimento", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="iniciar_atendimento",
        annotations=registro.exigir("iniciar_atendimento").anotacoes,
    )
    async def iniciar_atendimento(
        contato_id: Annotated[int, Field(description="Id do contato.")],
        fluxo_id: Annotated[int, Field(description="Fluxo onde o cartão entra.")],
        etapa_inicial_id: Annotated[
            int, Field(description="Etapa de entrada, de `list_etapas_fluxo`.")
        ],
        assunto: Annotated[str, Field(default="", description="Assunto.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Abre um atendimento para um contato, como o "Iniciar atendimento" do
        app. Se já houver um aberto, devolve esse em vez de duplicar."""
        tool = registro.exigir("iniciar_atendimento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"abrir um atendimento para o contato {contato_id}"
            )
        r = await executor.executar(
            "iniciar_atendimento",
            "IniciarAtendimentoManual",
            pb.IniciarAtendimentoManualRequest(
                contato_id=contato_id,
                fluxo_id=fluxo_id,
                etapa_inicial_id=etapa_inicial_id,
                assunto=assunto or None,
            ),
        )
        if r.ja_existia:
            return f"O contato já tinha o atendimento {r.atendimento_id} aberto."
        return f"Atendimento {r.atendimento_id} aberto."

    registro.registrar(
        "mover_atendimento_etapa", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="mover_atendimento_etapa",
        annotations=registro.exigir("mover_atendimento_etapa").anotacoes,
    )
    async def mover_atendimento_etapa(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        etapa_destino_id: Annotated[
            int, Field(description="Etapa de destino, de `list_etapas_fluxo`.")
        ],
        motivo: Annotated[str, Field(default="", description="Por quê.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Move o cartão para outra etapa do mesmo fluxo (arrastar no Kanban).
        Para outro fluxo, use `transferir_para_fluxo`."""
        tool = registro.exigir("mover_atendimento_etapa")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool,
                f"mover o atendimento {atendimento_id} para a etapa {etapa_destino_id}",
            )
        await executor.executar(
            "mover_atendimento_etapa",
            "MoveAtendimentoEtapa",
            pb.MoveAtendimentoEtapaRequest(
                atendimento_id=atendimento_id,
                etapa_destino_id=etapa_destino_id,
                motivo=motivo,
            ),
        )
        return f"Atendimento {atendimento_id} movido."

    registro.registrar(
        "set_atendimento_status", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="set_atendimento_status",
        annotations=registro.exigir("set_atendimento_status").anotacoes,
    )
    async def set_atendimento_status(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        status: Annotated[
            Literal[
                "fila",
                "em_atendimento",
                "pendencia",
                "resolvido",
                "cancelado",
                "arquivado",
            ],
            Field(description="Nova situação (o vocabulário do quadro)."),
        ],
        motivo: Annotated[str, Field(default="", description="Por quê.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Muda a situação do atendimento (resolver, cancelar, pôr em espera,
        reabrir). O cartão vai para a coluna correspondente."""
        tool = registro.exigir("set_atendimento_status")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"marcar o atendimento {atendimento_id} como '{status}'"
            )
        r = await executor.executar(
            "set_atendimento_status",
            "SetAtendimentoStatus",
            pb.SetAtendimentoStatusRequest(
                atendimento_id=atendimento_id, status=status, motivo=motivo
            ),
        )
        return f"Atendimento {atendimento_id} agora está '{r.status or status}'."

    registro.registrar(
        "atribuir_atendimento", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="atribuir_atendimento",
        annotations=registro.exigir("atribuir_atendimento").anotacoes,
    )
    async def atribuir_atendimento(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        atendente_id: Annotated[
            int,
            Field(
                default=0,
                description="Atendente, de `list_atendentes`. 0 = a quem autorizou.",
            ),
        ] = 0,
        devolver_para_fila: Annotated[
            bool, Field(default=False, description="Tira o responsável.")
        ] = False,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Define quem é o responsável pelo atendimento, ou o devolve à fila com
        `devolver_para_fila=true`. Use `list_atendentes` para achar o id da pessoa."""
        tool = registro.exigir("atribuir_atendimento")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"mudar o responsável do atendimento {atendimento_id}"
            )
        r = await executor.executar(
            "atribuir_atendimento",
            "AtribuirAtendimento",
            pb.AtribuirAtendimentoRequest(
                atendimento_id=atendimento_id,
                atendente_id=atendente_id,
                devolver_para_fila=devolver_para_fila,
            ),
        )
        if not r.atribuido:
            return f"Não foi possível atribuir: {r.motivo or 'recusado'}."
        return "Responsável atualizado."

    registro.registrar(
        "definir_prioridade", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="definir_prioridade",
        annotations=registro.exigir("definir_prioridade").anotacoes,
    )
    async def definir_prioridade(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        prioridade: Annotated[
            Literal["baixa", "normal", "alta", "urgente"], Field(description="Nível.")
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Muda a prioridade do atendimento (baixa, normal, alta, urgente). A
        prioridade ordena o quadro e os filtros do app; use com parcimônia, senão
        tudo vira urgente."""
        tool = registro.exigir("definir_prioridade")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"prioridade '{prioridade}'")
        await executor.executar(
            "definir_prioridade",
            "DefinirPrioridade",
            pb.DefinirPrioridadeRequest(
                atendimento_id=atendimento_id, prioridade=prioridade
            ),
        )
        return f"Prioridade '{prioridade}' definida."

    registro.registrar(
        "transferir_para_fluxo", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="transferir_para_fluxo",
        annotations=registro.exigir("transferir_para_fluxo").anotacoes,
    )
    async def transferir_para_fluxo(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        fluxo_id: Annotated[int, Field(description="Fluxo de destino.")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Transfere o atendimento para outro fluxo (outro quadro), entrando na
        etapa inicial dele."""
        tool = registro.exigir("transferir_para_fluxo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"transferir para o fluxo {fluxo_id}")
        r = await executor.executar(
            "transferir_para_fluxo",
            "TransferirParaFluxo",
            pb.TransferirParaFluxoRequest(
                atendimento_id=atendimento_id, fluxo_id=fluxo_id
            ),
        )
        if not r.transferido:
            return f"Transferência recusada: {r.motivo or 'sem motivo informado'}."
        return f"Transferido para '{r.fluxo_nome}', etapa '{r.etapa_nome}'."

    registro.registrar(
        "marcar_atendimento_lido", Categoria.CONFIGURACAO, ("atendimentos:read",)
    )

    @mcp.tool(
        name="marcar_atendimento_lido",
        annotations=registro.exigir("marcar_atendimento_lido").anotacoes,
    )
    async def marcar_atendimento_lido(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Marca as mensagens do cliente como lidas, zerando o contador do cartão. Use
        depois de ler a conversa com `get_thread`, como faria o atendente ao
        abri-la."""
        tool = registro.exigir("marcar_atendimento_lido")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, "marcar como lidas as mensagens do atendimento"
            )
        r = await executor.executar(
            "marcar_atendimento_lido",
            "MarcarAtendimentoLido",
            pb.MarcarAtendimentoLidoRequest(atendimento_id=atendimento_id),
        )
        return f"{r.marcadas} mensagem(ns) marcada(s) como lida(s)."

    registro.registrar(
        "marcar_revisado", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="marcar_revisado", annotations=registro.exigir("marcar_revisado").anotacoes
    )
    async def marcar_revisado(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Tira a marca "A revisar" de uma conversa em que a IA respondeu com
        pouca confiança, depois de alguém conferir a resposta."""
        tool = registro.exigir("marcar_revisado")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "tirar a marca 'A revisar' do atendimento")
        await executor.executar(
            "marcar_revisado",
            "MarcarRevisado",
            pb.MarcarRevisadoRequest(atendimento_id=atendimento_id),
        )
        return "Marcado como revisado."

    registro.registrar(
        "definir_bot_da_conversa", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="definir_bot_da_conversa",
        annotations=registro.exigir("definir_bot_da_conversa").anotacoes,
    )
    async def definir_bot_da_conversa(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        habilitado: Annotated[
            bool, Field(description="true = a IA volta a responder nesta conversa.")
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Liga ou desliga a IA **só nesta conversa** (o interruptor da ficha).
        Desligar é o que se faz quando uma pessoa assume; para o número inteiro use
        `definir_resposta_bot_conexao`."""
        tool = registro.exigir("definir_bot_da_conversa")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "ligar/desligar a IA nesta conversa")
        r = await executor.executar(
            "definir_bot_da_conversa",
            "DefinirBotDaConversa",
            pb.DefinirBotDaConversaRequest(
                atendimento_id=atendimento_id, habilitado=habilitado
            ),
        )
        return "IA ligada nesta conversa." if r.habilitado else "IA desligada."

    # -- Notas, etiquetas e campos -------------------------------------------

    registro.registrar("create_nota", Categoria.CONFIGURACAO, ("atendimentos:write",))

    @mcp.tool(name="create_nota", annotations=registro.exigir("create_nota").anotacoes)
    async def create_nota(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        texto: Annotated[str, Field(description="Nota interna (o cliente não vê).")],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Acrescenta uma nota interna ao atendimento. O cliente não vê. Use para
        registrar combinados, pendências e contexto para o próximo atendente."""
        tool = registro.exigir("create_nota")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "criar uma nota interna")
        r = await executor.executar(
            "create_nota",
            "CreateNota",
            pb.CreateNotaRequest(atendimento_id=atendimento_id, texto=texto),
        )
        return f"Nota {r.nota.id} criada."

    registro.registrar("remover_nota", Categoria.DESTRUTIVA, ("atendimentos:write",))

    @mcp.tool(
        name="remover_nota", annotations=registro.exigir("remover_nota").anotacoes
    )
    async def remover_nota(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        nota_id: Annotated[int, Field(description="Id, de `get_ficha_atendimento`.")],
        confirmar: Annotated[
            str,
            Field(default="", description="O id da nota de novo, como confirmação."),
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Remove uma nota interna. Não tem desfazer. A nota precisa ser deste
        atendimento — o par é conferido no servidor."""
        tool = registro.exigir("remover_nota")
        ficha = await executor.executar(
            "remover_nota",
            "GetDetalheAtendimento",
            pb.AtendimentoIdRequest(atendimento_id=atendimento_id),
            contabilizar=False,
        )
        if not any(n.id == nota_id for n in ficha.notas):
            raise ToolError(
                f"A nota {nota_id} não é do atendimento {atendimento_id}. "
                "Confira em `get_ficha_atendimento`."
            )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"remover a nota {nota_id}")
        exigir_confirmacao(tool, str(nota_id), confirmar or None)
        await executor.executar(
            "remover_nota",
            "RemoverNota",
            pb.RemoverNotaRequest(nota_id=nota_id, atendimento_id=atendimento_id),
        )
        return f"Nota {nota_id} removida."

    registro.registrar(
        "create_etiqueta", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="create_etiqueta", annotations=registro.exigir("create_etiqueta").anotacoes
    )
    async def create_etiqueta(
        nome: Annotated[str, Field(description="Nome da etiqueta.")],
        cor: Annotated[str, Field(default="", description="#RRGGBB.")] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria uma etiqueta no catálogo do negócio. Confira antes, em
        `get_ficha_atendimento`, se já não existe uma igual."""
        tool = registro.exigir("create_etiqueta")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "criar uma etiqueta no catálogo")
        r = await executor.executar(
            "create_etiqueta",
            "CreateEtiqueta",
            pb.CreateEtiquetaRequest(nome=nome, cor=cor),
        )
        return f"Etiqueta '{r.etiqueta.nome}' criada com o id {r.etiqueta.id}."

    registro.registrar(
        "update_etiqueta", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="update_etiqueta", annotations=registro.exigir("update_etiqueta").anotacoes
    )
    async def update_etiqueta(
        etiqueta_id: Annotated[int, Field(description="Id da etiqueta.")],
        nome: Annotated[str, Field(description="Nome (obrigatório).")],
        cor: Annotated[str, Field(default="", description="#RRGGBB.")] = "",
        descricao: Annotated[
            str,
            Field(
                default="",
                description="Quando usar — a IA lê isto para etiquetar sozinha.",
            ),
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Renomeia uma etiqueta do catálogo ou muda cor e descrição. A descrição diz
        quando usar a etiqueta — é o que a IA lê para etiquetar sozinha."""
        tool = registro.exigir("update_etiqueta")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar a etiqueta")
        r = await executor.executar(
            "update_etiqueta",
            "UpdateEtiqueta",
            pb.UpdateEtiquetaRequest(
                id=etiqueta_id, nome=nome, cor=cor, descricao=descricao
            ),
        )
        return f"Etiqueta '{r.etiqueta.nome}' atualizada."

    registro.registrar(
        "desativar_etiqueta", Categoria.DESTRUTIVA, ("atendimentos:write",)
    )

    @mcp.tool(
        name="desativar_etiqueta",
        annotations=registro.exigir("desativar_etiqueta").anotacoes,
    )
    async def desativar_etiqueta(
        etiqueta_id: Annotated[int, Field(description="Id da etiqueta.")],
        atendimento_id: Annotated[
            int,
            Field(
                description=(
                    "Qualquer atendimento: é de onde o catálogo de etiquetas é "
                    "lido para conferir o nome."
                )
            ),
        ],
        confirmar: Annotated[
            str, Field(default="", description="Nome exato da etiqueta.")
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Tira a etiqueta do catálogo do negócio: some de todos os atendimentos.
        Exige confirmação com o nome exato."""
        tool = registro.exigir("desativar_etiqueta")
        ficha = await executor.executar(
            "desativar_etiqueta",
            "GetDetalheAtendimento",
            pb.AtendimentoIdRequest(atendimento_id=atendimento_id),
            contabilizar=False,
        )
        nome = next((e.nome for e in ficha.catalogo if e.id == etiqueta_id), None)
        if nome is None:
            raise ToolError(
                f"A etiqueta {etiqueta_id} não está no catálogo. Confira em "
                "`get_ficha_atendimento`."
            )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"desativar a etiqueta '{nome}'")
        exigir_confirmacao(tool, nome, confirmar or None)
        await executor.executar(
            "desativar_etiqueta",
            "DesativarEtiqueta",
            pb.DesativarEtiquetaRequest(id=etiqueta_id),
        )
        return f"Etiqueta '{nome}' desativada."

    registro.registrar(
        "aplicar_etiqueta", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="aplicar_etiqueta",
        annotations=registro.exigir("aplicar_etiqueta").anotacoes,
    )
    async def aplicar_etiqueta(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        etiqueta_id: Annotated[int, Field(description="Id da etiqueta.")],
        aplicar: Annotated[
            bool, Field(default=True, description="false = tirar do atendimento.")
        ] = True,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Coloca ou tira uma etiqueta de um atendimento. Tirar uma etiqueta que
        a IA pôs impede a IA de recolocá-la nesta conversa."""
        tool = registro.exigir("aplicar_etiqueta")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "aplicar/retirar a etiqueta do atendimento")
        await executor.executar(
            "aplicar_etiqueta",
            "AlternarEtiqueta",
            pb.AlternarEtiquetaRequest(
                atendimento_id=atendimento_id, etiqueta_id=etiqueta_id, aplicar=aplicar
            ),
        )
        return "Etiqueta aplicada." if aplicar else "Etiqueta retirada."

    registro.registrar(
        "set_valor_campo", Categoria.CONFIGURACAO, ("atendimentos:write",)
    )

    @mcp.tool(
        name="set_valor_campo", annotations=registro.exigir("set_valor_campo").anotacoes
    )
    async def set_valor_campo(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        campo_id: Annotated[int, Field(description="Id do campo, de `list_campos`.")],
        valor_json: Annotated[
            str,
            Field(
                description=(
                    'Valor em JSON conforme o tipo: texto "\\"abc\\"", número "12", '
                    'data "\\"2026-09-25\\"", opção "\\"id_da_opcao\\"". '
                    "Vazio limpa."
                )
            ),
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Preenche um campo personalizado do cartão. Valor dado por pessoa não é
        sobrescrito depois pela IA."""
        tool = registro.exigir("set_valor_campo")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "gravar o valor do campo")
        await executor.executar(
            "set_valor_campo",
            "SetMyValorCampo",
            pb.SetMyValorCampoRequest(
                atendimento_id=atendimento_id, campo_id=campo_id, valor_json=valor_json
            ),
        )
        return "Campo atualizado."

    # -- Envio de mídia ------------------------------------------------------

    registro.registrar("send_media", Categoria.ENVIO, ("atendimentos:write",))

    @mcp.tool(name="send_media", annotations=registro.exigir("send_media").anotacoes)
    async def send_media(
        atendimento_id: Annotated[int, ATENDIMENTO_ID],
        nome_arquivo: Annotated[str, Field(description="Ex.: 'orcamento.pdf'.")],
        mimetype: Annotated[str, Field(description="Ex.: 'application/pdf'.")],
        conteudo_base64: Annotated[
            str, Field(description="O arquivo em base64 (até 16 MB).")
        ],
        legenda: Annotated[str, Field(default="", description="Texto junto.")] = "",
        confirmar: Annotated[
            str,
            Field(
                default="",
                description=(
                    "O `contato_id` deste atendimento (de `list_atendimentos`). "
                    "Preencha só depois de conferir o envio com a pessoa."
                ),
            ),
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Envia um arquivo (foto, PDF, áudio, vídeo) ao WhatsApp do cliente.

        **Não tem desfazer**: o arquivo chega ao telefone da pessoa. Mostre o que
        vai sair e confirme antes.
        """
        tool = registro.exigir("send_media")
        dados = decodificar_arquivo(conteudo_base64)
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool,
                f"enviar '{nome_arquivo}' ({len(dados)} bytes) no atendimento "
                f"{atendimento_id}",
            )
        contato = await executor.executar(
            "send_media",
            "ObterContatoDoAtendimento",
            pb.ObterContatoDoAtendimentoRequest(atendimento_id=atendimento_id),
            contabilizar=False,
        )
        exigir_confirmacao(tool, str(contato.contato_id), confirmar or None)
        up = await executor.executar(
            "send_media",
            "SolicitarUploadMidia",
            pb.SolicitarUploadMidiaRequest(
                atendimento_id=atendimento_id,
                nome_arquivo=nome_arquivo,
                mimetype=mimetype,
                bytes=len(dados),
            ),
            contabilizar=False,
        )
        await executor.enviar_arquivo(up.url_upload, up.content_type or mimetype, dados)
        r = await executor.executar(
            "send_media",
            "EnviarMidiaAtendimento",
            pb.EnviarMidiaAtendimentoRequest(
                atendimento_id=atendimento_id,
                chave=up.chave,
                mimetype=mimetype,
                nome_arquivo=nome_arquivo,
                legenda=legenda,
            ),
        )
        return f"Arquivo enviado (mensagem {r.message_id})."
