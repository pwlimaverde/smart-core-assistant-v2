"""Transferência para atendente (plano ia-engine-jev).

Quando o bot passa a conversa para uma pessoa é **decisão do negócio**, e fica
num cadastro próprio — a mesma tela "Transferência para atendente" das
configurações. No motor Jev esse cadastro é a única fonte: a IA não transfere
por conta própria.

- **Sinais automáticos**: pedido de humano, cliente irritado, na dúvida
  transferir, base sem resposta, resposta sem apoio na base — liga/desliga e
  sensibilidade (baixa · media · alta).
- **Regras do negócio**: cada uma com um gatilho (uma condição exata, lida ao pé
  da letra, ou uma intenção do catálogo), o momento (imediato ou depois de
  coletar campos do cartão), o destino e a mensagem.

Regra nova nasce **inativa**: teste com `testar_regra_transferencia` e ative com
`ativar_regra_transferencia`.
"""

from __future__ import annotations

from typing import Annotated, Literal

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor, limitar_itens, para_dict
from mcp_server.tools.guards import mesmo_nome, recusar_duplicata, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

LER = ("configuracoes:read",)
ESCREVER = ("configuracoes:write",)

Gatilho = Literal["condicao", "intencao"]
Momento = Literal["imediato", "apos_coleta"]
Destino = Literal["fluxo", "setor_jev", "padrao"]
Sensibilidade = Literal["baixa", "media", "alta"]
Sinal = Literal[
    "pede_humano",
    "irritacao",
    "duvida_transfere",
    "base_sem_resposta",
    "resposta_sem_apoio",
]

DRY_RUN = Field(default=False, description="Só simular: nada é gravado.")
REGRA_ID = Field(description="Id da regra, de `list_regras_transferencia`.")
CONDICAO = Field(
    default="",
    description=(
        "Para gatilho `condicao`: UMA frase exata, lida ao pé da letra — "
        '"o cliente quer fechar ou confirmar um pedido", não "assuntos '
        'comerciais".'
    ),
)


async def _regras(executor: Executor, tool: str) -> list[pb.RegraTransferencia]:
    r = await executor.executar(
        tool,
        "ListMyRegrasTransferencia",
        pb.ListMyRegrasTransferenciaRequest(),
        contabilizar=False,
    )
    return list(r.regras)


def _achar(regras: list[pb.RegraTransferencia], regra_id: int) -> pb.RegraTransferencia:
    for r in regras:
        if r.id == regra_id:
            return r
    raise ToolError(
        f"Regra {regra_id} não encontrada. Use `list_regras_transferencia`."
    )


