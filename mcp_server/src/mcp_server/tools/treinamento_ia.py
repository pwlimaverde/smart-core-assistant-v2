"""Tools do treinamento da IA além da base de conhecimento: intenções
(QueryCompose), leitura de um treinamento, treinamento a partir de arquivo,
teste de pergunta e a revisão das avaliações do teste.
"""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import (
    Executor,
    decodificar_arquivo,
    limitar_itens,
    para_dict,
)
from mcp_server.tools.guards import (
    mesmo_nome,
    recusar_duplicata,
    resultado_dry_run,
)
from mcp_server.tools.registry import Categoria, Registro

DRY_RUN = Field(default=False, description="Só simular.")


# Descrições dos parâmetros de coleta (motor Jev). No escopo do módulo: com
# `from __future__ import annotations`, as anotações são resolvidas nos
# globais quando o FastMCP monta o schema.
CAMPOS_COLETA = Field(
    description=(
        "Motor Jev — dados essenciais que o bot pede ao cliente nesta intenção, "
        "em ordem de prioridade: tipo de entidade (ex.: 'quantidade_tiragem') "
        "ou slug de campo do cartão. Até 10."
    )
)
MAX_PERGUNTAS = Field(
    description="Quantos dados, no máximo, o bot pede numa mensagem (1 a 5)."
)
APOS_COLETA = Field(
    description=(
        "Depois da rodada de coleta (uma por atendimento), ou se o cliente já "
        "informou tudo: 'transferir' para um atendente ou 'continuar'."
    )
)


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
        tag: str,
        grupo: str,
        descricao: str,
        exemplo: str,
        comportamento: str,
        campos_coleta: list[str],
        max_perguntas: int,
        apos_coleta: str,
    ) -> pb.MyIntentDados:
        return pb.MyIntentDados(
            tag=tag,
            grupo=grupo,
            descricao=descricao,
            exemplo=exemplo,
            comportamento=comportamento,
            campos_coleta=campos_coleta,
            max_perguntas=max_perguntas,
            apos_coleta=apos_coleta,
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
        campos_coleta: Annotated[list[str], CAMPOS_COLETA] = [],  # noqa: B006
        max_perguntas: Annotated[int, MAX_PERGUNTAS] = 2,
        apos_coleta: Annotated[Literal["transferir", "continuar"], APOS_COLETA] = (
            "transferir"
        ),
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria uma intenção (o 'QueryCompose' da v1): um tipo de mensagem que a IA
        reconhece e o comportamento que ela deve ter nesse caso. Tag+grupo são
        únicos — confira `list_intencoes` antes.

        Motor Jev: `campos_coleta` são os dados essenciais que o bot pede ao
        cliente quando esta intenção é a escolhida — no máximo `max_perguntas`
        por mensagem e uma única rodada por atendimento; depois dela (ou se o
        cliente já disse tudo), `apos_coleta` decide: transferir ou continuar."""
        tool = registro.exigir("create_intencao")
        lista = await executor.executar(
            "create_intencao",
            "ListMyIntents",
            pb.ListMyIntentsRequest(),
            contabilizar=False,
        )
        igual = next(
            (
                i
                for i in lista.intents
                if mesmo_nome(i.tag, tag) and mesmo_nome(i.grupo, grupo)
            ),
            None,
        )
        if igual is not None:
            return recusar_duplicata(
                executor,
                tool,
                dry_run,
                f"já existe a intenção '{igual.tag}' no grupo '{igual.grupo}' "
                f"(id {igual.id}). Use `update_intencao` para alterá-la.",
            )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"criar a intenção '{grupo}/{tag}'")
        r = await executor.executar(
            "create_intencao",
            "CreateMyIntent",
            _dados_intencao(
                tag,
                grupo,
                descricao,
                exemplo,
                comportamento,
                list(campos_coleta),
                max_perguntas,
                apos_coleta,
            ),
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
        campos_coleta: Annotated[list[str] | None, CAMPOS_COLETA] = None,
        max_perguntas: Annotated[int | None, MAX_PERGUNTAS] = None,
        apos_coleta: Annotated[
            Literal["transferir", "continuar"] | None, APOS_COLETA
        ] = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Edita uma intenção existente (tag, grupo, descrição, exemplo e
        comportamento). Esses cinco são gravados como vierem: leia com
        `list_intencoes` e reenvie o que não muda. A coleta (`campos_coleta`,
        `max_perguntas`, `apos_coleta`) omitida mantém o valor atual."""
        tool = registro.exigir("update_intencao")
        if campos_coleta is None or max_perguntas is None or apos_coleta is None:
            lista = await executor.executar(
                "update_intencao",
                "ListMyIntents",
                pb.ListMyIntentsRequest(),
                contabilizar=False,
            )
            atual = next((i for i in lista.intents if i.id == intencao_id), None)
            if campos_coleta is None:
                campos_coleta = list(atual.campos_coleta) if atual else []
            if max_perguntas is None:
                max_perguntas = (atual.max_perguntas if atual else 0) or 2
            if apos_coleta is None:
                apos_coleta = (
                    "continuar"
                    if atual and atual.apos_coleta == "continuar"
                    else "transferir"
                )
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "alterar a intenção")
        await executor.executar(
            "update_intencao",
            "UpdateMyIntent",
            pb.UpdateMyIntentRequest(
                id=intencao_id,
                dados=_dados_intencao(
                    tag,
                    grupo,
                    descricao,
                    exemplo,
                    comportamento,
                    list(campos_coleta),
                    max_perguntas,
                    apos_coleta,
                ),
            ),
        )
        return f"Intenção {intencao_id} atualizada."

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
        para uma pessoa. Pelo motor Jev, também o **ato** decidido (transferir,
        responder, coletar, social, sem_info ou barrada), o **motivo** da
        transferência (regra ou sinal), os sinais medidos com o limiar, a
        intenção escolhida, os trechos aprovados, os dados que a resposta pediu,
        se a redação subiu para o modelo maior (`escalada`, com os `problemas`) e
        o tempo de cada etapa. Use para validar treinamentos, intenções, coleta e
        regras. O ensaio não conta rodada de coleta (é sempre a primeira)."""
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
        """Registra a avaliação de uma resposta obtida com `testar_pergunta` (o 👍/👎 da
        tela de teste). Se foi ruim, informe a resposta correta: ela vai para a
        revisão."""
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
        """Lista as avaliações do teste de resposta ainda não tratadas, as ruins
        primeiro. Use para revisar o que o assistente errou e decidir o que vira
        treinamento."""
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
        """Tira uma avaliação da lista de revisão, dizendo se a correção virou
        treinamento ou foi dispensada. Use depois de criar o treinamento com
        `create_treinamento`."""
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
