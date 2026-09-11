"""Tradução dos erros do backend para algo que um agente consiga usar.

Esta é a parte do módulo que um modelo de linguagem lê quando algo dá errado, e a
diferença entre uma mensagem boa e uma ruim é comportamental: com "permissão
insuficiente, não tente de novo" o agente para; com "erro interno" ele tenta mais
cinco vezes e queima o rate limit.

Os testes verificam as duas propriedades que importam em cada caso: **que a
mensagem diga o que fazer** e **que ela não vaze dado do sistema**.
"""

from __future__ import annotations

import grpc
import pytest

from mcp_server.grpc.runtime_client import ErroDoBackend, RuntimeApiClient


class FalhaFalsa(grpc.aio.AioRpcError):
    """`AioRpcError` sem rede. O construtor real exige objetos internos do gRPC."""

    def __init__(self, codigo: grpc.StatusCode, detalhes: str = "") -> None:
        self._codigo = codigo
        self._detalhes = detalhes

    def code(self) -> grpc.StatusCode:
        return self._codigo

    def details(self) -> str:
        return self._detalhes


def traduzir(codigo: grpc.StatusCode, detalhes: str = "", metodo: str = "ListMyFluxos"):
    return RuntimeApiClient._traduzir(FalhaFalsa(codigo, detalhes), metodo)


def test_permissao_negada_diz_ao_agente_para_nao_insistir():
    erro = traduzir(grpc.StatusCode.PERMISSION_DENIED, metodo="SendOutboundMessage")

    assert isinstance(erro, ErroDoBackend)
    texto = str(erro)
    assert "SendOutboundMessage" in texto
    # A frase que muda o comportamento do modelo.
    assert "Não tente de novo" in texto
    assert "reconectar" in texto


def test_nao_autenticado_manda_reconectar_e_nao_falar_de_permissao():
    texto = str(traduzir(grpc.StatusCode.UNAUTHENTICATED))

    assert "expirou" in texto or "revogada" in texto
    assert "reconectar" in texto
    # Não é problema de escopo: sugerir isso mandaria o agente pelo caminho errado.
    assert "permissão" not in texto.lower()


def test_nao_encontrado_ensina_a_listar_antes():
    texto = str(traduzir(grpc.StatusCode.NOT_FOUND, metodo="DesativarMyFluxo"))

    assert "não existe" in texto
    # O conselho é o que evita a próxima chamada com o mesmo id inventado.
    assert "Liste antes" in texto


def test_argumento_invalido_repassa_o_detalhe_do_backend():
    # Aqui o detalhe é validação de campo, não dado de cliente — repassá-lo é o
    # que permite ao agente corrigir a chamada.
    texto = str(traduzir(grpc.StatusCode.INVALID_ARGUMENT, "nome não pode ser vazio"))
    assert "nome não pode ser vazio" in texto


def test_erro_interno_nao_repassa_o_detalhe():
    """Detalhe de erro interno pode conter dado do sistema.

    E o agente não tem o que fazer com ele: a orientação útil é "tente de novo".
    """
    texto = str(traduzir(grpc.StatusCode.INTERNAL, "pool esgotado em pg-node-3"))

    assert "pg-node-3" not in texto
    assert "pool" not in texto
    assert "falha temporária" in texto


def test_deadline_sugere_tentar_de_novo():
    texto = str(traduzir(grpc.StatusCode.DEADLINE_EXCEEDED))
    assert "demorou demais" in texto
    assert "Tente de novo" in texto


def test_conflito_de_estado_e_distinguido_de_argumento_invalido():
    texto = str(traduzir(grpc.StatusCode.FAILED_PRECONDITION, "fluxo já inativo"))
    assert "conflita com o estado" in texto
    assert "fluxo já inativo" in texto


def test_toda_traducao_carrega_o_nome_da_operacao():
    """Sem o nome, o agente não sabe QUAL das chamadas dele falhou."""
    codigos_com_metodo = [
        grpc.StatusCode.PERMISSION_DENIED,
        grpc.StatusCode.NOT_FOUND,
        grpc.StatusCode.INVALID_ARGUMENT,
        grpc.StatusCode.FAILED_PRECONDITION,
        grpc.StatusCode.DEADLINE_EXCEEDED,
        grpc.StatusCode.INTERNAL,
    ]
    for codigo in codigos_com_metodo:
        assert "MinhaOperacao" in str(traduzir(codigo, metodo="MinhaOperacao"))


async def test_metodo_inexistente_falha_antes_de_tocar_a_rede():
    cliente = RuntimeApiClient("localhost:1")

    class StubVazio:
        pass

    cliente._stub = StubVazio()  # evita abrir canal

    with pytest.raises(ErroDoBackend, match="não existe no backend"):
        await cliente.chamar("OperacaoQueNaoExiste", object(), "token")


async def test_metadata_leva_token_interno_e_marca_a_origem():
    """Duas propriedades num teste só, porque elas vivem na mesma lista.

    O `user-agent` com prefixo `SmartCoreAssistant-MCP` é o que faz a trilha de
    auditoria distinguir ação de agente de ação humana (N13.7), e o
    `authorization` tem de levar o token INTERNO — nunca o do cliente.
    """
    capturado: dict[str, object] = {}

    class StubQueCaptura:
        async def GetMyPainel(self, requisicao, metadata=None, timeout=None):
            capturado["metadata"] = metadata
            return "ok"

    cliente = RuntimeApiClient("localhost:1")
    cliente._stub = StubQueCaptura()

    await cliente.chamar(
        "GetMyPainel", object(), "JWT-INTERNO", traceparent="00-abc-def-01"
    )

    metadata = dict(capturado["metadata"])  # type: ignore[arg-type]
    assert metadata["authorization"] == "Bearer JWT-INTERNO"
    assert metadata["user-agent"] == "SmartCoreAssistant-MCP/GetMyPainel"
    assert metadata["traceparent"] == "00-abc-def-01"


async def test_sem_traceparent_o_metadata_nao_leva_a_chave_vazia():
    capturado: dict[str, object] = {}

    class StubQueCaptura:
        async def GetMyPainel(self, requisicao, metadata=None, timeout=None):
            capturado["metadata"] = metadata
            return "ok"

    cliente = RuntimeApiClient("localhost:1")
    cliente._stub = StubQueCaptura()

    await cliente.chamar("GetMyPainel", object(), "JWT")

    assert "traceparent" not in dict(capturado["metadata"])  # type: ignore[arg-type]
