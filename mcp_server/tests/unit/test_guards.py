"""Salvaguardas: escopo, confirmação, `dry_run`, rate limit e não-vazamento.

Cada teste aqui corresponde a uma linha do Definition of Done da fase N13.
"""

from __future__ import annotations

import os

import pytest
from mcp.server.mcpserver.exceptions import ToolError

os.environ.setdefault("OTEL_SDK_DISABLED", "true")

from mcp_server.grpc.contracts import admin_pb2 as pb  # noqa: E402
from mcp_server.tools import destrutivas, envio, leitura  # noqa: E402
from mcp_server.tools.base import Executor  # noqa: E402
from mcp_server.tools.guards import (  # noqa: E402
    LimiteCategoria,
    RateLimiter,
    exigir_confirmacao,
    exigir_escopo,
)
from mcp_server.tools.registry import Categoria, Registro  # noqa: E402
from tests.conftest import (  # noqa: E402
    ClienteFalso,
    MetricasFalsas,
    TrocadorFalso,
    como,
)


class ServidorFalso:
    """Coleta as funções decoradas sem subir um `MCPServer` de verdade."""

    def __init__(self) -> None:
        self.funcoes: dict[str, object] = {}

    def tool(self, name: str, **_kwargs: object):
        def decorador(fn):
            self.funcoes[name] = fn
            return fn

        return decorador


def montar_ambiente(
    respostas: dict[str, object] | None = None,
    limites: dict[Categoria, LimiteCategoria] | None = None,
) -> tuple[ServidorFalso, Registro, Executor, ClienteFalso, MetricasFalsas]:
    servidor = ServidorFalso()
    registro = Registro()
    cliente = ClienteFalso(respostas or {})
    metricas = MetricasFalsas()
    executor = Executor(
        registro=registro,
        cliente=cliente,  # type: ignore[arg-type]
        trocador=TrocadorFalso(),  # type: ignore[arg-type]
        limitador=RateLimiter(
            limites
            or {
                Categoria.LEITURA: LimiteCategoria(1000),
                Categoria.CONFIGURACAO: LimiteCategoria(1000),
                Categoria.ENVIO: LimiteCategoria(1000, 1000),
                Categoria.DESTRUTIVA: LimiteCategoria(1000, 1000),
            }
        ),
        metricas=metricas,  # type: ignore[arg-type]
    )
    return servidor, registro, executor, cliente, metricas


# ---------------------------------------------------------------------------
# Escopo
# ---------------------------------------------------------------------------


def test_escopo_insuficiente_ensina_o_agente_a_nao_insistir():
    registro = Registro()
    tool = registro.registrar("send_message", Categoria.ENVIO, ("atendimentos:write",))

    with pytest.raises(ToolError) as erro:
        exigir_escopo(tool, ["atendimentos:read"])

    texto = str(erro.value)
    assert "atendimentos:write" in texto
    # A mensagem precisa dizer que insistir não adianta — sem isso o modelo
    # tenta de novo com outros argumentos e queima o rate limit.
    assert "reconectar" in texto


def test_tenant_admin_satisfaz_qualquer_escopo():
    registro = Registro()
    tool = registro.registrar("x", Categoria.DESTRUTIVA, ("operacional:admin",))
    exigir_escopo(tool, ["tenant:admin"])  # não levanta


def test_mensagens_de_erro_nao_carregam_pii():
    """O SDK loga `str(exc)` no caminho de erro de tool.

    Uma mensagem "acionável para o agente" que cite nome de contato ou telefone
    viraria vazamento de PII no log do processo.
    """
    registro = Registro()
    tool = registro.registrar("send_message", Categoria.ENVIO, ("atendimentos:write",))

    with pytest.raises(ToolError) as erro:
        exigir_escopo(tool, [])
    texto_escopo = str(erro.value)

    with pytest.raises(ToolError) as erro:
        exigir_confirmacao(tool, "Maria Silva", "Joao")
    texto_confirmacao = str(erro.value)

    for texto in (texto_escopo, texto_confirmacao):
        assert "Maria" not in texto
        assert "Silva" not in texto
        assert "5511" not in texto


# ---------------------------------------------------------------------------
# Confirmação
# ---------------------------------------------------------------------------


def test_confirmacao_ausente_e_recusada():
    registro = Registro()
    tool = registro.registrar(
        "desativar_fluxo", Categoria.DESTRUTIVA, ("kanban:admin",)
    )
    with pytest.raises(ToolError, match="confirmação"):
        exigir_confirmacao(tool, "Funil de Vendas", None)


