"""Troca do token do cliente pelo JWT interno, e o cache dela.

O cache existe porque, sem ele, um agente ativo faria uma chamada HTTP ao
`control_plane` por chamada de tool — o dobro de latência em troca de nada, já que
a resposta é idêntica durante minutos.

O que os testes garantem: que ele **não** entregue credencial vencida, que **não**
cresça sem limite, e que o token do cliente não apareça em mensagem de erro.
"""

from __future__ import annotations

import time

import pytest

from mcp_server.auth.token_verifier import TokenInvalido, TrocadorDeToken


class RespostaFalsa:
    def __init__(self, status: int, corpo: dict | None = None) -> None:
        self.status_code = status
        self._corpo = corpo or {}

    def json(self) -> dict:
        return self._corpo


class ClienteHttpFalso:
    """Substitui o `httpx2.AsyncClient` usado como context manager."""

    chamadas: list[dict] = []

    def __init__(self, resposta: RespostaFalsa) -> None:
        self._resposta = resposta

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_exc) -> None:
        return None

    async def post(self, url, json=None, headers=None):
        type(self).chamadas.append({"url": url, "json": json, "headers": headers})
        return self._resposta


def instalar(monkeypatch, resposta: RespostaFalsa) -> type[ClienteHttpFalso]:
    ClienteHttpFalso.chamadas = []
    monkeypatch.setattr(
        "mcp_server.auth.token_verifier.httpx.AsyncClient",
        lambda timeout=None: ClienteHttpFalso(resposta),
    )
    return ClienteHttpFalso


async def test_troca_devolve_o_token_interno_e_manda_o_segredo_de_servico(monkeypatch):
    falso = instalar(
        monkeypatch,
        RespostaFalsa(200, {"internal_token": "JWT-INTERNO", "expires_in": 300}),
    )
    trocador = TrocadorDeToken("http://cp:8095/troca", "segredo-de-servico")

    interno = await trocador.obter("TOKEN-DO-CLIENTE", "jti-1")

    assert interno == "JWT-INTERNO"
    envio = falso.chamadas[-1]
    # O segredo identifica o PROCESSO, não um usuário.
    assert envio["headers"]["X-Servico-Secreto"] == "segredo-de-servico"
    # O token do cliente vai no corpo, para o NOSSO authorization server — que é
    # o emissor dele. Isso não é passthrough para API de terceiro.
    assert envio["json"]["access_token"] == "TOKEN-DO-CLIENTE"


async def test_segunda_chamada_com_o_mesmo_jti_usa_o_cache(monkeypatch):
    falso = instalar(
        monkeypatch, RespostaFalsa(200, {"internal_token": "JWT-1", "expires_in": 300})
    )
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    await trocador.obter("tok", "jti-1")
    await trocador.obter("tok", "jti-1")
    await trocador.obter("tok", "jti-1")

    assert len(falso.chamadas) == 1


async def test_jti_diferente_nao_reaproveita_credencial_de_outro(monkeypatch):
    """Cache por `jti` é cache por TOKEN, não por processo.

    Reaproveitar entre `jti` diferentes entregaria a credencial interna de um
    usuário a outro — o pior defeito possível neste arquivo.
    """
    falso = instalar(
        monkeypatch, RespostaFalsa(200, {"internal_token": "JWT", "expires_in": 300})
    )
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    await trocador.obter("tok-a", "jti-a")
    await trocador.obter("tok-b", "jti-b")

    assert len(falso.chamadas) == 2


async def test_credencial_perto_de_vencer_nao_e_reaproveitada(monkeypatch):
    """A margem existe para que uma chamada gRPC longa chegue válida do outro lado.

    Com `expires_in` menor que a margem, o cache guarda por poucos segundos e a
    entrada seguinte refaz a troca — em vez de entregar algo que vai expirar no
    meio do caminho.
    """
    falso = instalar(
        monkeypatch, RespostaFalsa(200, {"internal_token": "JWT", "expires_in": 10})
    )
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    await trocador.obter("tok", "jti-1")
    validade = trocador._cache["jti-1"][1]

    # 10s de vida com margem de 60s: o piso de 5s entra em ação.
    assert validade - time.time() <= 6
    assert len(falso.chamadas) == 1


async def test_recusa_do_control_plane_vira_erro_sem_o_token_na_mensagem(monkeypatch):
    instalar(monkeypatch, RespostaFalsa(401, {"error": "invalid_token"}))
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    with pytest.raises(TokenInvalido) as erro:
        await trocador.obter("TOKEN-SECRETO-DO-CLIENTE", "jti-1")

    assert "TOKEN-SECRETO" not in str(erro.value)


async def test_resposta_sem_credencial_e_recusada(monkeypatch):
    instalar(monkeypatch, RespostaFalsa(200, {"expires_in": 300}))
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    with pytest.raises(TokenInvalido, match="sem credencial"):
        await trocador.obter("tok", "jti-1")


async def test_cache_poda_entradas_vencidas_e_nao_cresce_sem_limite(monkeypatch):
    """Sem poda, o cache cresceria por `jti` — ou seja, sem teto.

    Cada renovação de access token gera um `jti` novo; um agente ativo produz
    dezenas por hora.
    """
    instalar(
        monkeypatch, RespostaFalsa(200, {"internal_token": "JWT", "expires_in": 300})
    )
    trocador = TrocadorDeToken("http://cp:8095/troca", "s")

    for i in range(20):
        await trocador.obter("tok", f"jti-{i}")
    assert len(trocador._cache) == 20

    # Envelhece tudo à força e faz uma chamada nova: a poda roda no caminho.
    for chave in list(trocador._cache):
        token, _ = trocador._cache[chave]
        trocador._cache[chave] = (token, time.time() - 1)

    await trocador.obter("tok", "jti-novo")

    assert list(trocador._cache) == ["jti-novo"]
