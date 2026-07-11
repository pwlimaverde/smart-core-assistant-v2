"""Testes do mapeamento de ação de transferência para chave de fluxo."""

from __future__ import annotations

from ia_engine.features.responder import mapear_acao_para_fluxo

FLUXOS = {
    "Financeiro - cobranças e boletos": "setor financeiro",
    "Suporte Técnico - problemas no sistema": "setor de TI",
}


def test_match_exato_por_nome_do_setor():
    assert (
        mapear_acao_para_fluxo("Financeiro", FLUXOS)
        == "Financeiro - cobranças e boletos"
    )


def test_match_substring_case_insensitive():
    assert (
        mapear_acao_para_fluxo("suporte técnico", FLUXOS)
        == "Suporte Técnico - problemas no sistema"
    )


def test_match_acao_contem_nome_setor():
    # ação mais longa que contém o nome do setor
    assert (
        mapear_acao_para_fluxo("time de Financeiro", FLUXOS)
        == "Financeiro - cobranças e boletos"
    )


def test_fallback_primeira_chave_quando_sem_correspondencia():
    assert (
        mapear_acao_para_fluxo("Departamento Inexistente", FLUXOS)
        == "Financeiro - cobranças e boletos"
    )


def test_sem_fluxos_retorna_vazio():
    assert mapear_acao_para_fluxo("Financeiro", {}) == ""