def test_confirmacao_divergente_e_recusada():
    registro = Registro()
    tool = registro.registrar(
        "desativar_fluxo", Categoria.DESTRUTIVA, ("kanban:admin",)
    )
    with pytest.raises(ToolError):
        exigir_confirmacao(tool, "Funil de Vendas", "Funil de vendas 2")


def test_confirmacao_correta_passa_ignorando_espacos():
    registro = Registro()
    tool = registro.registrar(
        "desativar_fluxo", Categoria.DESTRUTIVA, ("kanban:admin",)
    )
    exigir_confirmacao(tool, "Funil de Vendas", "  Funil de Vendas  ")


# ---------------------------------------------------------------------------
# dry_run
# ---------------------------------------------------------------------------


async def test_dry_run_de_tool_destrutiva_nao_chama_o_backend():
    """`dry_run` nunca escreve — a prova é o backend não receber a escrita."""
    fluxos = pb.ListMyFluxosResponse(
        fluxos=[pb.MyFluxo(id=3, nome="Funil de Vendas", atendimentos_abertos=12)]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente({"ListMyFluxos": fluxos})
    destrutivas.registrar(servidor, registro, executor)

    with como(["tenant:admin"]):
        resultado = await servidor.funcoes["desativar_fluxo"](fluxo_id=3, dry_run=True)

    assert "SIMULAÇÃO" in resultado
    assert "nada foi alterado" in resultado
    # Diz quantos atendimentos seriam afetados: é a informação que muda a
    # decisão de quem está do outro lado.
    assert "12 atendimento" in resultado
    # Só a leitura que resolve o alvo; nenhuma escrita.
    assert cliente.metodos == ["ListMyFluxos"]
    assert "DesativarMyFluxo" not in cliente.metodos


async def test_dry_run_de_envio_nao_envia_e_nao_ecoa_o_texto():
    servidor, registro, executor, cliente, _ = montar_ambiente()
    envio.registrar(servidor, registro, executor)

    segredo = "Oi Maria, seu pedido 123 chega amanhã"
    with como(["atendimentos:write"]):
        resultado = await servidor.funcoes["send_message"](
            atendimento_id=9, conteudo=segredo, dry_run=True
        )

    assert cliente.chamadas == []
    assert "SIMULAÇÃO" in resultado
    # O conteúdo é PII e o retorno de uma tool pode ser logado pelo cliente.
    assert segredo not in resultado
    assert "Maria" not in resultado
    assert str(len(segredo)) in resultado


async def test_envio_sem_confirmacao_nao_chega_ao_backend():
    atendimentos = pb.ListAtendimentosResponse(
        atendimentos=[pb.AtendimentoResumo(id=9, contato_id=44)]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"ListAtendimentos": atendimentos}
    )
    envio.registrar(servidor, registro, executor)

    with como(["atendimentos:write"]), pytest.raises(ToolError, match="confirmação"):
        await servidor.funcoes["send_message"](atendimento_id=9, conteudo="oi")

    assert "SendOutboundMessage" not in cliente.metodos


async def test_envio_com_confirmacao_correta_chega_ao_backend():
    atendimentos = pb.ListAtendimentosResponse(
        atendimentos=[pb.AtendimentoResumo(id=9, contato_id=44)]
    )
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {
            "ListAtendimentos": atendimentos,
            "SendOutboundMessage": pb.SendOutboundMessageResponse(message_id=77),
        }
    )
    envio.registrar(servidor, registro, executor)

    with como(["atendimentos:write"]):
        resultado = await servidor.funcoes["send_message"](
            atendimento_id=9, conteudo="oi", confirmar="44"
        )

    assert "77" in resultado
    assert "SendOutboundMessage" in cliente.metodos


async def test_envio_para_atendimento_inexistente_e_recusado():
    """Um `atendimento_id` alucinado não passa: ele não produz par que confira."""
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"ListAtendimentos": pb.ListAtendimentosResponse(atendimentos=[])}
    )
    envio.registrar(servidor, registro, executor)

    with (
        como(["atendimentos:write"]),
        pytest.raises(ToolError, match="não foi encontrado"),
    ):
        await servidor.funcoes["send_message"](
            atendimento_id=99999, conteudo="oi", confirmar="1"
        )

    assert "SendOutboundMessage" not in cliente.metodos


