"""Cliente TypeSafe: conversão de/para o SDK, erros e fábrica — sem rede."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

import httpx2
import pytest
from typesafe_sdk import (
    Choice,
    Noul,
    Score,
    TypeSafeAPIConnectionError,
    TypeSafeAuthenticationError,
    TypeSafeRateLimitError,
    TypeSafeUnprocessableEntityError,
)

from ia_engine_jev.typesafe import (
    FabricaJev,
    JevChaveInvalida,
    JevIndisponivel,
    JevLimite,
    JevNaoConfigurado,
    JevPerguntaInvalida,
    PerguntaChoice,
    PerguntaNoul,
    PerguntaScore,
    TypeSafeJev,
)
from ia_engine_jev.typesafe.cliente import de_sdk, para_sdk, traduzir_erro


def test_para_sdk():
    c = para_sdk(PerguntaChoice("qual?", {"a": None, "b": "desc"}))
    assert isinstance(c, Choice) and dict(c.criteria) == {"a": None, "b": "desc"}
    n = para_sdk(PerguntaNoul("é?", sim="sim", nao=["não"]))
    assert isinstance(n, Noul) and n.criteria is not None
    assert para_sdk(PerguntaNoul("é?")).criteria is None
    s = para_sdk(PerguntaScore("quanto?", ("baixo", "alto")))
    assert isinstance(s, Score) and list(s.criteria) == ["baixo", "alto"]


def test_de_sdk():
    bruto = SimpleNamespace(
        choices={
            "c": SimpleNamespace(choice="a", confidence=0.8, probabilities={"a": 0.8})
        },
        nouls={"n": SimpleNamespace(noul=0.3)},
        scores={
            "s": SimpleNamespace(
                score=1.2, confidence=0.7, probabilities={1: 0.6, 2: 0.4}
            )
        },
        usage=SimpleNamespace(input_tokens=None),
        model="jev-1.13.0",
    )
    r = de_sdk(bruto, 42)
    assert r.escolha("c").escolha == "a"
    assert r.noul("n") == 0.3 and r.noul("x", 0.5) == 0.5
    assert r.nivel("s").mais_provavel() == 1
    assert r.tokens_entrada == 0 and r.duracao_ms == 42 and r.modelo == "jev-1.13.0"


def _erro(cls: type, status: int) -> Any:
    return cls(status, {"message": "texto do cliente ecoado"}, httpx2.Headers({}))


def test_traduzir_erro_sem_carregar_a_mensagem():
    assert isinstance(
        traduzir_erro(_erro(TypeSafeAuthenticationError, 401)), JevChaveInvalida
    )
    assert isinstance(
        traduzir_erro(_erro(TypeSafeUnprocessableEntityError, 422)), JevPerguntaInvalida
    )
    assert isinstance(traduzir_erro(_erro(TypeSafeRateLimitError, 429)), JevLimite)
    erro = traduzir_erro(TypeSafeAPIConnectionError("rede"))
    assert isinstance(erro, JevIndisponivel)
    assert "ecoado" not in str(traduzir_erro(_erro(TypeSafeAuthenticationError, 401)))


def test_fabrica_reaproveita_por_chave_e_recusa_vazia():
    fabrica = FabricaJev()
    with pytest.raises(JevNaoConfigurado):
        fabrica("  ", "jev-1.13.0")
    a = fabrica("ts-chave-1", "jev-1.13.0")
    assert fabrica("ts-chave-1", "jev-1.13.0") is a
    assert fabrica("ts-chave-2", "jev-1.13.0") is not a
    assert fabrica("ts-chave-1", "") is fabrica("ts-chave-1", "jev-1.13.0")


async def test_perguntar_converte_e_traduz(monkeypatch: pytest.MonkeyPatch):
    cliente = TypeSafeJev("ts-chave", "jev-1.13.0")
    bruto = SimpleNamespace(
        choices={},
        nouls={"n": SimpleNamespace(noul=0.9)},
        scores={},
        usage=SimpleNamespace(input_tokens=12),
        model="jev-1.13.0",
    )

    async def ok(**_kw: Any) -> Any:
        return bruto

    monkeypatch.setattr(cliente._cliente, "system_one", ok)
    r = await cliente.perguntar(
        "analise", {"mensagem": "oi"}, {"n": PerguntaNoul("é?")}
    )
    assert r.noul("n") == 0.9 and r.tokens_entrada == 12

    async def falha(**_kw: Any) -> Any:
        raise _erro(TypeSafeRateLimitError, 429)

    monkeypatch.setattr(cliente._cliente, "system_one", falha)
    with pytest.raises(JevLimite):
        await cliente.perguntar(
            "analise", {"mensagem": "oi"}, {"n": PerguntaNoul("é?")}
        )


async def test_erro_do_jev_nao_leva_mensagem_nem_chave_ao_log(
    monkeypatch: pytest.MonkeyPatch,
):
    import loguru

    chave = "ts-chave-sentinela-123"
    texto = "meu cpf e 123.456.789-00"
    cliente = TypeSafeJev(chave, "jev-1.13.0")

    async def falha(**_kw: Any) -> Any:
        # O corpo do erro ecoa o `state` — é o que não pode vazar.
        raise TypeSafeAuthenticationError(
            401, {"message": texto, "key": chave}, httpx2.Headers({})
        )

    monkeypatch.setattr(cliente._cliente, "system_one", falha)
    capturado: list[str] = []
    sink = loguru.logger.add(lambda m: capturado.append(str(m)), level="DEBUG")
    try:
        with pytest.raises(JevChaveInvalida) as exc:
            await cliente.perguntar(
                "antes", {"mensagem": texto}, {"n": PerguntaNoul("é?")}
            )
    finally:
        loguru.logger.remove(sink)
    assert capturado, "o erro deveria ter sido logado"
    assert all(texto not in linha and chave not in linha for linha in capturado)
    assert texto not in str(exc.value) and chave not in str(exc.value)


async def test_falha_fora_do_sdk_vira_indisponivel(monkeypatch: pytest.MonkeyPatch):
    cliente = TypeSafeJev("ts-chave", "jev-1.13.0")

    async def quebra(**_kw: Any) -> Any:
        raise RuntimeError("detalhe de terceiro com dado do cliente")

    monkeypatch.setattr(cliente._cliente, "system_one", quebra)
    with pytest.raises(JevIndisponivel) as exc:
        await cliente.perguntar("antes", {}, {"n": PerguntaNoul("é?")})
    assert "detalhe" not in str(exc.value)


def test_motivo_da_metrica_sem_nome_de_regra():
    from ia_engine_jev.telemetry import motivo_da_metrica

    assert motivo_da_metrica("regra:Fechar pedido") == "regra"
    assert motivo_da_metrica("duvida:regra:Fechar pedido") == "duvida_regra"
    assert motivo_da_metrica("duvida:pede_humano") == "duvida_pede_humano"
    assert motivo_da_metrica("irritacao") == "irritacao"
    assert motivo_da_metrica("") == "desconhecido"
