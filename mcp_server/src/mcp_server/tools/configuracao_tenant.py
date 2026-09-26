"""Tools da configuração do assistente do tenant.

# Por que `update_tenant_config` lê antes de gravar

O `UpdateMyTenantConfig` grava **todos** os campos a cada chamada — o painel
sempre manda a configuração inteira. Uma chamada parcial apagaria as mensagens
padrão e as chaves de API. Por isso a tool lê a configuração atual, aplica só o
que o agente pediu e reenvia o conjunto. As chaves voltam mascaradas da leitura,
e a máscara reenviada é justamente o que o servidor entende como "manter".

A configuração avançada tem RPC próprio (`UpdateMyConfigAvancada`), que já é
parcial por construção.
"""

from __future__ import annotations

from typing import Annotated, Any, Literal

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import BaseModel, Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor
from mcp_server.tools.guards import resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

DRY_RUN = Field(default=False, description="Só simular.")

#: Campos de texto da configuração geral que o agente pode trocar.
CAMPOS_GERAIS = (
    "dados_empresa",
    "msg_fallback",
    "msg_sem_info",
    "msg_transferencia",
    "llm_class",
    "model",
    "llm_temperature",
    "transcription_provider",
    "transcription_model",
    "vision_provider",
    "vision_model",
    "embeddings_class",
    "embeddings_model",
    "similarity_threshold",
    "vector_distance_threshold",
    "confianca_minima_transferencia",
    "confianca_minima_automatica",
)


class Prompt(BaseModel):
    chave: str = Field(
        description=(
            "Nome do prompt, ex.: 'PROMPT_REGRAS_RESPOSTA', "
            "'PROMPT_TEMPLATE_USER_RAG', 'PROMPT_SYSTEM_ANALISE_PREVIA_MENSAGEM'."
        )
    )
    texto: str = Field(description="Texto do prompt. Vazio = voltar ao global.")


def _pedido_completo(
    atual: pb.GetTenantConfigResponse,
) -> pb.UpdateMyTenantConfigRequest:
    """A configuração atual, no formato de gravação."""
    return pb.UpdateMyTenantConfigRequest(
        dados_empresa=atual.dados_empresa,
        persona_bot=atual.persona_bot,
        bot_agent_name=atual.bot_agent_name,
        msg_fallback=atual.msg_fallback,
        msg_sem_info=atual.msg_sem_info,
        msg_transferencia=atual.msg_transferencia,
        llm_class=atual.llm_class,
        model=atual.model,
        llm_temperature=atual.llm_temperature,
        transcription_provider=atual.transcription_provider,
        transcription_model=atual.transcription_model,
        vision_provider=atual.vision_provider,
        vision_model=atual.vision_model,
        embeddings_class=atual.embeddings_class,
        embeddings_model=atual.embeddings_model,
        chunk_size=atual.chunk_size,
        chunk_overlap=atual.chunk_overlap,
        similarity_threshold=atual.similarity_threshold,
        vector_distance_threshold=atual.vector_distance_threshold,
        # Mascaradas na leitura; a máscara reenviada mantém o valor guardado.
        api_keys=[pb.ApiKeyEntry(key=e.key, value=e.value) for e in atual.api_keys],
        confianca_minima_transferencia=atual.confianca_minima_transferencia,
        confianca_minima_automatica=atual.confianca_minima_automatica,
    )


