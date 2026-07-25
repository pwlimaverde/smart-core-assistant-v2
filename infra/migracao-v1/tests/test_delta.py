"""Testes da logica de deteccao de delta (`--since <timestamp>`)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from migracao_v1.delta import clausula_since_sql, incluir_no_delta

T0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
ANTES = T0 - timedelta(days=1)
DEPOIS = T0 + timedelta(days=1)


class TestIncluirNoDelta:
    def test_carga_full_since_none_sempre_inclui(self):
        assert incluir_no_delta(ANTES, since=None) is True
        assert incluir_no_delta(None, since=None) is True

    def test_linha_sem_timestamp_sempre_inclui_mesmo_em_modo_delta(self):
        assert incluir_no_delta(None, since=T0) is True

    def test_timestamp_igual_ao_since_e_incluido(self):
        assert incluir_no_delta(T0, since=T0) is True

    def test_timestamp_depois_do_since_e_incluido(self):
        assert incluir_no_delta(DEPOIS, since=T0) is True

    def test_timestamp_antes_do_since_e_excluido(self):
        assert incluir_no_delta(ANTES, since=T0) is False


class TestClausulaSinceSql:
    def test_sem_coluna_de_controle_devolve_string_vazia(self):
        assert clausula_since_sql(None, indice_parametro=2) == ""

    def test_com_coluna_monta_clausula_parametrizada(self):
        assert clausula_since_sql("updated_at", indice_parametro=2) == " AND updated_at >= $2"

    def test_indice_do_parametro_e_respeitado(self):
        assert clausula_since_sql("data_atualizacao", indice_parametro=5) == (
            " AND data_atualizacao >= $5"
        )
