"""Testes unitários do score triádico e da decisão de transferência.

Portam os casos da v1 (`test_features_compose.py`) e cobrem os cenários de
`should_force_transfer` descritos no contrato da feature.
"""

from __future__ import annotations

import math

import pytest

from ia_engine.domain.models import RespostaBot
from ia_engine.features.responder import (
    calculate_embedding_similarity,
    evaluate_triple_similarity,
    resolve_resposta,
)

FLUXOS = {"Financeiro - cobranças": "setor financeiro"}


# --- similaridade de cosseno (portado da v1) ------------------------------- #
def test_cosine_identical_vectors():
    assert calculate_embedding_similarity([1.0, 0.0], [1.0, 0.0]) == pytest.approx(1.0)


def test_cosine_orthogonal_vectors():
    assert calculate_embedding_similarity([1.0, 0.0], [0.0, 1.0]) == pytest.approx(0.0)


def test_cosine_dim_mismatch_raises():
    with pytest.raises(ValueError):
        calculate_embedding_similarity([1.0, 0.0], [1.0])


def test_cosine_zero_vector_raises():
    with pytest.raises(ValueError):
        calculate_embedding_similarity([0.0, 0.0], [1.0, 0.0])


# --- score triádico (portado da v1) ---------------------------------------- #
def test_triple_no_training_applies_075_sr():
    # sr = 1.0 -> 0.75 * 1.0
    score = evaluate_triple_similarity([1.0, 0.0], [1.0, 0.0], None)
    assert score == pytest.approx(0.75)


def test_triple_with_training_all_aligned():
    # sr=sq=st=1 -> base=1.0, sem penalidade
    assert evaluate_triple_similarity(
        [1.0, 0.0], [1.0, 0.0], [1.0, 0.0]
    ) == pytest.approx(1.0)


def test_triple_penalty_when_training_diverges():
    # message e response alinhados (sr=1); training ortogonal (sq=st=0).
    # base = 0.5*1 + 0.25*0 + 0.25*0 = 0.5; min_qt=0 < 0.4 ->
    # penalty = (0.4 - 0) * 0.5 = 0.2 -> 0.3
    score = evaluate_triple_similarity([1.0, 0.0], [1.0, 0.0], [0.0, 1.0])
    assert score == pytest.approx(0.3)


def test_triple_clamped_to_unit_interval():
    score = evaluate_triple_similarity([1.0, 0.0], [-1.0, 0.0], None)
    assert 0.0 <= score <= 1.0
    assert math.isclose(score, 0.0)


# --- decisão de transferência ---------------------------------------------- #
def test_score_alto_sem_transferencia():
    resposta = RespostaBot(
        resposta_texto="Tudo certo!", acao_transferencia=None, confianca=0.9
    )
    result = resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=FLUXOS,
        final_score=0.9,
        similarity_threshold=0.5,
    )
    assert result.transferir_atendimento is False
    assert result.fluxo_transferencia == ""
    assert result.confiabilidade == pytest.approx(0.9)


def test_score_baixo_confianca_baixa_forca_transferencia():
    resposta = RespostaBot(
        resposta_texto="Não sei responder.",
        acao_transferencia=None,
        confianca=0.3,
    )
    result = resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=FLUXOS,
        final_score=0.2,
        similarity_threshold=0.5,
    )
    assert result.transferir_atendimento is True
    # usa o primeiro fluxo como padrão
    assert result.fluxo_transferencia == "Financeiro - cobranças"
    # mensagem genérica de transferência é anexada
    assert "transferir seu atendimento" in result.resposta_texto.lower()


def test_score_baixo_mas_confianca_alta_nao_transfere():
    resposta = RespostaBot(
        resposta_texto="Olá! Bom dia.",
        acao_transferencia=None,
        confianca=0.95,
    )
    result = resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=FLUXOS,
        final_score=0.1,
        similarity_threshold=0.5,
    )
    assert result.transferir_atendimento is False
    assert result.resposta_texto == "Olá! Bom dia."


def test_llm_indica_transferencia_respeita_independente_do_score():
    resposta = RespostaBot(
        resposta_texto="Vou te ajudar com isso.",
        acao_transferencia="Financeiro",
        confianca=0.99,
    )
    result = resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=FLUXOS,
        final_score=0.99,
        similarity_threshold=0.5,
    )
    assert result.transferir_atendimento is True
    assert result.fluxo_transferencia == "Financeiro - cobranças"


def test_safety_net_regex_forca_transferencia_sem_acao():
    resposta = RespostaBot(
        resposta_texto="Vou transferir você para o setor responsável.",
        acao_transferencia=None,
        confianca=0.9,
    )
    result = resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=FLUXOS,
        final_score=0.9,
        similarity_threshold=0.5,
    )
    assert result.transferir_atendimento is True
    assert result.fluxo_transferencia == "Financeiro - cobranças"
