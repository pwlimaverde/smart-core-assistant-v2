"""O catálogo de escopos precisa concordar com o lado Rust.

Existem três cópias do catálogo no sistema: `oauth/scopes.rs` (consentimento),
`derivar_escopos` (login) e `auth/scopes.py` (aqui). Este teste é a trava que
impede a terceira de ficar para trás: ele **lê o arquivo Rust** e compara escopo
a escopo.

Se alguém acrescentar um escopo no consentimento e esquecer aqui, o efeito seria
silencioso e ruim — a tool que dependesse dele ficaria invisível para todo mundo,
sem erro em lugar nenhum.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from mcp_server.auth import scopes

FONTE_RUST = (
    Path(__file__).resolve().parents[2].parent
    / "server"
    / "apps"
    / "control_plane"
    / "src"
    / "oauth"
    / "scopes.rs"
)


def escopos_do_rust() -> list[str]:
    texto = FONTE_RUST.read_text(encoding="utf-8")
    # `escopo: "atendimentos:read",` dentro do CATALOGO.
    return re.findall(r'escopo:\s*"([^"]+)"', texto)


@pytest.mark.skipif(
    not FONTE_RUST.is_file(), reason="fonte Rust ausente neste checkout"
)
def test_catalogo_bate_com_o_lado_rust():
    do_rust = escopos_do_rust()
    assert do_rust, "não foi possível extrair o catálogo do Rust"
    assert list(scopes.CATALOGO) == do_rust, (
        "o catálogo Python divergiu do Rust — o consentimento ofereceria escopos "
        "que as tools não reconhecem, ou o contrário"
    )


def test_catalogo_tem_os_14_escopos_do_doc_09():
    assert len(scopes.CATALOGO) == 14


def test_tenant_admin_satisfaz_qualquer_escopo():
    assert scopes.tem_escopo(["tenant:admin"], "financeiro:write")


def test_coringa_de_superusuario_satisfaz_qualquer_escopo():
    assert scopes.tem_escopo(["*"], "tenant:admin")


def test_escopo_exato_satisfaz_apenas_a_si():
    assert scopes.tem_escopo(["atendimentos:read"], "atendimentos:read")
    assert not scopes.tem_escopo(["atendimentos:read"], "atendimentos:write")


def test_read_nao_implica_write():
    """Sem isto, um `viewer` enviaria mensagem — o defeito que N13.3 conserta."""
    viewer = ["atendimentos:read", "clientes:read", "operacional:read"]
    assert not scopes.tem_escopo(viewer, "atendimentos:write")
    assert not scopes.tem_escopo(viewer, "operacional:admin")


def test_lista_vazia_nao_satisfaz_nada():
    for escopo in scopes.CATALOGO:
        assert not scopes.tem_escopo([], escopo)


def test_ordenar_usa_a_ordem_do_catalogo_e_descarta_desconhecidos():
    assert scopes.ordenar(["clientes:read", "atendimentos:read", "inventado:x"]) == [
        "atendimentos:read",
        "clientes:read",
    ]
