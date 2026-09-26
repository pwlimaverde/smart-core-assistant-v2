"""Tools de leitura.

# A descrição É a interface

A docstring de cada tool vira a descrição no `inputSchema`, e é ela que o modelo
lê para decidir *se* e *quando* chamar. Uma descrição ruim não produz um erro:
produz um agente que erra com confiança. Por isso cada uma diz **o que faz,
quando usar e quando NÃO usar**, e cada argumento carrega `Field(description=…)`.

# O que não sai daqui

Telefone e nome de contato **não** entram em log nem em span — só ids. As tools
devolvem esses dados ao agente (é para isso que existem), mas o rastro que fica
no nosso sistema carrega apenas identificadores.
"""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor, limitar_itens
from mcp_server.tools.registry import Categoria, Registro

TETO_PADRAO = 50


def registrar(
    mcp, registro: Registro, executor: Executor, teto: int = TETO_PADRAO
) -> None:
    """Registra as tools de leitura no servidor."""

    # -- Painel --------------------------------------------------------------

    registro.registrar("get_painel", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(
        name="get_painel",
        annotations=registro.exigir("get_painel").anotacoes,
    )
    async def get_painel() -> dict[str, int]:
        """Números gerais do negócio agora: atendimentos em andamento e aguardando,
        mensagens nas últimas 24h, conexões de WhatsApp ativas, departamentos e
        treinamentos.

        Use no começo de uma conversa, para entender a situação antes de agir, ou
        quando perguntarem "como estamos hoje".

        NÃO use para responder sobre um atendimento específico — para isso use
        `list_atendimentos` e `get_thread`.
        """
        resposta = await executor.executar(
            "get_painel", "GetMyPainel", pb.GetMyPainelRequest()
        )
        return {
            "em_andamento": resposta.em_andamento,
            "aguardando": resposta.aguardando,
            "mensagens_24h": resposta.mensagens_24h,
            "conexoes_ativas": resposta.conexoes_ativas,
            "conexoes_total": resposta.conexoes_total,
            "departamentos": resposta.departamentos,
            "treinamentos_ativos": resposta.treinamentos_ativos,
        }

    # -- Fluxos e etapas -----------------------------------------------------

    registro.registrar("list_fluxos", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(name="list_fluxos", annotations=registro.exigir("list_fluxos").anotacoes)
    async def list_fluxos() -> list[dict[str, object]]:
        """Lista os fluxos de atendimento (os quadros Kanban) do negócio, com o
        departamento de cada um e quantos atendimentos estão abertos neles.

        Use antes de qualquer operação sobre fluxo ou etapa: é aqui que se
        descobre o `fluxo_id` e o nome exato, que as tools de escrita exigem.
        """
        resposta = await executor.executar(
            "list_fluxos", "ListMyFluxos", pb.ListMyFluxosRequest()
        )
        return [
            {
                "id": f.id,
                "nome": f.nome,
                "descricao": f.descricao,
                "departamento_id": f.departamento_id,
                "departamento_nome": f.departamento_nome,
                "ativo": f.ativo,
                "atendimentos_abertos": f.atendimentos_abertos,
            }
            for f in limitar_itens(list(resposta.fluxos), teto)
        ]

    registro.registrar("list_etapas_fluxo", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(
        name="list_etapas_fluxo",
        annotations=registro.exigir("list_etapas_fluxo").anotacoes,
    )
    async def list_etapas_fluxo(
        fluxo_id: Annotated[
            int, Field(description="Id do fluxo, obtido em `list_fluxos`.")
        ],
    ) -> list[dict[str, object]]:
        """Lista as etapas (colunas) de um fluxo, na ordem em que aparecem no quadro.

        Use para saber a estrutura de um funil antes de criar, mover ou remover
        etapas — e para descobrir o `etapa_id` correspondente a um nome.
        """
        resposta = await executor.executar(
            "list_etapas_fluxo", "ListMyEtapasFluxo", pb.MyFluxoIdRequest(id=fluxo_id)
        )
        return [
            {
                "id": e.id,
                "nome": e.nome,
                "descricao": e.descricao,
                "ordem": e.ordem,
                "cor": e.cor,
                "tipo_etapa": e.tipo_etapa,
                "ativo": e.ativo,
            }
            for e in limitar_itens(list(resposta.etapas), teto)
        ]

    # -- Estrutura operacional ----------------------------------------------

    registro.registrar("list_departamentos", Categoria.LEITURA, ("operacional:read",))

    @mcp.tool(
        name="list_departamentos",
        annotations=registro.exigir("list_departamentos").anotacoes,
    )
    async def list_departamentos() -> list[dict[str, object]]:
        """Lista os departamentos do negócio (comercial, suporte, financeiro…).

        Use antes de criar um fluxo ou um atendente: os dois exigem um
        `departamento_id` que sai daqui.
        """
        resposta = await executor.executar(
            "list_departamentos", "ListMyDepartamentos", pb.ListMyDepartamentosRequest()
        )
        return [
            {
                "id": d.id,
                "nome": d.nome,
                "slug": d.slug,
                "descricao": d.descricao,
                "ativo": d.ativo,
            }
            for d in limitar_itens(list(resposta.departamentos), teto)
        ]

    registro.registrar("list_atendentes", Categoria.LEITURA, ("operacional:read",))

    @mcp.tool(
        name="list_atendentes", annotations=registro.exigir("list_atendentes").anotacoes
    )
    async def list_atendentes() -> list[dict[str, object]]:
        """Lista os atendentes cadastrados, com departamento, disponibilidade e
        quantos atendimentos simultâneos cada um aceita.

        Use para entender a equipe antes de distribuir trabalho ou de criar um
        atendente novo (evita duplicar alguém que já existe).
        """
        resposta = await executor.executar(
            "list_atendentes", "ListMyAtendentes", pb.ListMyAtendentesRequest()
        )
        return [
            {
                "id": a.id,
                "nome": a.nome,
                "cargo": a.cargo,
                "email": a.email,
                "departamento_id": a.departamento_id,
                # 0 = atende todos os fluxos do departamento.
                "fluxo_id": a.fluxo_id,
                "ativo": a.ativo,
                "disponivel": a.disponivel,
                "max_atendimentos_simultaneos": a.max_atendimentos_simultaneos,
            }
            for a in limitar_itens(list(resposta.atendentes), teto)
        ]

    registro.registrar(
        "list_conexoes_whatsapp", Categoria.LEITURA, ("operacional:read",)
    )

    @mcp.tool(
        name="list_conexoes_whatsapp",
        annotations=registro.exigir("list_conexoes_whatsapp").anotacoes,
    )
    async def list_conexoes_whatsapp() -> list[dict[str, object]]:
        """Lista as conexões de WhatsApp do negócio e o estado de cada uma.

        Use quando perguntarem se o WhatsApp está no ar, ou antes de tentar
        enviar mensagem: sem conexão ativa, o envio falha.
        """
        resposta = await executor.executar(
            "list_conexoes_whatsapp",
            "ListMyWhatsappInstances",
            pb.ListMyWhatsappInstancesRequest(),
        )
        return [
            {
                "id": i.id,
                "nome": i.name,
                "telefone": i.phone_number,
                "estado": i.connection_state,
                "ativa": i.active,
            }
            for i in limitar_itens(list(resposta.instancias), teto)
        ]

    # -- Contatos e atendimentos --------------------------------------------

    registro.registrar("list_contatos", Categoria.LEITURA, ("clientes:read",))

    @mcp.tool(
        name="list_contatos", annotations=registro.exigir("list_contatos").anotacoes
    )
    async def list_contatos(
        busca: Annotated[
            str,
            Field(
                default="",
                description=(
                    "Trecho de nome ou telefone para filtrar. "
                    "Vazio traz os mais recentes."
                ),
            ),
        ] = "",
    ) -> list[dict[str, object]]:
        """Busca contatos (clientes) do negócio por nome ou telefone.

        Use para encontrar o `contato_id` de alguém antes de olhar o histórico.

        NÃO use para exportar a base inteira: a resposta é limitada, e listar
        todos os contatos não ajuda a responder pergunta nenhuma.
        """
        resposta = await executor.executar(
            "list_contatos",
            "ListMyContatos",
            pb.ListMyContatosRequest(busca=busca, limite=teto),
        )
        return [
            {
                "id": c.id,
                "nome": c.nome_contato or c.nome_perfil_whatsapp,
                "telefone": c.telefone,
                "email": c.email,
                "ativo": c.ativo,
            }
            for c in limitar_itens(list(resposta.contatos), teto)
        ]

    registro.registrar("list_atendimentos", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(
        name="list_atendimentos",
        annotations=registro.exigir("list_atendimentos").anotacoes,
    )
    async def list_atendimentos(
        status: Annotated[
            Literal["em_andamento", "aguardando", "finalizado", "todos"],
            Field(
                description="Filtro de situação. Use `todos` só quando precisar mesmo."
            ),
        ] = "em_andamento",
        departamento_id: Annotated[
            int, Field(default=0, description="Filtra por departamento. 0 = todos.")
        ] = 0,
    ) -> list[dict[str, object]]:
        """Lista os atendimentos (conversas) do negócio, do mais recente para o
        mais antigo, com situação, departamento, etapa e sentimento.

        Use para responder "o que está aberto agora" e para achar o
        `atendimento_id` que `get_thread` e `send_message` exigem.
        """
        resposta = await executor.executar(
            "list_atendimentos",
            "ListAtendimentos",
            pb.ListAtendimentosRequest(
                status="" if status == "todos" else status,
                departamento_id=departamento_id,
                limit=teto,
            ),
        )
        return [
            {
                "id": a.id,
                "contato_id": a.contato_id,
                "status": a.status,
                "assunto": a.assunto,
                "departamento_id": a.departamento_id,
                "fluxo_id": a.fluxo_atendimento_id,
                "etapa_id": a.etapa_atual_id,
                "prioridade": a.prioridade,
                "sentimento": a.sentimento_label,
            }
            for a in limitar_itens(list(resposta.atendimentos), teto)
        ]

    registro.registrar("get_thread", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(name="get_thread", annotations=registro.exigir("get_thread").anotacoes)
    async def get_thread(
        atendimento_id: Annotated[
            int, Field(description="Id do atendimento, obtido em `list_atendimentos`.")
        ],
    ) -> list[dict[str, object]]:
        """Lê as mensagens de um atendimento, em ordem cronológica, com quem
        enviou cada uma e se foi gerada pela IA.

        Use antes de responder a um cliente: sem ler a conversa, qualquer resposta
        é chute.

        NÃO use para varrer conversas em busca de padrão — é uma conversa por vez.
        """
        resposta = await executor.executar(
            "get_thread",
            "GetThread",
            pb.GetThreadRequest(atendimento_id=atendimento_id, limit=teto, offset=0),
        )
        return [
            {
                "id": m.id,
                "tipo": m.tipo,
                "conteudo": m.conteudo,
                "remetente": m.remetente,
                "timestamp": m.timestamp,
                "gerado_por_ia": m.gerado_por_ia,
            }
            for m in limitar_itens(list(resposta.mensagens), teto)
        ]

    # -- Base de conhecimento -----------------------------------------------

    registro.registrar("list_treinamentos", Categoria.LEITURA, ("treinamento:read",))

    @mcp.tool(
        name="list_treinamentos",
        annotations=registro.exigir("list_treinamentos").anotacoes,
    )
    async def list_treinamentos() -> list[dict[str, object]]:
        """Lista os treinamentos da base de conhecimento do assistente — os textos
        que ele usa para responder aos clientes —, com tag, grupo e se já foram
        finalizados e vetorizados.

        Use antes de criar treinamento novo, para não duplicar assunto já coberto.
        """
        resposta = await executor.executar(
            "list_treinamentos", "ListMyTreinamentos", pb.ListMyTreinamentosRequest()
        )
        return [
            {
                "id": t.id,
                "tag": t.tag,
                "grupo": t.grupo,
                "finalizado": t.finalizado,
                "vetorizado": t.vetorizado,
            }
            for t in limitar_itens(list(resposta.treinamentos), teto)
        ]

    # -- Configuração --------------------------------------------------------

    registro.registrar("get_tenant_config", Categoria.LEITURA, ("configuracoes:read",))

    @mcp.tool(
        name="get_tenant_config",
        annotations=registro.exigir("get_tenant_config").anotacoes,
    )
    async def get_tenant_config() -> dict[str, object]:
        """Lê a configuração do assistente: dados da empresa, persona do bot,
        mensagens padrão, modelo de linguagem escolhido e **quais** provedores
        têm chave configurada.

        As chaves de API em si NÃO são devolvidas — só a lista de provedores que
        estão configurados. Nenhum agente precisa da chave, e ela não deve entrar
        no contexto de um modelo de terceiro.
        """
        resposta = await executor.executar(
            "get_tenant_config", "GetMyTenantConfig", pb.GetMyTenantConfigRequest()
        )
        return {
            "observacao": (
                "Campos de modelo, provedor e embeddings VAZIOS não são falta de "
                "configuração: o negócio usa o padrão global do sistema, "
                "definido pelo administrador. provedores_configurados lista só "
                "as chaves PRÓPRIAS do negócio — vazio significa que ele usa as "
                "chaves globais."
            ),
            "dados_empresa": resposta.dados_empresa,
            "persona_bot": resposta.persona_bot,
            "nome_do_agente": resposta.bot_agent_name,
            "msg_fallback": resposta.msg_fallback,
            "msg_sem_info": resposta.msg_sem_info,
            "msg_transferencia": resposta.msg_transferencia,
            "llm_class": resposta.llm_class,
            "model": resposta.model,
            "llm_temperature": resposta.llm_temperature,
            "embeddings_model": resposta.embeddings_model,
            # Só os NOMES dos provedores. O `value` de cada `ApiKeyEntry` fica
            # de fora em hipótese nenhuma — nem mascarado, nem truncado: um
            # prefixo de chave ainda é material para um ataque, e o agente não
            # tem uso para ele.
            "provedores_configurados": sorted(
                entrada.key for entrada in resposta.api_keys if entrada.value
            ),
            "transcription_provider": resposta.transcription_provider,
            "transcription_model": resposta.transcription_model,
            "vision_provider": resposta.vision_provider,
            "vision_model": resposta.vision_model,
            "embeddings_class": resposta.embeddings_class,
            "chunk_size": resposta.chunk_size,
            "chunk_overlap": resposta.chunk_overlap,
            "similarity_threshold": resposta.similarity_threshold,
            "vector_distance_threshold": resposta.vector_distance_threshold,
            "confianca_minima_transferencia": resposta.confianca_minima_transferencia,
            "confianca_minima_automatica": resposta.confianca_minima_automatica,
            # Configuração avançada. `None` = o negócio herda o padrão global.
            "tipos_de_entidade_json": resposta.entity_types_json,
            "prompts_do_negocio": {p.chave: p.texto for p in resposta.prompts},
            "marca": resposta.brand_name,
            "cor_primaria": resposta.primary_color,
            "cor_secundaria": resposta.secondary_color,
            "fuso": resposta.timezone,
            "idioma": resposta.language_code,
            "analise_previa_habilitada": (
                resposta.analise_previa_habilitada
                if resposta.HasField("analise_previa_habilitada")
                else None
            ),
            "pesquisa_satisfacao_ativa": (
                resposta.pesquisa_satisfacao_ativa
                if resposta.HasField("pesquisa_satisfacao_ativa")
                else None
            ),
            "msg_pesquisa_satisfacao": resposta.msg_pesquisa_satisfacao,
            "minutos_inatividade_encerra": (
                resposta.minutos_inatividade_encerra
                if resposta.HasField("minutos_inatividade_encerra")
                else None
            ),
            "transcricao_habilitada": (
                resposta.transcription_enabled
                if resposta.HasField("transcription_enabled")
                else None
            ),
        }
