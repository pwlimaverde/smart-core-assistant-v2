"""Cliente gRPC do `runtime_api` — a única porta de dados deste processo.

# O invariante que este arquivo protege

O `mcp_server` **não** fala com o banco. Não tem `DATABASE_URL`, não está na rede
`internal` e, dentro do container, os nomes `postgres`, `data_postgres` e
`data_redis` não resolvem. Toda leitura e escrita passa por aqui, e daqui pelo
`runtime_api` — que é o único componente capaz de cunhar um envelope de
identidade confiável, e onde a RLS e a trilha de auditoria já acontecem.

A barreira é topológica (a rede `mcp_net` do compose), não uma convenção de
código. Este comentário explica *por quê*; o teste
`test_isolamento_de_rede.py` prova que continua valendo.

# O token que sai daqui não é o token que entrou

O metadata gRPC carrega o **JWT interno**, obtido do `control_plane`. O access
token do cliente MCP nunca cruza esta fronteira — exigência normativa da spec, e
o `test_token_do_cliente_nao_vaza_no_metadata` é a prova.
"""

from __future__ import annotations

from typing import Any

import grpc
from loguru import logger
from opentelemetry.propagate import inject

from mcp_server.grpc.contracts import admin_pb2_grpc

#: Prefixo que a trilha de auditoria reconhece como ação de agente
#: (`infrastructure_postgres::auditoria::audit_log::PREFIXO_USER_AGENT_MCP`).
PREFIXO_ORIGEM = "SmartCoreAssistant-MCP"

#: Header em que a origem de cada chamada viaja (lido pelo `runtime_api`).
HEADER_ORIGEM = "x-smartcore-agente"


def origem_da_chamada(operacao: str, grant_id: str | None) -> str:
    """`SmartCoreAssistant-MCP/<tool> (grant <id>)` — o formato que a trilha lê."""
    origem = f"{PREFIXO_ORIGEM}/{operacao}"
    if grant_id:
        origem = f"{origem} (grant {grant_id})"
    return origem


def traceparent_atual() -> str | None:
    """`traceparent` W3C do span em curso, ou `None` sem span (OTel desligado)."""
    portador: dict[str, str] = {}
    inject(portador)
    return portador.get("traceparent")


def _e_duplicidade(detalhe: str) -> bool:
    """O backend recusou por violação de unicidade (o registro já existe)."""
    texto = detalhe.casefold()
    return any(
        marca in texto for marca in ("unicidade", "duplicate key", "unique constraint")
    )


class ErroDoBackend(Exception):
    """Falha vinda do `runtime_api`, já traduzida para linguagem de agente.

    A mensagem é lida por um LLM e **vai para o log do processo** (o SDK loga o
    `str` da exceção no caminho de erro de tool). Por isso ela carrega só nome de
    operação, escopo e identificadores — nunca nome de contato, telefone ou
    trecho de mensagem.
    """

    def __init__(self, mensagem: str, codigo: grpc.StatusCode | None = None) -> None:
        super().__init__(mensagem)
        self.codigo = codigo


