"""Tools de envio — o único efeito deste servidor que sai do sistema.

Uma mensagem enviada chega ao telefone de uma pessoa real e não tem desfazer. É o
risco central do módulo inteiro, e é por isso que esta categoria acumula todas as
salvaguardas ao mesmo tempo: escopo `atendimentos:write`, `dry_run`, confirmação
casada com o nome do contato, e o rate limit mais apertado do servidor (10/min,
100/dia).

# Conteúdo de mensagem é PII

O texto enviado **não** entra em log, span, métrica nem no `context` da
auditoria. O que fica registrado é `atendimento_id` e o tamanho. Vale também para
a mensagem de confirmação e para o texto de qualquer `ToolError` daqui — o SDK
loga `str(exc)` no caminho de erro de tool.
"""

from __future__ import annotations

from typing import Annotated

from mcp.server.mcpserver.exceptions import ToolError
from pydantic import Field

from mcp_server.grpc.contracts import admin_pb2 as pb
from mcp_server.tools.base import Executor
from mcp_server.tools.guards import exigir_confirmacao, resultado_dry_run
from mcp_server.tools.registry import Categoria, Registro

#: Teto de tamanho da mensagem. O WhatsApp aceita mais, mas um agente que gera
#: 20 KB de texto para um cliente está errando de um jeito que vale interromper.
MAX_CONTEUDO = 4000


def registrar(mcp, registro: Registro, executor: Executor) -> None:
    """Registra as tools de envio no servidor."""

    registro.registrar("send_message", Categoria.ENVIO, ("atendimentos:write",))

    @mcp.tool(
        name="send_message", annotations=registro.exigir("send_message").anotacoes
    )
    async def send_message(
        atendimento_id: Annotated[
            int,
            Field(
                description=(
                    "Atendimento em que a mensagem entra, de `list_atendimentos`."
                )
            ),
        ],
        conteudo: Annotated[
            str, Field(description="O texto que será enviado ao cliente.")
        ],
        confirmar: Annotated[
            str,
            Field(
                default="",
                description=(
                    "O `contato_id` deste atendimento, como aparece em "
                    "`list_atendimentos`. Serve de confirmação: só preencha depois "
                    "de conferir com a pessoa que você está ajudando que a mensagem "
                    "deve mesmo ser enviada."
                ),
            ),
        ] = "",
        dry_run: Annotated[
            bool,
            Field(
                default=False,
                description="Se true, mostra o que seria enviado e não envia nada.",
            ),
        ] = False,
    ) -> str:
        """Envia uma mensagem de texto ao cliente, dentro de um atendimento.

        **Esta ação não tem desfazer.** A mensagem chega ao WhatsApp de uma pessoa
        real, em nome do negócio.

        Antes de chamar: leia a conversa com `get_thread`, escreva a mensagem,
        **mostre o texto à pessoa que está pedindo** e só então envie. Use
        `dry_run=true` para revisar antes.

        NÃO use para: mandar mensagem em massa, testar o sistema, ou responder
        sem ter lido a conversa.
        """
        tool = registro.exigir("send_message")

        texto = conteudo.strip()
        if not texto:
            raise ToolError("A mensagem está vazia; escreva o texto antes de enviar.")
        if len(texto) > MAX_CONTEUDO:
            raise ToolError(
                f"A mensagem tem {len(texto)} caracteres e o limite é {MAX_CONTEUDO}. "
                "Encurte o texto."
            )

        if dry_run:
            executor.registrar_simulacao(tool)
            # O texto NÃO é ecoado aqui: o retorno de uma tool pode ser logado
            # pelo cliente, e a simulação não precisa repetir o conteúdo — quem
            # pediu já o escreveu.
            return resultado_dry_run(
                tool,
                f"enviar uma mensagem de {len(texto)} caracteres no atendimento "
                f"{atendimento_id}",
            )

        # Confirmação nível 2. O alvo é o `contato_id`, não o nome do contato.
        #
        # O plano previa o nome, e para as tools destrutivas é isso mesmo que se
        # usa. Aqui não dá, por dois motivos concretos: nenhum RPC do backend
        # resolve um contato a partir do id (só há busca por texto), e o texto de
        # um `ToolError` vai para o log do processo — pôr o nome de um cliente ali
        # violaria a regra de PII do módulo. O `contato_id` preserva a propriedade
        # que interessa: o agente só o obtém listando os atendimentos de verdade,
        # então um `atendimento_id` alucinado não produz um par que confira.
        contato_id = await _contato_do_atendimento(executor, atendimento_id)
        exigir_confirmacao(tool, str(contato_id), confirmar or None)

        resposta = await executor.executar(
            "send_message",
            "SendOutboundMessage",
            pb.SendOutboundMessageRequest(
                atendimento_id=atendimento_id, conteudo=texto, tipo="texto"
            ),
        )
        return (
            f"Mensagem enviada no atendimento {atendimento_id} "
            f"(id da mensagem: {resposta.message_id})."
        )


#: Teto da varredura que resolve o atendimento. Alto porque a lista vem ordenada
#: por atividade e um atendimento antigo pode estar fundo — mas finito, para que
#: a resolução não vire uma consulta ilimitada disparada por argumento de agente.
_LIMITE_BUSCA_ATENDIMENTO = 500


async def _contato_do_atendimento(executor: Executor, atendimento_id: int) -> int:
    """Resolve, **no servidor**, o contato dono do atendimento.

    Resolver aqui é o ponto da salvaguarda: se aceitássemos o par
    (atendimento, contato) informado pelo agente, a confirmação não confirmaria
    nada — ele poderia inventar os dois.
    """
    resposta = await executor.executar(
        "send_message",
        "ListAtendimentos",
        pb.ListAtendimentosRequest(
            status="", departamento_id=0, limit=_LIMITE_BUSCA_ATENDIMENTO
        ),
       contabilizar=False,
    )
    for resumo in resposta.atendimentos:
        if resumo.id == atendimento_id:
            return int(resumo.contato_id)

    raise ToolError(
        f"O atendimento {atendimento_id} não foi encontrado entre os atendimentos "
        "deste negócio. Liste com `list_atendimentos` e use um id de lá."
    )