def registrar(mcp, registro: Registro, executor: Executor) -> None:
    """Registra as tools de configuração do tenant."""

    async def _ler(nome_da_tool: str) -> pb.GetTenantConfigResponse:
        return await executor.executar(
            nome_da_tool,
            "GetMyTenantConfig",
            pb.GetMyTenantConfigRequest(),
            contabilizar=False,
        )

    registro.registrar(
        "update_tenant_config", Categoria.CONFIGURACAO, ("configuracoes:write",)
    )

    @mcp.tool(
        name="update_tenant_config",
        annotations=registro.exigir("update_tenant_config").anotacoes,
    )
    async def update_tenant_config(
        dados_empresa: Annotated[
            str | None,
            Field(
                default=None, description="Quem é a empresa, o que vende, como atua."
            ),
        ] = None,
        msg_fallback: Annotated[
            str | None, Field(default=None, description="Quando a IA falha.")
        ] = None,
        msg_sem_info: Annotated[
            str | None, Field(default=None, description="Quando não sabe responder.")
        ] = None,
        msg_transferencia: Annotated[
            str | None, Field(default=None, description="Ao passar para uma pessoa.")
        ] = None,
        llm_class: str | None = None,
        model: str | None = None,
        llm_temperature: Annotated[
            str | None, Field(default=None, description="Decimal, ex.: '0.2'.")
        ] = None,
        transcription_provider: str | None = None,
        transcription_model: str | None = None,
        vision_provider: str | None = None,
        vision_model: str | None = None,
        embeddings_class: str | None = None,
        embeddings_model: str | None = None,
        chunk_size: int | None = None,
        chunk_overlap: int | None = None,
        similarity_threshold: str | None = None,
        vector_distance_threshold: str | None = None,
        confianca_minima_transferencia: Annotated[
            str | None, Field(default=None, description="0 a 1, ex.: '0.5'.")
        ] = None,
        confianca_minima_automatica: Annotated[
            str | None, Field(default=None, description="0 a 1, ex.: '0.8'.")
        ] = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Atualiza a configuração geral do assistente: dados da empresa,
        mensagens padrão, modelo de linguagem e limiares.

        Só os campos informados mudam — o resto é preservado. Para persona use
        `set_bot_persona`; para prompts, `set_prompts`; para marca, fuso,
        tipos de entidade e afins, `update_config_avancada`.
        """
        tool = registro.exigir("update_tenant_config")
        pedidos = {
            k: v
            for k, v in {
                "dados_empresa": dados_empresa,
                "msg_fallback": msg_fallback,
                "msg_sem_info": msg_sem_info,
                "msg_transferencia": msg_transferencia,
                "llm_class": llm_class,
                "model": model,
                "llm_temperature": llm_temperature,
                "transcription_provider": transcription_provider,
                "transcription_model": transcription_model,
                "vision_provider": vision_provider,
                "vision_model": vision_model,
                "embeddings_class": embeddings_class,
                "embeddings_model": embeddings_model,
                "chunk_size": chunk_size,
                "chunk_overlap": chunk_overlap,
                "similarity_threshold": similarity_threshold,
                "vector_distance_threshold": vector_distance_threshold,
                "confianca_minima_transferencia": confianca_minima_transferencia,
                "confianca_minima_automatica": confianca_minima_automatica,
            }.items()
            if v is not None
        }
        if not pedidos:
            raise ToolError("Informe ao menos um campo para alterar.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"alterar {', '.join(sorted(pedidos))}")

        requisicao = _pedido_completo(await _ler("update_tenant_config"))
        for campo, valor in pedidos.items():
            setattr(requisicao, campo, valor)
        await executor.executar(
            "update_tenant_config", "UpdateMyTenantConfig", requisicao
        )
        return f"Configuração atualizada: {', '.join(sorted(pedidos))}."

    registro.registrar("definir_chave_api", Categoria.CONFIGURACAO, ("tenant:admin",))

    @mcp.tool(
        name="definir_chave_api",
        annotations=registro.exigir("definir_chave_api").anotacoes,
    )
    async def definir_chave_api(
        provedor: Annotated[
            Literal["openai", "groq", "google"],
            Field(description="Provedor da chave."),
        ],
        chave: Annotated[
            str,
            Field(description="A chave. Vazio remove a chave própria do negócio."),
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Grava a chave de API própria do negócio para um provedor de IA.

        A chave nunca é devolvida por nenhuma tool. Só administradores do negócio.
        """
        tool = registro.exigir("definir_chave_api")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, "gravar/remover a chave de API do provedor")
        requisicao = _pedido_completo(await _ler("definir_chave_api"))
        nome = f"{provedor}_api_key"
        restantes = [e for e in requisicao.api_keys if e.key != nome]
        del requisicao.api_keys[:]
        requisicao.api_keys.extend(restantes)
        requisicao.api_keys.append(pb.ApiKeyEntry(key=nome, value=chave))
        await executor.executar("definir_chave_api", "UpdateMyTenantConfig", requisicao)
        return f"Chave de {provedor} {'removida' if not chave else 'gravada'}."

    registro.registrar(
        "update_config_avancada", Categoria.CONFIGURACAO, ("configuracoes:write",)
    )

    @mcp.tool(
        name="update_config_avancada",
        annotations=registro.exigir("update_config_avancada").anotacoes,
    )
    async def update_config_avancada(
        entity_types_json: Annotated[
            str | None,
            Field(
                default=None,
                description=(
                    "Tipos de entidade que a IA extrai, em JSON: objeto "
                    '{"tipo": "descrição"} ou lista de nomes. Aceita o formato '
                    'da v1 ({"entity_types": {...}}).'
                ),
            ),
        ] = None,
        brand_name: str | None = None,
        primary_color: Annotated[
            str | None, Field(default=None, description="#RRGGBB.")
        ] = None,
        secondary_color: Annotated[
            str | None, Field(default=None, description="#RRGGBB.")
        ] = None,
        timezone: Annotated[
            str | None, Field(default=None, description="Ex.: 'America/Fortaleza'.")
        ] = None,
        language_code: Annotated[
            str | None, Field(default=None, description="Ex.: 'pt-br'.")
        ] = None,
        analise_previa_habilitada: bool | None = None,
        pesquisa_satisfacao_ativa: bool | None = None,
        msg_pesquisa_satisfacao: str | None = None,
        minutos_inatividade_encerra: Annotated[
            int | None,
            Field(default=None, description="0 = volta a herdar o padrão global."),
        ] = None,
        transcription_enabled: bool | None = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Configuração avançada: tipos de entidade, marca (nome e cores), fuso,
        idioma, pesquisa de satisfação, encerramento por inatividade, análise
        prévia e transcrição de áudio. Só o informado muda."""
        tool = registro.exigir("update_config_avancada")
        campos = {
            "entity_types_json": entity_types_json,
            "brand_name": brand_name,
            "primary_color": primary_color,
            "secondary_color": secondary_color,
            "timezone": timezone,
            "language_code": language_code,
            "analise_previa_habilitada": analise_previa_habilitada,
            "pesquisa_satisfacao_ativa": pesquisa_satisfacao_ativa,
            "msg_pesquisa_satisfacao": msg_pesquisa_satisfacao,
            "minutos_inatividade_encerra": minutos_inatividade_encerra,
            "transcription_enabled": transcription_enabled,
        }
        pedidos: dict[str, Any] = {k: v for k, v in campos.items() if v is not None}
        if not pedidos:
            raise ToolError("Informe ao menos um campo para alterar.")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"alterar {', '.join(sorted(pedidos))}")
        await executor.executar(
            "update_config_avancada",
            "UpdateMyConfigAvancada",
            pb.UpdateMyConfigAvancadaRequest(**pedidos),
        )
        return f"Configuração avançada atualizada: {', '.join(sorted(pedidos))}."

    registro.registrar("set_prompts", Categoria.CONFIGURACAO, ("configuracoes:write",))

    @mcp.tool(name="set_prompts", annotations=registro.exigir("set_prompts").anotacoes)
    async def set_prompts(
        prompts: Annotated[
            list[Prompt],
            Field(description="Prompts a gravar. Texto vazio remove o override."),
        ],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Grava prompts personalizados **deste negócio**, por cima dos globais.

        Só os prompts informados mudam. Leia os atuais com `get_tenant_config`.
        Chaves aceitas: PROMPT_* (maiúsculas ou minúsculas, como na v1).
        """
        tool = registro.exigir("set_prompts")
        if not prompts:
            raise ToolError("Informe ao menos um prompt.")
        chaves = ", ".join(p.chave.upper() for p in prompts)
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(tool, f"gravar os prompts {chaves}")
        await executor.executar(
            "set_prompts",
            "UpdateMyConfigAvancada",
            pb.UpdateMyConfigAvancadaRequest(
                prompts=[
                    pb.PromptDoTenant(chave=p.chave, texto=p.texto) for p in prompts
                ]
            ),
        )
        return f"Prompts gravados: {chaves}."