# ---------------------------------------------------------------------------
# Rate limit
# ---------------------------------------------------------------------------


def test_rate_limit_de_envio_corta_no_teto_e_diz_quanto_esperar():
    registro = Registro()
    tool = registro.registrar("send_message", Categoria.ENVIO, ("atendimentos:write",))
    limitador = RateLimiter({Categoria.ENVIO: LimiteCategoria(10, 100)})

    for _ in range(10):
        limitador.registrar("grant-1", tool)

    with pytest.raises(ToolError) as erro:
        limitador.registrar("grant-1", tool)

    texto = str(erro.value)
    assert "10 chamadas por minuto" in texto
    # O agente precisa saber quanto esperar; sem isso ele martela.
    assert "segundos" in texto


def test_rate_limit_e_por_grant_e_nao_global():
    registro = Registro()
    tool = registro.registrar("send_message", Categoria.ENVIO, ("atendimentos:write",))
    limitador = RateLimiter({Categoria.ENVIO: LimiteCategoria(2, 100)})

    limitador.registrar("grant-a", tool)
    limitador.registrar("grant-a", tool)
    # O agente de outra pessoa não pode ser afetado pelo laço deste.
    limitador.registrar("grant-b", tool)
    assert limitador.restantes("grant-b", Categoria.ENVIO) == 1


def test_categorias_nao_compartilham_o_mesmo_teto():
    registro = Registro()
    leitura_tool = registro.registrar(
        "list_x", Categoria.LEITURA, ("atendimentos:read",)
    )
    envio_tool = registro.registrar("send_x", Categoria.ENVIO, ("atendimentos:write",))
    limitador = RateLimiter(
        {Categoria.LEITURA: LimiteCategoria(2), Categoria.ENVIO: LimiteCategoria(2, 10)}
    )

    limitador.registrar("g", leitura_tool)
    limitador.registrar("g", leitura_tool)
    # Estourou leitura, mas envio segue disponível.
    limitador.registrar("g", envio_tool)
    assert limitador.restantes("g", Categoria.ENVIO) == 1


async def test_dry_run_nao_consome_o_rate_limit_da_categoria():
    """Simular é o comportamento que se quer incentivar antes de agir.

    Cobrá-lo do mesmo teto empurraria o agente a pular a simulação.
    """
    fluxos = pb.ListMyFluxosResponse(fluxos=[pb.MyFluxo(id=3, nome="Funil")])
    servidor, registro, executor, _, _ = montar_ambiente(
        {"ListMyFluxos": fluxos},
        limites={
            Categoria.LEITURA: LimiteCategoria(1000),
            Categoria.DESTRUTIVA: LimiteCategoria(1, 1),
        },
    )
    destrutivas.registrar(servidor, registro, executor)

    with como(["tenant:admin"]):
        for _ in range(5):
            await servidor.funcoes["desativar_fluxo"](fluxo_id=3, dry_run=True)

    assert executor.limitador.restantes("grant-1", Categoria.DESTRUTIVA) == 1


# ---------------------------------------------------------------------------
# Token passthrough
# ---------------------------------------------------------------------------


async def test_token_do_cliente_nao_vaza_para_o_backend():
    """A prova de D8: o backend recebe o JWT interno, nunca o token do cliente.

    *"The MCP server MUST NOT pass through the token it received from the MCP
    client."*
    """
    servidor, registro, executor, cliente, _ = montar_ambiente(
        {"GetMyPainel": pb.GetMyPainelResponse(em_andamento=3)}
    )
    leitura.registrar(servidor, registro, executor)

    token_do_cliente = "TOKEN-SECRETO-DO-CLIENTE"
    with como(["atendimentos:read"], token=token_do_cliente):
        await servidor.funcoes["get_painel"]()

    assert cliente.chamadas, "a chamada ao backend não aconteceu"
    for _metodo, _req, token_enviado in cliente.chamadas:
        assert token_enviado == TrocadorFalso.TOKEN_INTERNO
        assert token_do_cliente not in token_enviado


async def test_metrica_de_negacao_registra_o_motivo():
    """`smartcore_mcp_denied_total{motivo}` é o que revela agente em laço."""
    servidor, registro, executor, cliente, metricas = montar_ambiente()
    leitura.registrar(servidor, registro, executor)

    with como(["clientes:read"]), pytest.raises(ToolError):
        await servidor.funcoes["get_painel"]()

    assert ("get_painel", "escopo") in metricas.negacoes
    assert cliente.chamadas == []