def registrar(mcp, registro: Registro, executor: Executor, teto: int = 50) -> None:
    """Registra as tools da transferência para atendente."""

    # -- Leitura ------------------------------------------------------------
    registro.registrar("get_config_transferencia", Categoria.LEITURA, LER)

    @mcp.tool(
        name="get_config_transferencia",
        annotations=registro.exigir("get_config_transferencia").anotacoes,
    )
    async def get_config_transferencia() -> dict[str, object]:
        """Como o bot decide transferir: os sinais automáticos (ligado e
        sensibilidade), o fluxo padrão de destino, a mensagem ao cliente na
        transferência e o motor de IA em uso (`llm`, `sombra` ou `jev`)."""
        r = await executor.executar(
            "get_config_transferencia",
            "GetMyConfigTransferencia",
            pb.GetMyConfigTransferenciaRequest(),
        )
        return para_dict(r.config)

    registro.registrar("list_regras_transferencia", Categoria.LEITURA, LER)

    @mcp.tool(
        name="list_regras_transferencia",
        annotations=registro.exigir("list_regras_transferencia").anotacoes,
    )
    async def list_regras_transferencia() -> list[dict[str, object]]:
        """As regras de transferência do negócio, ativas primeiro, incluindo as
        **sugestões inativas** criadas a partir do texto antigo (`sugestao`)."""
        regras = await _regras(executor, "list_regras_transferencia")
        return [para_dict(r) for r in regras]

    registro.registrar("list_transferencias", Categoria.LEITURA, ("atendimentos:read",))

    @mcp.tool(
        name="list_transferencias",
        annotations=registro.exigir("list_transferencias").anotacoes,
    )
    async def list_transferencias() -> list[dict[str, object]]:
        """As últimas conversas que a IA transferiu, com o **motivo** (nome da
        regra ou do sinal), os sinais medidos e o fluxo de destino. Sem o texto
        da conversa."""
        r = await executor.executar(
            "list_transferencias",
            "ListMyTransferencias",
            pb.ListMyTransferenciasRequest(limite=teto),
        )
        return [para_dict(t) for t in limitar_itens(list(r.transferencias), teto)]

    registro.registrar("testar_regra_transferencia", Categoria.LEITURA, LER)

    @mcp.tool(
        name="testar_regra_transferencia",
        annotations=registro.exigir("testar_regra_transferencia").anotacoes,
    )
    async def testar_regra_transferencia(
        frase: Annotated[str, Field(description="Mensagem como o cliente mandaria.")],
        regra_id: Annotated[
            int, Field(default=0, description="Uma regra salva. 0 = usar `condicao`.")
        ] = 0,
        condicao: Annotated[str, CONDICAO] = "",
        exemplos_sim: Annotated[
            list[str] | None, Field(default=None, description="Frases que transferem.")
        ] = None,
        exemplos_nao: Annotated[
            list[str] | None,
            Field(default=None, description="Frases que NÃO transferem."),
        ] = None,
        sensibilidade: Annotated[Sensibilidade, Field(default="media")] = "media",
    ) -> dict[str, object]:
        """Testa se uma frase dispararia uma regra de **condição** — a salva
        (`regra_id`) ou uma ainda não salva (`condicao` + exemplos). Devolve a
        probabilidade, o limiar da sensibilidade e se dispararia. Nada é
        gravado. Regra por intenção se testa com `testar_pergunta`."""
        regra = None
        if not regra_id:
            if not condicao.strip():
                raise ToolError("Informe `regra_id` ou a `condicao` a testar.")
            regra = pb.RegraTransferencia(
                gatilho_tipo="condicao",
                condicao=condicao,
                exemplos_sim=exemplos_sim or [],
                exemplos_nao=exemplos_nao or [],
                sensibilidade=sensibilidade,
            )
        r = await executor.executar(
            "testar_regra_transferencia",
            "TestarMyRegraTransferencia",
            pb.TestarMyRegraTransferenciaRequest(
                frase=frase, regra_id=regra_id, regra=regra
            ),
        )
        return para_dict(r)

    # -- Configuração -------------------------------------------------------
    registro.registrar("create_regra_transferencia", Categoria.CONFIGURACAO, ESCREVER)

    @mcp.tool(
        name="create_regra_transferencia",
        annotations=registro.exigir("create_regra_transferencia").anotacoes,
    )
    async def create_regra_transferencia(
        nome: Annotated[str, Field(description="Nome curto, aparece como motivo.")],
        gatilho_tipo: Annotated[
            Gatilho,
            Field(description="`condicao` (uma frase) ou `intencao` (do catálogo)."),
        ],
        condicao: Annotated[str, CONDICAO] = "",
        intencao_tag: Annotated[
            str, Field(default="", description="Para gatilho `intencao`: a tag.")
        ] = "",
        exemplos_sim: Annotated[
            list[str] | None, Field(default=None, description="Frases que transferem.")
        ] = None,
        exemplos_nao: Annotated[
            list[str] | None,
            Field(default=None, description="Frases que NÃO transferem."),
        ] = None,
        momento: Annotated[
            Momento,
            Field(
                default="imediato",
                description="`apos_coleta` = só depois de preencher `campos_coleta`.",
            ),
        ] = "imediato",
        campos_coleta: Annotated[
            list[str] | None,
            Field(default=None, description="Slugs dos campos do cartão."),
        ] = None,
        destino_tipo: Annotated[
            Destino,
            Field(
                default="padrao",
                description="`fluxo` (destino_fluxo_id), `setor_jev` ou `padrao`.",
            ),
        ] = "padrao",
        destino_fluxo_id: Annotated[int, Field(default=0)] = 0,
        mensagem: Annotated[
            str,
            Field(default="", description="Ao cliente. Vazio = a mensagem padrão."),
        ] = "",
        sensibilidade: Annotated[Sensibilidade, Field(default="media")] = "media",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Cria uma regra de transferência. Ela nasce **inativa**: teste com
        `testar_regra_transferencia` e ative com `ativar_regra_transferencia`.
        Sempre `dry_run=true` primeiro e mostre a regra à pessoa."""
        tool = registro.exigir("create_regra_transferencia")
        existentes = await _regras(executor, "create_regra_transferencia")
        if any(mesmo_nome(r.nome, nome) for r in existentes):
            return recusar_duplicata(
                executor, tool, dry_run, f"já existe uma regra chamada '{nome}'"
            )
        regra = pb.RegraTransferencia(
            nome=nome,
            gatilho_tipo=gatilho_tipo,
            condicao=condicao,
            intencao_tag=intencao_tag,
            exemplos_sim=exemplos_sim or [],
            exemplos_nao=exemplos_nao or [],
            momento=momento,
            campos_coleta=campos_coleta or [],
            destino_tipo=destino_tipo,
            destino_fluxo_id=destino_fluxo_id,
            mensagem=mensagem,
            sensibilidade=sensibilidade,
        )
        if dry_run:
            executor.registrar_simulacao(tool)
            # O servidor valida na simulação também: condição vaga, destino
            # sem fluxo e coleta sem campos voltam como erro já aqui.
            await executor.executar(
                "create_regra_transferencia",
                "SalvarMyRegraTransferencia",
                pb.SalvarMyRegraTransferenciaRequest(regra=regra, dry_run=True),
                contabilizar=False,
            )
            return resultado_dry_run(
                tool, f"criar a regra '{nome}' INATIVA ({gatilho_tipo}, {momento})"
            )
        r = await executor.executar(
            "create_regra_transferencia",
            "SalvarMyRegraTransferencia",
            pb.SalvarMyRegraTransferenciaRequest(regra=regra),
        )
        return (
            f"Regra '{r.regra.nome}' criada (id {r.regra.id}), inativa. Teste e "
            "ative quando estiver certa."
        )

    registro.registrar("update_regra_transferencia", Categoria.CONFIGURACAO, ESCREVER)

    @mcp.tool(
        name="update_regra_transferencia",
        annotations=registro.exigir("update_regra_transferencia").anotacoes,
    )
    async def update_regra_transferencia(
        regra_id: Annotated[int, REGRA_ID],
        nome: str | None = None,
        condicao: str | None = None,
        intencao_tag: str | None = None,
        exemplos_sim: list[str] | None = None,
        exemplos_nao: list[str] | None = None,
        momento: Momento | None = None,
        campos_coleta: list[str] | None = None,
        destino_tipo: Destino | None = None,
        destino_fluxo_id: int | None = None,
        mensagem: str | None = None,
        sensibilidade: Sensibilidade | None = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Altera só os campos informados de uma regra (os demais ficam como
        estão). Regra ativa alterada vale a partir da próxima mensagem."""
        tool = registro.exigir("update_regra_transferencia")
        atual = _achar(await _regras(executor, "update_regra_transferencia"), regra_id)
        if nome is not None and not mesmo_nome(nome, atual.nome):
            outras = await _regras(executor, "update_regra_transferencia")
            if any(r.id != regra_id and mesmo_nome(r.nome, nome) for r in outras):
                return recusar_duplicata(
                    executor, tool, dry_run, f"já existe uma regra chamada '{nome}'"
                )
        nova = pb.RegraTransferencia()
        nova.CopyFrom(atual)
        mudancas = {
            "nome": nome,
            "condicao": condicao,
            "intencao_tag": intencao_tag,
            "momento": momento,
            "destino_tipo": destino_tipo,
            "destino_fluxo_id": destino_fluxo_id,
            "mensagem": mensagem,
            "sensibilidade": sensibilidade,
        }
        for campo, valor in mudancas.items():
            if valor is not None:
                setattr(nova, campo, valor)
        for campo, lista in (
            ("exemplos_sim", exemplos_sim),
            ("exemplos_nao", exemplos_nao),
            ("campos_coleta", campos_coleta),
        ):
            if lista is not None:
                del getattr(nova, campo)[:]
                getattr(nova, campo).extend(lista)
        r = await executor.executar(
            "update_regra_transferencia",
            "SalvarMyRegraTransferencia",
            pb.SalvarMyRegraTransferenciaRequest(
                id=regra_id, regra=nova, dry_run=dry_run
            ),
            contabilizar=not dry_run,
        )
        if dry_run:
            executor.registrar_simulacao(tool)
            campos = ", ".join(r.campos_alterados) or "nada"
            return resultado_dry_run(tool, f"alterar em '{atual.nome}': {campos}")
        campos = ", ".join(r.campos_alterados) or "nada mudou"
        return f"Regra '{r.regra.nome}' atualizada ({campos})."

    registro.registrar("ativar_regra_transferencia", Categoria.CONFIGURACAO, ESCREVER)

    @mcp.tool(
        name="ativar_regra_transferencia",
        annotations=registro.exigir("ativar_regra_transferencia").anotacoes,
    )
    async def ativar_regra_transferencia(
        regra_id: Annotated[int, REGRA_ID],
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Ativa uma regra (inclusive uma sugestão): ela passa a valer na próxima
        mensagem. Teste antes com `testar_regra_transferencia`."""
        tool = registro.exigir("ativar_regra_transferencia")
        r = await executor.executar(
            "ativar_regra_transferencia",
            "SetMyRegraTransferenciaAtiva",
            pb.SetMyRegraTransferenciaAtivaRequest(
                id=regra_id, ativa=True, dry_run=dry_run
            ),
            contabilizar=not dry_run,
        )
        if dry_run:
            executor.registrar_simulacao(tool)
            if r.regra.ativa:
                return resultado_dry_run(tool, f"nada — '{r.regra.nome}' já está ativa")
            return resultado_dry_run(tool, f"ativar a regra '{r.regra.nome}'")
        return f"Regra '{r.regra.nome}' ativa."

    registro.registrar("set_sinais_transferencia", Categoria.CONFIGURACAO, ESCREVER)

    @mcp.tool(
        name="set_sinais_transferencia",
        annotations=registro.exigir("set_sinais_transferencia").anotacoes,
    )
    async def set_sinais_transferencia(
        sinal: Annotated[
            Sinal | None, Field(default=None, description="O sinal a mudar.")
        ] = None,
        ativo: Annotated[bool | None, Field(default=None)] = None,
        sensibilidade: Annotated[Sensibilidade | None, Field(default=None)] = None,
        fluxo_padrao_id: Annotated[
            int | None,
            Field(default=None, description="Fluxo de destino padrão; 0 limpa."),
        ] = None,
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> dict[str, object]:
        """Liga/desliga um sinal automático, muda a sensibilidade dele, e/ou o
        fluxo padrão de destino. Padrões: pedido de humano, irritação e "na
        dúvida, transferir" ligados; base sem resposta e resposta sem apoio
        desligados (o cliente recebe a mensagem de "não encontrei")."""
        tool = registro.exigir("set_sinais_transferencia")
        sinais = []
        if sinal is not None:
            if ativo is None and sensibilidade is None:
                raise ToolError("Diga `ativo` e/ou `sensibilidade` do sinal.")
            atual = await executor.executar(
                "set_sinais_transferencia",
                "GetMyConfigTransferencia",
                pb.GetMyConfigTransferenciaRequest(),
                contabilizar=False,
            )
            base = next((s for s in atual.config.sinais if s.nome == sinal), None)
            sinais.append(
                pb.SinalTransferencia(
                    nome=sinal,
                    ativo=ativo if ativo is not None else bool(base and base.ativo),
                    sensibilidade=sensibilidade
                    or (base.sensibilidade if base else "media"),
                )
            )
        elif fluxo_padrao_id is None:
            raise ToolError("Nada a alterar: informe `sinal` ou `fluxo_padrao_id`.")
        r = await executor.executar(
            "set_sinais_transferencia",
            "SetMySinaisTransferencia",
            pb.SetMySinaisTransferenciaRequest(
                sinais=sinais,
                alterar_fluxo_padrao=fluxo_padrao_id is not None,
                fluxo_padrao_id=fluxo_padrao_id or 0,
                dry_run=dry_run,
            ),
            contabilizar=not dry_run,
        )
        if dry_run:
            executor.registrar_simulacao(tool)
        return {"simulacao": dry_run, **para_dict(r.config)}

    registro.registrar(
        "gerar_sugestoes_transferencia", Categoria.CONFIGURACAO, ESCREVER
    )

    @mcp.tool(
        name="gerar_sugestoes_transferencia",
        annotations=registro.exigir("gerar_sugestoes_transferencia").anotacoes,
    )
    async def gerar_sugestoes_transferencia(
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Lê o texto de transferência antigo (comportamento das intenções e o
        prompt de regras de transferência) e cria **sugestões inativas** de
        regra, para revisar e ativar. Não duplica o que já existe."""
        tool = registro.exigir("gerar_sugestoes_transferencia")
        if dry_run:
            executor.registrar_simulacao(tool)
            return resultado_dry_run(
                tool, "criar sugestões INATIVAS de regra a partir do texto antigo"
            )
        r = await executor.executar(
            "gerar_sugestoes_transferencia",
            "GerarMySugestoesTransferencia",
            pb.GerarMySugestoesTransferenciaRequest(),
        )
        return f"{r.criadas} sugestão(ões) criada(s), inativas."

    # -- Destrutiva ---------------------------------------------------------
    registro.registrar("desativar_regra_transferencia", Categoria.DESTRUTIVA, ESCREVER)

    @mcp.tool(
        name="desativar_regra_transferencia",
        annotations=registro.exigir("desativar_regra_transferencia").anotacoes,
    )
    async def desativar_regra_transferencia(
        regra_id: Annotated[int, REGRA_ID],
        confirmar: Annotated[
            str,
            Field(
                default="",
                description="O nome exato da regra. Sem ele nada é desativado.",
            ),
        ] = "",
        dry_run: Annotated[bool, DRY_RUN] = False,
    ) -> str:
        """Desativa uma regra: ela deixa de valer na próxima mensagem (nada é
        apagado; reative com `ativar_regra_transferencia`). Exige `confirmar`
        igual ao nome — rode `dry_run=true` primeiro e mostre à pessoa."""
        tool = registro.exigir("desativar_regra_transferencia")
        if dry_run:
            executor.registrar_simulacao(tool)
            r = await executor.executar(
                "desativar_regra_transferencia",
                "SetMyRegraTransferenciaAtiva",
                pb.SetMyRegraTransferenciaAtivaRequest(
                    id=regra_id, ativa=False, dry_run=True
                ),
                contabilizar=False,
            )
            return resultado_dry_run(
                tool,
                f"desativar a regra '{r.regra.nome}'. Para confirmar, repita com "
                f"confirmar='{r.regra.nome}'",
            )
        if not confirmar.strip():
            raise ToolError(
                "Desativar exige `confirmar` com o nome da regra. Rode com "
                "`dry_run=true` e repita com o nome mostrado."
            )
        r = await executor.executar(
            "desativar_regra_transferencia",
            "SetMyRegraTransferenciaAtiva",
            pb.SetMyRegraTransferenciaAtivaRequest(
                id=regra_id, ativa=False, confirmar=confirmar
            ),
        )
        return f"Regra '{r.regra.nome}' desativada."