class RuntimeApiClient:
    """Canal único e reutilizado para o `AdminService`.

    Um canal por processo, não por chamada: o gRPC multiplexa sobre HTTP/2, e
    abrir canal por requisição custaria um handshake por chamada de tool.
    """

    def __init__(self, endpoint: str, timeout_s: float = 30.0) -> None:
        self._endpoint = endpoint
        self._timeout = timeout_s
        self._canal: grpc.aio.Channel | None = None
        self._stub: Any = None

    async def _garantir_canal(self) -> Any:
        if self._stub is None:
            # `insecure_channel` porque o tráfego não sai da rede `mcp_net`; o
            # TLS público termina no Caddy, na borda.
            #
            # `grpc.primary_user_agent` marca o canal inteiro como MCP. O
            # `user-agent` por chamada não serve para isso: o core do gRPC o
            # sobrescreve com `grpc-python-asyncio/...` (provado em produção —
            # a trilha de auditoria nunca recebeu o valor que mandávamos).
            self._canal = grpc.aio.insecure_channel(
                self._endpoint,
                options=[("grpc.primary_user_agent", PREFIXO_ORIGEM)],
            )
            self._stub = admin_pb2_grpc.AdminServiceStub(self._canal)
            logger.info("canal gRPC com o runtime_api aberto em {}", self._endpoint)
        return self._stub

    async def chamar(
        self,
        metodo: str,
        requisicao: Any,
        token_interno: str,
        traceparent: str | None = None,
        grant_id: str | None = None,
        tool: str | None = None,
    ) -> Any:
        """Executa um RPC do `AdminService`.

        `token_interno` é o JWT trocado; nunca o token do cliente. `grant_id` é
        o consentimento em nome do qual o agente age (B3). `tool` é o nome da
        tool MCP que pediu a chamada — é ele que a trilha mostra, não o RPC.
        """
        stub = await self._garantir_canal()
        rpc = getattr(stub, metodo, None)
        if rpc is None:
            raise ErroDoBackend(f"operação `{metodo}` não existe no backend")

        # A ORIGEM da ação na trilha de auditoria.
        #
        # O `runtime_api` copia este header para o campo `user_agent` do
        # envelope, e de lá ele chega ao `audit_log`. É o que faz "o que o agente
        # do fulano fez ontem" ser uma consulta de um filtro só, sem tabela nova —
        # o prefixo `SmartCoreAssistant-MCP` distingue ação de agente de ação
        # humana, o nome da tool diz qual foi, e o grant (B3) diz QUAL
        # aplicativo agiu. O grant é identificador, não segredo.
        #
        # Header próprio, e não `user-agent`: o gRPC descarta o `user-agent`
        # passado por chamada.
        metadata = [
            ("authorization", f"Bearer {token_interno}"),
            (HEADER_ORIGEM, origem_da_chamada(tool or metodo, grant_id)),
        ]
        # Continua o trace do agente até o Postgres: sem `traceparent` o
        # `runtime_api` inventa um novo, e a chamada da tool some do trace.
        traceparent = traceparent or traceparent_atual()
        if traceparent:
            metadata.append(("traceparent", traceparent))

        try:
            return await rpc(requisicao, metadata=metadata, timeout=self._timeout)
        except grpc.aio.AioRpcError as exc:
            raise self._traduzir(exc, metodo) from None

    @staticmethod
    def _traduzir(exc: grpc.aio.AioRpcError, metodo: str) -> ErroDoBackend:
        """Traduz o erro gRPC para algo que o agente consiga usar.

        A distinção que importa: `PERMISSION_DENIED` precisa dizer ao agente que
        o problema é permissão e **não** adianta tentar de novo com outros
        argumentos, enquanto `INVALID_ARGUMENT` é exatamente o caso em que
        tentar de novo, corrigido, funciona.
        """
        codigo = exc.code()
        detalhe = exc.details() or ""

        if codigo == grpc.StatusCode.PERMISSION_DENIED:
            msg = (
                f"Permissão insuficiente para `{metodo}`. O usuário que autorizou "
                "este agente não concedeu (ou não possui) a permissão necessária. "
                "Não tente de novo: peça a ele para reconectar concedendo o acesso."
            )
        elif codigo == grpc.StatusCode.UNAUTHENTICATED:
            msg = (
                "A autorização expirou ou foi revogada. Peça ao usuário para "
                "reconectar o aplicativo."
            )
        elif codigo == grpc.StatusCode.NOT_FOUND:
            msg = (
                f"`{metodo}`: o item indicado não existe. "
                "Liste antes de agir sobre um id."
            )
        elif codigo == grpc.StatusCode.INVALID_ARGUMENT:
            # O detalhe do backend é validação de campo, não dado de cliente.
            msg = f"`{metodo}`: argumento inválido ({detalhe})."
        elif codigo == grpc.StatusCode.ALREADY_EXISTS or (
            codigo == grpc.StatusCode.FAILED_PRECONDITION and _e_duplicidade(detalhe)
        ):
            # O detalhe de uma violação de unicidade traz nome de tabela e de
            # constraint: nada que o agente use, e expõe o esquema do banco.
            msg = (
                f"`{metodo}`: já existe um registro igual. Liste antes e altere "
                "o existente em vez de criar outro."
            )
        elif codigo == grpc.StatusCode.FAILED_PRECONDITION:
            msg = f"`{metodo}`: a operação conflita com o estado atual ({detalhe})."
        elif codigo == grpc.StatusCode.DEADLINE_EXCEEDED:
            msg = f"`{metodo}`: o backend demorou demais. Tente de novo em instantes."
        else:
            # Detalhe de erro interno NÃO vai para o agente: pode conter dado do
            # sistema, e o modelo não tem o que fazer com ele.
            logger.error("erro inesperado do runtime_api em {}: {}", metodo, codigo)
            msg = (
                f"`{metodo}`: falha temporária no sistema. Tente de novo em instantes."
            )

        return ErroDoBackend(msg, codigo)

    async def fechar(self) -> None:
        if self._canal is not None:
            await self._canal.close()
            self._canal = None
            self._stub = None
