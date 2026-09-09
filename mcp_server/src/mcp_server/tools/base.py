"""O caminho comum de toda tool: identidade → guards → backend → telemetria.

Cada tool é um caso de uso isolado; o que elas compartilham vive aqui, aplicado
como decoração no registro e não como `if` repetido dentro de cada função. Trocar
o transporte do backend, ou acrescentar uma salvaguarda, não toca tool nenhuma.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

from loguru import logger
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.mcpserver.exceptions import ToolError

from mcp_server.auth.token_verifier import (
    IdentidadeMcp,
    TokenInvalido,
    TrocadorDeToken,
)
from mcp_server.grpc.runtime_client import ErroDoBackend, RuntimeApiClient
from mcp_server.telemetry import Metricas
from mcp_server.tools.guards import RateLimiter, exigir_escopo
from mcp_server.tools.registry import Registro, ToolRegistrada


@dataclass
class Executor:
    """Cola entre a tool e o backend. Uma instância por processo."""

    registro: Registro
    cliente: RuntimeApiClient
    trocador: TrocadorDeToken
    limitador: RateLimiter
    metricas: Metricas

    def identidade(self) -> tuple[IdentidadeMcp, str, str]:
        """Quem está chamando, o token bruto e o `jti`.

        O token bruto é necessário para a troca pelo JWT interno — e é o **único**
        lugar do módulo onde ele é manipulado depois da validação. Ele não entra
        em log, span, métrica nem mensagem de erro.
        """
        token = get_access_token()
        if token is None:
            # Não deveria acontecer: o `RequireAuthMiddleware` do SDK barra antes.
            # Se acontecer, é falha de configuração, e recusar é o certo.
            raise ToolError(
                "Esta operação exige uma autorização válida. Reconecte o aplicativo."
            )
        claims: dict[str, Any] = token.claims or {}
        return (
            IdentidadeMcp.de_access_token(token),
            token.token,
            str(claims.get("jti", "")),
        )

    async def executar(
        self,
        nome_da_tool: str,
        metodo_grpc: str,
        requisicao: Any,
        *,
        contabilizar: bool = True,
    ) -> Any:
        """Executa uma tool: valida escopo, conta o limite e chama o backend.

        `contabilizar=False` para as chamadas **internas** que só resolvem o alvo
        de uma ação (ler o nome do fluxo antes de desativá-lo, por exemplo).
        Elas continuam passando pelo mesmo escopo, mas não consomem o teto da
        categoria — cobrá-las teria dois efeitos ruins: uma leitura interna
        gastaria a cota de "destrutivas", e um `dry_run`, que é só resolução,
        consumiria o limite da ação que ele existe justamente para evitar.
        """
        tool = self.registro.exigir(nome_da_tool)
        if tool is None:
            # Tool chamada mas não registrada = erro de programação nosso.
            raise ToolError(
                f"A tool `{nome_da_tool}` não está disponível neste servidor."
            )

        identidade, token_bruto, jti = self.identidade()
        inicio = time.monotonic()

        try:
            exigir_escopo(tool, identidade.escopos)
        except ToolError:
            self.metricas.negada(tool.nome, "escopo")
            raise

        if contabilizar:
            try:
                self.limitador.registrar(identidade.grant_id, tool)
            except ToolError:
                self.metricas.negada(tool.nome, "rate_limit")
                raise

        try:
            interno = await self.trocador.obter(token_bruto, jti)
        except TokenInvalido as exc:
            self.metricas.negada(tool.nome, "troca_de_token")
            raise ToolError(str(exc)) from None

        try:
            resposta = await self.cliente.chamar(metodo_grpc, requisicao, interno)
        except ErroDoBackend as exc:
            self.metricas.tool_executada(tool.nome, "erro", time.monotonic() - inicio)
            raise ToolError(str(exc)) from None

        if contabilizar:
            self.metricas.tool_executada(tool.nome, "ok", time.monotonic() - inicio)
        # `tenant_id` e nome da tool, nada mais: nem argumentos, nem resposta.
        logger.info(
            "tool executada",
            tool=tool.nome,
            tenant_id=identidade.tenant_id,
            categoria=tool.categoria.value,
        )
        return resposta

    def registrar_simulacao(self, tool: ToolRegistrada) -> None:
        """Contabiliza um `dry_run`.

        Simulação **não** consome o rate limit da categoria: ela é justamente o
        que se quer incentivar antes de uma ação irreversível, e cobrá-la do
        mesmo teto empurraria o agente a agir direto.
        """
        self.metricas.tool_executada(tool.nome, "dry_run", 0.0)


def limitar_itens(itens: list[Any], teto: int) -> list[Any]:
    """Corta a lista no teto do servidor.

    Independe do que o agente pediu. Uma lista de cinco mil contatos não ajuda o
    modelo — enche a janela de contexto dele com dado que ele não vai usar e
    aumenta a chance de ele responder sobre o item errado.
    """
    return itens[:teto]
