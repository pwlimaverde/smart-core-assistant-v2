"""`tools/list` por autorização — o que o agente enxerga.

Estes testes cobrem três itens do Definition of Done da fase:

* token só-leitura **não vê** nenhuma tool de escrita;
* dois tokens de escopos diferentes recebem listas diferentes;
* a lista é determinística entre chamadas.

E um quarto, que não está no DoD mas é o achado de segurança que motivou o
requisito: a lista **não** pode ser cacheável publicamente, porque varia por
token.
"""

from __future__ import annotations

import os

import pytest

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.server import montar  # noqa: E402
from tests.conftest import como  # noqa: E402

SO_LEITURA = ["atendimentos:read", "clientes:read", "operacional:read"]
ADMIN = ["tenant:admin"]
STAFF = ["clientes:read", "atendimentos:read", "atendimentos:write"]


@pytest.fixture(scope="module")
def servidor():
    return montar()


async def nomes(servidor, escopos: list[str]) -> list[str]:
    with como(escopos):
        return [t.name for t in await servidor.list_tools()]


async def test_token_so_leitura_nao_ve_nenhuma_tool_de_escrita(servidor):
    visiveis = await nomes(servidor, SO_LEITURA)

    assert visiveis, "um token de leitura precisa ver ao menos as tools de leitura"
    for proibida in (
        "create_fluxo",
        "create_departamento",
        "send_message",
        "desativar_fluxo",
        "remover_conexao_whatsapp",
        "set_bot_persona",
    ):
        assert proibida not in visiveis


async def test_admin_ve_o_catalogo_inteiro(servidor):
    visiveis = await nomes(servidor, ADMIN)
    assert len(visiveis) == len(servidor._registro.todos())
    assert "send_message" in visiveis
    assert "remover_conexao_whatsapp" in visiveis


async def test_dois_tokens_de_escopos_diferentes_recebem_listas_diferentes(servidor):
    assert await nomes(servidor, SO_LEITURA) != await nomes(servidor, ADMIN)


async def test_staff_ve_envio_mas_nao_ve_configuracao_estrutural(servidor):
    visiveis = await nomes(servidor, STAFF)
    # `staff` tem atendimentos:write, então envia mensagem…
    assert "send_message" in visiveis
    # …mas não mexe na estrutura do negócio.
    assert "create_departamento" not in visiveis
    assert "create_fluxo" not in visiveis
    assert "get_tenant_config" not in visiveis


async def test_lista_e_deterministica_entre_chamadas(servidor):
    primeira = await nomes(servidor, ADMIN)
    segunda = await nomes(servidor, ADMIN)
    terceira = await nomes(servidor, ADMIN)
    assert primeira == segunda == terceira


async def test_ordem_segue_o_registro_com_leitura_primeiro(servidor):
    visiveis = await nomes(servidor, ADMIN)
    # Leitura antes de escrita: o agente precisa listar para obter ids, e modelos
    # dão peso à ordem em que as ferramentas aparecem.
    assert visiveis[0] == "get_painel"
    assert visiveis.index("list_fluxos") < visiveis.index("create_fluxo")
    assert visiveis.index("create_fluxo") < visiveis.index("desativar_fluxo")


async def test_sem_token_a_lista_e_vazia(servidor):
    # Sem autenticação não se devolve o catálogo: a superfície do servidor é ela
    # mesma informação sobre o que existe do outro lado.
    assert await servidor.list_tools() == []


async def test_toda_tool_visivel_declara_anotacao_coerente(servidor):
    with como(ADMIN):
        tools = await servidor.list_tools()

    registro = servidor._registro
    for t in tools:
        registrada = registro.exigir(t.name)
        assert t.annotations is not None, f"{t.name} sem annotations"
        if registrada.categoria.value == "leitura":
            assert t.annotations.read_only_hint is True
        else:
            assert t.annotations.read_only_hint is False
        if registrada.categoria.value in ("envio", "destrutiva"):
            # O cliente usa `destructive_hint` para decidir se pede confirmação
            # ao usuário. Não é barreira — a barreira é o guard —, mas errar a
            # anotação faz o cliente deixar de perguntar.
            assert t.annotations.destructive_hint is True
            assert t.annotations.idempotent_hint is False


async def test_nenhuma_tool_declara_cache_publico(servidor):
    """A lista varia por token; cache público a serviria de um usuário a outro.

    O servidor não declara `cache_hints`, e este teste é a trava contra alguém
    acrescentar `cacheScope: "public"` achando que é otimização inofensiva.
    """
    assert getattr(servidor, "_cache_hints", None) in (None, {})


async def test_toda_tool_tem_descricao_util(servidor):
    """A descrição é a interface: sem ela o agente erra com confiança."""
    with como(ADMIN):
        tools = await servidor.list_tools()

    for t in tools:
        assert t.description, f"{t.name} sem descrição"
        assert len(t.description) > 80, (
            f"{t.name} tem descrição curta demais para orientar um modelo"
        )
