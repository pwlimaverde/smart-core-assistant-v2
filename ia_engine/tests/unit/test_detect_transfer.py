"""Testes do safety-net de detecção de transferência por regex."""

from __future__ import annotations

import pytest

from ia_engine.features.responder import detect_transfer_in_text

DETECTA = [
    "Vou encaminhar seu atendimento agora.",
    "Vou transferir você para o financeiro.",
    "Estou direcionando você ao setor certo.",
    "Vou te transferir para um especialista.",
    "Encaminhando você para o suporte.",
    "Transferindo seu atendimento imediatamente.",
]

NAO_DETECTA = [
    "Olá! Como posso ajudar?",
    "Seu pedido foi confirmado com sucesso.",
    "O horário de funcionamento é das 8h às 18h.",
]


@pytest.mark.parametrize("texto", DETECTA)
def test_detecta_transferencia(texto: str):
    assert detect_transfer_in_text(texto) is True


@pytest.mark.parametrize("texto", NAO_DETECTA)
def test_nao_detecta_transferencia(texto: str):
    assert detect_transfer_in_text(texto) is False
