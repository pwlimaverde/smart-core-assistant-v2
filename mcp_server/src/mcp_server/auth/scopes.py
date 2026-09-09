"""Espelho do catálogo canônico de escopos (doc 09 §3).

Este arquivo é a terceira cópia do catálogo — as outras duas são
`derivar_escopos` (Rust, no login) e `oauth/scopes.rs` (Rust, no consentimento).
Três cópias é uma a mais do que o ideal, e a alternativa (gerar o catálogo a
partir de um arquivo compartilhado) foi descartada porque criaria um passo de
build entre dois ecossistemas para uma lista de 14 strings que muda de ano em
ano.

O que impede a divergência é o teste `catalogo_bate_com_o_lado_rust`, que lê o
`oauth/scopes.rs` e compara escopo a escopo. Se alguém acrescentar um escopo no
Rust e esquecer aqui, o `pytest` do módulo quebra.
"""

from __future__ import annotations

from typing import Final

#: Ordem canônica — a mesma do lado Rust. `tools/list` usa esta ordem para ser
#: determinístico entre chamadas.
CATALOGO: Final[tuple[str, ...]] = (
    "atendimentos:read",
    "atendimentos:write",
    "clientes:read",
    "clientes:write",
    "operacional:read",
    "operacional:admin",
    "kanban:admin",
    "treinamento:read",
    "treinamento:write",
    "financeiro:read",
    "financeiro:write",
    "configuracoes:read",
    "configuracoes:write",
    "tenant:admin",
)

#: Escopo que implica todos os outros (doc 09 §3).
ADMIN: Final[str] = "tenant:admin"

#: Coringa do superusuário. Não deveria aparecer num token MCP (D4 do plano
#: proíbe superusuário conectar agente), mas é tratado por completude: se um dia
#: aparecer, o comportamento é explícito e não acidental.
CORINGA: Final[str] = "*"


def tem_escopo(escopos_do_token: list[str], exigido: str) -> bool:
    """`True` se o token satisfaz o escopo exigido.

    `tenant:admin` e `*` satisfazem qualquer exigência — a mesma regra que o
    `RequestContext::has_permission` aplica do lado do banco. Duplicá-la aqui é
    ergonomia (falhar rápido, com mensagem que ensina o agente), não segurança:
    a barreira real está no `runtime_api` e no repositório.
    """
    return any(e in (CORINGA, ADMIN) or e == exigido for e in escopos_do_token)


def tem_algum(escopos_do_token: list[str], exigidos: tuple[str, ...]) -> bool:
    """`True` se o token satisfaz **ao menos um** dos escopos exigidos."""
    return any(tem_escopo(escopos_do_token, e) for e in exigidos)


def ordenar(escopos: list[str]) -> list[str]:
    """Devolve os escopos na ordem do catálogo, descartando desconhecidos."""
    return [e for e in CATALOGO if e in escopos]
