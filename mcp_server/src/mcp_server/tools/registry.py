"""Registro de tools: escopo exigido, categoria e o filtro de `tools/list`.

# Por que `tools/list` é filtrado

A spec prevê explicitamente que um servidor devolva listas diferentes conforme a
autorização. É a diferença entre um agente que sabe o que pode fazer e um que
descobre por tentativa e erro — e cada tentativa errada é uma chamada recusada
que o modelo precisa interpretar.

Três requisitos que acompanham o filtro:

1. **Ordem determinística.** A lista sai sempre na ordem de registro, nunca na
   de iteração de um dicionário — dois `tools/list` do mesmo token devolvem
   exatamente a mesma sequência.
2. **`cacheScope` nunca público.** A lista varia por token; um cache público
   permitiria a um intermediário servir a superfície de um usuário a outro. É a
   razão de este servidor não declarar dica de cache para `tools/list`.
3. **A lista não é a barreira.** Esconder uma tool não impede um agente de
   chamá-la pelo nome. O guard de escopo em `guards.py` roda em toda execução,
   independentemente do que a listagem mostrou.

# Como o filtro sabe quem está chamando

`MCPServer.list_tools()` não recebe contexto — o handler interno
`_handle_list_tools(ctx, params)` chama `self.list_tools()` sem repassar o `ctx`.
A identidade vem do contextvar de autenticação, via `get_access_token()`. É por
isso que este arquivo sobrescreve `list_tools` (método público, contrato
estável) em vez de mexer no `_handle_list_tools` (privado, frágil).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

from mcp.server import MCPServer
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.types import Tool as MCPTool
from mcp.types import ToolAnnotations

from mcp_server.auth import scopes as catalogo


class Categoria(StrEnum):
    """Categoria da tool. Define o teto de rate limit e as salvaguardas."""

    LEITURA = "leitura"
    CONFIGURACAO = "configuracao"
    ENVIO = "envio"
    DESTRUTIVA = "destrutiva"


@dataclass(frozen=True)
class ToolRegistrada:
    nome: str
    categoria: Categoria
    #: Escopos que satisfazem a tool. Basta **um**.
    escopos: tuple[str, ...]
    anotacoes: ToolAnnotations
    #: Posição de registro — o que garante ordem determinística.
    ordem: int


@dataclass
class Registro:
    """Catálogo de tools do servidor, com o escopo de cada uma."""

    _por_nome: dict[str, ToolRegistrada] = field(default_factory=dict)
    _proxima_ordem: int = 0

    def registrar(
        self,
        nome: str,
        categoria: Categoria,
        escopos: tuple[str, ...],
    ) -> ToolRegistrada:
        if nome in self._por_nome:
            raise ValueError(f"tool `{nome}` registrada duas vezes")
        if not escopos:
            # Tool sem escopo seria tool que qualquer token executa — não existe
            # caso legítimo disso neste servidor.
            raise ValueError(f"tool `{nome}` precisa declarar ao menos um escopo")

        registrada = ToolRegistrada(
            nome=nome,
            categoria=categoria,
            escopos=escopos,
            anotacoes=_anotacoes_de(categoria),
            ordem=self._proxima_ordem,
        )
        self._por_nome[nome] = registrada
        self._proxima_ordem += 1
        return registrada

    def buscar(self, nome: str) -> ToolRegistrada | None:
        return self._por_nome.get(nome)

    def exigir(self, nome: str) -> ToolRegistrada:
        """Como `buscar`, mas para quem sabe que a tool existe.

        Usado dentro dos módulos de tool, onde o registro acabou de acontecer
        três linhas acima. Devolver `Optional` ali obrigaria cada uma das 28
        tools a tratar um `None` que só aconteceria por erro de digitação — e o
        tratamento seria pior que a exceção, porque esconderia o erro.
        """
        registrada = self._por_nome.get(nome)
        if registrada is None:
            raise KeyError(f"tool `{nome}` não registrada")
        return registrada

    def nomes_permitidos(self, escopos_do_token: list[str]) -> list[str]:
        """Nomes das tools que este token pode executar, em ordem de registro."""
        return [
            r.nome
            for r in sorted(self._por_nome.values(), key=lambda r: r.ordem)
            if catalogo.tem_algum(escopos_do_token, r.escopos)
        ]

    def todos(self) -> list[ToolRegistrada]:
        return sorted(self._por_nome.values(), key=lambda r: r.ordem)


def _anotacoes_de(categoria: Categoria) -> ToolAnnotations:
    """Anotações coerentes com a categoria.

    **Não são barreira.** A spec manda o cliente tratar anotações como não
    confiáveis; elas servem para o cliente decidir se pede confirmação ao
    usuário. Toda restrição real está nos guards e no `runtime_api`.
    """
    if categoria is Categoria.LEITURA:
        return ToolAnnotations(
            read_only_hint=True,
            destructive_hint=False,
            idempotent_hint=True,
            open_world_hint=False,
        )
    if categoria is Categoria.CONFIGURACAO:
        return ToolAnnotations(
            read_only_hint=False,
            destructive_hint=False,
            idempotent_hint=False,
            open_world_hint=False,
        )
    if categoria is Categoria.ENVIO:
        # `open_world_hint=True`: a mensagem sai do sistema e vai para o
        # telefone de uma pessoa. Não há desfazer.
        return ToolAnnotations(
            read_only_hint=False,
            destructive_hint=True,
            idempotent_hint=False,
            open_world_hint=True,
        )
    return ToolAnnotations(
        read_only_hint=False,
        destructive_hint=True,
        idempotent_hint=False,
        open_world_hint=False,
    )


class ServidorMcpFiltrado(MCPServer):
    """`MCPServer` cujo `tools/list` mostra só o que o token pode executar."""

    def __init__(self, *args: Any, registro: Registro, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._registro = registro

    async def list_tools(self) -> list[MCPTool]:
        todas = await super().list_tools()
        token = get_access_token()
        if token is None:
            # Sem token não há superfície a mostrar. O SDK só chega aqui em
            # configuração sem autenticação; devolver tudo seria vazar o
            # catálogo inteiro para quem não se identificou.
            return []

        permitidas = set(self._registro.nomes_permitidos(list(token.scopes)))
        ordem = {r.nome: r.ordem for r in self._registro.todos()}
        # Ordena pela posição de registro, não pela ordem em que o SDK devolveu.
        return sorted(
            (t for t in todas if t.name in permitidas),
            key=lambda t: ordem.get(t.name, 10_000),
        )
