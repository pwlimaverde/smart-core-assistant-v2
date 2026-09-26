"""Tools do treinamento da IA além da base de conhecimento: intenções
(QueryCompose), leitura de um treinamento, treinamento a partir de arquivo,
teste de pergunta e a revisão das avaliações do teste.
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
from mcp_server.tools.guards import exigir_confirmacao, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

DRY_RUN = Field(default=False, description="Só simular.")


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools de treinamento da IA."""

    # -- Base de conhecimento: o que faltava --------------------------------

    registro.registrar("get_treinamento", Categoria.LEITURA, ("treinamento:read",))

    @mcp.tool(
        name="get_treinamento", annotations=registro.exigir("get_treinamento").anotacoes
    )
    async def get_treinamento(
        treinamento_id: Annotated[
            int, Field(description="Id, de `list_treinamentos`.")
        ],
    ) -> dict[str, object]:
        """Lê um treinamento inteiro, com o texto e o estado da extração quando
        veio de arquivo."""
        r = await executor.executar(
            "get_treinamento",
            "GetMyTreinamento",
            pb.GetMyTreinamentoRequest(id=treinamento_id),
        )
        return para_dict(r.treinamento)

    registro.registrar(
        "create_treinamento_com_arquivo", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="create_treinamento_com_arquivo",
        annotations=registro.exigir("create_treinamento_com_arquivo").anotacoes,
    )
    async def create_treinamento_com_arquivo(
        tag: Annotated[str, Field(description="Rótulo curto do assunto.")],
        nome_arquivo: Annotated[str, Field(description="Ex.: 'tabela.pdf'.")],
        mimetype: Annotated[str, Field(description="Ex.: 'application/pdf'.")],
        conteudo_base64: Annotated[str, Field(description="O arquivo em base64.")],
        grupo: str = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria um treinamento a partir de um arquivo (PDF, DOCX, planilha,
        texto). O texto é extraído no servidor; depois finalize com
        `finalizar_treinamento`."""
        tool = registro.exigir("create_treinamento_com_arquivo")
        dados = decodificar_arquivo(conteudo_base64)
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, f"criar o treinamento '{tag}' a partir de '{nome_arquivo}'"
            )
        up = await executor.executar(
            "create_treinamento_com_arquivo",
            "SolicitarUploadTreinamento",
            pb.SolicitarUploadTreinamentoRequest(
                nome_arquivo=nome_arquivo, mimetype=mimetype, bytes=len(dados)
            ),
            contabilizar=False,
        )
        await executor.enviar_arquivo(up.url_upload, up.content_type or mimetype, dados)
        r = await executor.executar(
            "create_treinamento_com_arquivo",
            "CreateMyTreinamentoComArquivo",
            pb.CreateMyTreinamentoComArquivoRequest(
                tag=tag,
                grupo=grupo,
                chave=up.chave,
                nome_arquivo=nome_arquivo,
                mimetype=mimetype,
            ),
        )
        return (
            f"Treinamento '{tag}' criado com o id {r.treinamento.id} "
            f"(extração: {r.treinamento.extracao_status or 'pendente'}). "
            "Ainda precisa ser finalizado."
        )

    # -- Intenções (QueryCompose) --------------------------------------------

    registro.registrar("list_intencoes", Categoria.LEITURA, ("treinamento:read",))

    @mcp.tool(
        name="list_intencoes", annotations=registro.exigir("list_intencoes").anotacoes
    )
    async def list_intencoes() -> list[dict[str, object]]:
        """Lista as intenções que a IA reconhece nas mensagens (o "QueryCompose"
        da v1): tag, grupo, descrição, exemplo e o comportamento que cada uma
        dispara."""
        r = await executor.executar(
            "list_intencoes", "ListMyIntents", pb.ListMyIntentsRequest()
        )
        return [para_dict(i) for i in limitar_itens(list(r.intents), 200)]

    def _dados_intencao(
        tag: str, grupo: str, descricao: str, exemplo: str, comportamento: str
    ) -> pb.MyIntentDados:
        return pb.MyIntentDados(
            tag=tag,
            grupo=grupo,
            descricao=descricao,
            exemplo=exemplo,
            comportamento=comportamento,
        )

    registro.registrar(
        "create_intencao", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="create_intencao", annotations=registro.exigir("create_intencao").anotacoes
    )
    async def create_intencao(
        tag: Annotated[str, Field(description="Até 40 caracteres, ex.: 'saudacao'.")],
        grupo: Annotated[str, Field(description="Até 40, ex.: 'comunicacao_basica'.")],
        descricao: Annotated[str, Field(description="Quando a intenção ocorre.")],
        exemplo: Annotated[str, Field(description="Mensagens típicas do cliente.")],
        comportamento: Annotated[
            str, Field(description="O que o assistente deve fazer nesse caso.")
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria uma intenção. Tag+grupo são únicos: confira `list_intencoes`."""
        tool = registro.exigir("create_intencao")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar a intenção '{grupo}/{tag}'")
        r = await executor.executar(
            "create_intencao",
            "CreateMyIntent",
            _dados_intencao(tag, grupo, descricao, exemplo, comportamento),
        )
        return f"Intenção '{grupo}/{tag}' criada com o id {r.intent.id}."

    registro.registrar(
        "update_intencao", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="update_intencao", annotations=registro.exigir("update_intencao").anotacoes
    )
    async def update_intencao(
        intencao_id: Annotated[int, Field(description="Id, de `list_intencoes`.")],
        tag: str,
        grupo: str,
        descricao: str,
        exemplo: str,
        comportamento: str,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Edita uma intenção. Todos os campos são gravados."""
        tool = registro.exigir("update_intencao")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar a intenção")
        await executor.executar(
            "update_intencao",
            "UpdateMyIntent",
            pb.UpdateMyIntentRequest(
                id=intencao_id,
                dados=_dados_intencao(tag, grupo, descricao, exemplo, comportamento),
            ),
        )
        return f"Intenção {intencao_id} atualizada."

    registro.registrar("remover_intencao", Categoria.DESTRUTIVA, ("treinamento:write",))

    @mcp.tool(
        name="remover_intencao",
        annotations=registro.exigir("remover_intencao").anotacoes,
    )
    async def remover_intencao(
        intencao_id: Annotated[int, Field(description="Id, de `list_intencoes`.")],
        confirmar: Annotated[
            str, Field(default="", description="A tag exata da intenção.")
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Remove uma intenção. Não tem desfazer."""
        tool = registro.exigir("remover_intencao")
        lista = await executor.executar(
            "remover_intencao",
            "ListMyIntents",
            pb.ListMyIntentsRequest(),
            contabilizar=False,
        )
        tag = next((i.tag for i in lista.intents if i.id == intencao_id), None)
        if tag is None:
            raise ToolError(
                f"A intenção {intencao_id} não existe. Confira `list_intencoes`."
            )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"remover a intenção '{tag}'")
        exigir_confirmacao(tool, tag, confirmar or None)
        await executor.executar(
            "remover_intencao", "RemoveMyIntent", pb.MyIntentIdRequest(id=intencao_id)
        )
        return f"Intenção '{tag}' removida."

    # -- Teste de resposta e avaliações --------------------------------------

    registro.registrar("testar_pergunta", Categoria.LEITURA, ("treinamento:read",))

    @mcp.tool(
        name="testar_pergunta", annotations=registro.exigir("testar_pergunta").anotacoes
    )
    async def testar_pergunta(
        pergunta: Annotated[
            str, Field(description="Mensagem como o cliente mandaria.")
        ],
    ) -> dict[str, object]:
        """Pergunta ao assistente sem enviar nada a cliente: devolve a resposta
        que ele daria, os trechos da base usados, a confiança e se transferiria
        para uma pessoa. Use para validar treinamentos e intenções."""
        r = await executor.executar(
            "testar_pergunta",
            "TestarPergunta",
            pb.TestarPerguntaRequest(pergunta=pergunta),
        )
        return para_dict(r)

    registro.registrar(
        "registrar_avaliacao_teste", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="registrar_avaliacao_teste",
        annotations=registro.exigir("registrar_avaliacao_teste").anotacoes,
    )
    async def registrar_avaliacao_teste(
        pergunta: str,
        resposta_obtida: str,
        avaliacao: Literal["boa", "ruim"],
        resposta_correta: Annotated[
            str, Field(default="", description="A resposta certa, se ruim.")
        ] = "",
        comportamento_aplicado: str = "",
        confiabilidade: float = 0.0,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Registra a avaliação de um teste (o 👍/👎 da tela de teste)."""
        tool = registro.exigir("registrar_avaliacao_teste")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "registrar a avaliação do teste")
        r = await executor.executar(
            "registrar_avaliacao_teste",
            "RegistrarFeedbackTeste",
            pb.RegistrarFeedbackTesteRequest(
                pergunta=pergunta,
                resposta_obtida=resposta_obtida,
                resposta_correta=resposta_correta,
                avaliacao=avaliacao,
                comportamento_aplicado=comportamento_aplicado,
                confiabilidade=confiabilidade,
            ),
        )
        return f"Avaliação registrada (id {r.id})."

    registro.registrar(
        "list_avaliacoes_de_teste", Categoria.LEITURA, ("treinamento:read",)
    )

    @mcp.tool(
        name="list_avaliacoes_de_teste",
        annotations=registro.exigir("list_avaliacoes_de_teste").anotacoes,
    )
    async def list_avaliacoes_de_teste() -> list[dict[str, object]]:
        """As avaliações do teste ainda não tratadas, as ruins primeiro."""
        r = await executor.executar(
            "list_avaliacoes_de_teste",
            "ListMyAvaliacoesDeTeste",
            pb.ListMyAvaliacoesDeTesteRequest(limite=teto),
        )
        return [para_dict(i) for i in limitar_itens(list(r.itens), teto)]

    registro.registrar(
        "marcar_avaliacao_tratada", Categoria.CONFIGURACAO, ("treinamento:write",)
    )

    @mcp.tool(
        name="marcar_avaliacao_tratada",
        annotations=registro.exigir("marcar_avaliacao_tratada").anotacoes,
    )
    async def marcar_avaliacao_tratada(
        avaliacao_id: Annotated[int, Field(description="Id da avaliação.")],
        virou_treinamento: Annotated[
            bool, Field(description="true = a correção virou treinamento.")
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Tira a avaliação da lista de revisão."""
        tool = registro.exigir("marcar_avaliacao_tratada")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "tirar a avaliação da lista de revisão")
        await executor.executar(
            "marcar_avaliacao_tratada",
            "MarcarAvaliacaoTratada",
            pb.MarcarAvaliacaoTratadaRequest(
                id=avaliacao_id, virou_treinamento=virou_treinamento
            ),
        )
        return f"Avaliação {avaliacao_id} tratada."
