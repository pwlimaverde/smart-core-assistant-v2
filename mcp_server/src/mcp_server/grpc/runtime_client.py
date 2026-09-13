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

from mcp_server.grpc.contracts import admin_pb2_grpc


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
            self._canal = grpc.aio.insecure_channel(self._endpoint)
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
    ) -> Any:
        """Executa um RPC do `AdminService`.

        `token_interno` é o JWT trocado; nunca o token do cliente. `grant_id` é
        o consentimento em nome do qual o agente age (B3).
        """
        stub = await self._garantir_canal()
        rpc = getattr(stub, metodo, None)
        if rpc is None:
            raise ErroDoBackend(f"operação `{metodo}` não existe no backend")

        # `user-agent` marca a ORIGEM da ação na trilha de auditoria.
        #
        # O `runtime_api` copia este header para o campo `user_agent` do envelope,
        # e de lá ele chega ao `audit_log`. É o que faz "o que o agente do fulano
        # fez ontem" ser uma consulta de um filtro só, sem tabela nova e sem
        # campo novo no contrato — o prefixo `SmartCoreAssistant-MCP` distingue
        # ação de agente de ação humana, e o nome da tool diz qual foi.
        #
        # O grant vai junto, entre parênteses (B3): sem ele a trilha sabia QUE
        # foi um agente, mas não QUAL aplicativo — e a pergunta do dono é "o que
        # o Claude fez", não "o que algum agente fez". O token interno não
        # carrega o grant, e o user-agent já chega ao `audit_log` sem mudança
        # nenhuma no contrato. É um identificador, não segredo.
        user_agent = f"SmartCoreAssistant-MCP/{metodo}"
        if grant_id:
            user_agent = f"{user_agent} (grant {grant_id})"
        metadata = [
            ("authorization", f"Bearer {token_interno}"),
            ("user-agent", user_agent),
        ]
        if traceparent:
            # Continua o trace do cliente MCP até o Postgres — é o que permite
            # ver uma chamada de agente inteira num span só no Tempo.
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
