"""Serialização do valor do campo do cartão (motor Jev) — função pura."""

from __future__ import annotations

import pytest

from ia_engine_jev.features.responder_jev import valor_json


@pytest.mark.parametrize(
    ("valor", "esperado"),
    [
        # Milhar no padrão brasileiro: "1.500" como JSON seria 1,5.
        ("1.500", "1500"),
        ("1.500.000", "1500000"),
        ("1 500", "1500"),
        ("-2.000", "-2000"),
        ("1.500,50", "1500.5"),
        ("1.500,00", "1500"),
        ("1 500,25", "1500.25"),
    ],
)
def test_milhar_brasileiro_normalizado(valor: str, esperado: str) -> None:
    assert valor_json(valor) == esperado


@pytest.mark.parametrize(
    ("valor", "esperado"),
    [
        # Formato duvidoso não é reinterpretado.
        ("1.50", "1.50"),
        ("1,500", "1.500"),
        ("1500", "1500"),
        ("1500,5", "1500.5"),
        ("12.3456", "12.3456"),
        ("1.500 000", '"1.500 000"'),
        ("1.500.00", '"1.500.00"'),
    ],
)
def test_formato_ambiguo_nao_muda(valor: str, esperado: str) -> None:
    assert valor_json(valor) == esperado


def test_outros_tipos() -> None:
    assert valor_json(" TRUE ") == "true"
    assert valor_json("52998224725") == '"52998224725"'
    assert valor_json("São Paulo") == '"São Paulo"'
