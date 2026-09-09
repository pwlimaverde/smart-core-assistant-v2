"""Fixtures compartilhadas.

O ponto delicado é simular a autenticação: o SDK guarda o usuário autenticado num
`contextvar` que o middleware preenche por requisição. Os testes preenchem o
mesmo contextvar diretamente — é o que permite exercitar o filtro de `tools/list`
e os guards sem subir um servidor HTTP e sem falsificar um JWT.
"""

from __future__ import annotations

import contextlib
from collections.abc import Iterator
from typing import Any

import pytest
from mcp.server.auth.middleware.auth_context import auth_context_var
from mcp.server.auth.middleware.bearer_auth import AuthenticatedUser
from mcp.server.auth.provider import AccessToken

from mcp_server.tools.guards import LimiteCategoria, RateLimiter
from mcp_server.tools.registry import Categoria


@contextlib.contextmanager
def como(
    escopos: list[str],
    *,
    token: str = "token-do-cliente-nao-deve-vazar",
    grant_id: str = "grant-1",
    tenant_id: str = "11111111-1111-1111-1111-111111111111",
    user_id: int = 7,
) -> Iterator[AccessToken]:
    """Executa o bloco como se um cliente MCP autenticado estivesse chamando."""
    access = AccessToken(
        token=token,
        client_id="https://claude.ai/mcp-client",
        scopes=escopos,
        expires_at=None,
        resource="https://mcp.smartcoreassistant.com.br",
        subject=str(user_id),
        claims={
            "sub": str(user_id),
            "tenant_id": tenant_id,
            "grant_id": grant_id,
            "jti": "jti-1",
            "scopes": escopos,
        },
    )
    marca = auth_context_var.set(AuthenticatedUser(access))
    try:
        yield access
    finally:
        auth_context_var.reset(marca)


class ClienteFalso:
    """Substitui o `RuntimeApiClient` e **registra o metadata** de cada chamada.

    Guardar o metadata é o ponto: é sobre ele que o teste prova que o token do
    cliente não é repassado ao backend.
    """

    def __init__(self, respostas: dict[str, Any] | None = None) -> None:
        self.chamadas: list[tuple[str, Any, str]] = []
        self.respostas = respostas or {}

    async def chamar(
        self,
        metodo: str,
        requisicao: Any,
        token_interno: str,
        traceparent: str | None = None,
    ) -> Any:
        self.chamadas.append((metodo, requisicao, token_interno))
        if metodo in self.respostas:
            return self.respostas[metodo]
        raise AssertionError(f"chamada inesperada ao backend: {metodo}")

    @property
    def metodos(self) -> list[str]:
        return [c[0] for c in self.chamadas]


class TrocadorFalso:
    """Devolve sempre o mesmo token interno, sem rede."""

    TOKEN_INTERNO = "jwt-interno-de-teste"

    def __init__(self) -> None:
        self.recebeu: list[str] = []

    async def obter(self, access_token: str, jti: str) -> str:
        self.recebeu.append(access_token)
        return self.TOKEN_INTERNO


class MetricasFalsas:
    def __init__(self) -> None:
        self.execucoes: list[tuple[str, str]] = []
        self.negacoes: list[tuple[str, str]] = []

    def tool_executada(self, tool: str, resultado: str, duracao_s: float) -> None:
        self.execucoes.append((tool, resultado))

    def negada(self, tool: str, motivo: str) -> None:
        self.negacoes.append((tool, motivo))


@pytest.fixture
def limitador_generoso() -> RateLimiter:
    return RateLimiter(
        {
            Categoria.LEITURA: LimiteCategoria(1000),
            Categoria.CONFIGURACAO: LimiteCategoria(1000),
            Categoria.ENVIO: LimiteCategoria(1000, 1000),
            Categoria.DESTRUTIVA: LimiteCategoria(1000, 1000),
        }
    )
