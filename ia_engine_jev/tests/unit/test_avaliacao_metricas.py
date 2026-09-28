"""Métricas da avaliação J0 — contas certas antes de decidir go/no-go."""

from __future__ import annotations

from ia_engine_jev.avaliacao.metricas import Resultado, calcular, em_markdown, percentil


def _r(i: int, esperada: str, obtida: str, conf: float, **kw: object) -> Resultado:
    return Resultado(i, esperada, obtida, conf, **kw)  # type: ignore[arg-type]


def test_acuracia_calibracao_e_transferencia():
    resultados = [
        _r(
            0,
            "a",
            "a",
            0.9,
            transfere_esperado=False,
            transfere_obtido=False,
            intencoes_esperadas=frozenset({"a"}),
            intencoes_obtidas=frozenset({"a"}),
            tokens=100,
            duracao_ms=120,
        ),
        _r(
            1,
            "b",
            "a",
            0.6,
            transfere_esperado=True,
            transfere_obtido=False,
            intencoes_esperadas=frozenset({"b"}),
            intencoes_obtidas=frozenset({"a"}),
            tokens=200,
            duracao_ms=300,
        ),
        _r(
            2,
            "c",
            "c",
            0.95,
            transfere_esperado=False,
            transfere_obtido=True,
            tokens=150,
            duracao_ms=200,
        ),
        _r(3, "", "", 0.0, erro="JevIndisponivel"),
    ]
    rel = calcular(resultados)
    assert rel.total == 4 and rel.erros == 1
    assert rel.acuracia_intencao == 2 / 3
    assert rel.precisao_multi == 0.5 and rel.recall_multi == 0.5
    assert rel.falsos_negativos == (1,) and rel.falsos_positivos == (2,)
    assert rel.recall_transferencia == 0.0
    faixas = dict((f, (n, a)) for f, n, a in rel.calibracao)
    assert faixas["0.85–1.00"] == (2, 1.0)
    assert rel.tokens_por_mensagem == 150
    texto = em_markdown("pt", rel)
    assert "Acurácia da intenção principal: 66.7%" in texto


def test_percentil_e_vazio():
    assert percentil([], 0.95) == 0.0
    assert percentil([10, 20, 30, 40], 0.5) in (20.0, 30.0)
    assert calcular([]).acuracia_intencao == 0.0
