"""Testes de `report.py`: mascaramento de PII e hash de conciliacao."""

from __future__ import annotations

import json
import uuid

from migracao_v1.report import (
    EntidadeStats,
    hash_linha,
    mascarar_email,
    mascarar_telefone,
)


class TestMascararTelefone:
    def test_mascara_numero_completo_com_ddi(self):
        assert mascarar_telefone("+5511999991234") == "+55***1234"

    def test_mascara_numero_sem_prefixo_mais(self):
        assert mascarar_telefone("5511999991234") == "+55***1234"

    def test_remove_caracteres_nao_numericos_antes_de_mascarar(self):
        assert mascarar_telefone("+55 (11) 99999-1234") == "+55***1234"

    def test_valor_vazio_ou_none_devolve_string_vazia(self):
        assert mascarar_telefone(None) == ""
        assert mascarar_telefone("") == ""

    def test_numero_muito_curto_usa_fallback_com_ultimos_digitos(self):
        assert mascarar_telefone("123") == "***23"


class TestMascararEmail:
    def test_mascara_parte_local_preservando_dominio(self):
        assert mascarar_email("fulano@exemplo.com") == "f***o@exemplo.com"

    def test_local_curto_usa_fallback(self):
        assert mascarar_email("ab@exemplo.com") == "a***@exemplo.com"

    def test_valor_vazio_ou_sem_arroba_devolve_string_vazia(self):
        assert mascarar_email(None) == ""
        assert mascarar_email("") == ""
        assert mascarar_email("nao-e-email") == ""


class TestHashLinha:
    def test_mesmos_valores_geram_mesmo_hash(self):
        assert hash_linha([1, "a", True, None]) == hash_linha([1, "a", True, None])

    def test_valores_diferentes_geram_hashes_diferentes(self):
        assert hash_linha([1, "a"]) != hash_linha([1, "b"])

    def test_hash_tem_tamanho_fixo_de_16_caracteres_hex(self):
        resultado = hash_linha(["x", 1, None])
        assert len(resultado) == 16
        assert all(c in "0123456789abcdef" for c in resultado)

    def test_ordem_dos_valores_importa(self):
        assert hash_linha([1, 2]) != hash_linha([2, 1])


class TestEntidadeStats:
    def test_registrar_id_atualiza_min_e_max(self):
        stat = EntidadeStats(entidade="teste")
        stat.registrar_id(10)
        stat.registrar_id(5)
        stat.registrar_id(20)
        assert stat.id_min_v1 == 5
        assert stat.id_max_v1 == 20

    def test_to_dict_inclui_todos_os_campos_esperados(self):
        stat = EntidadeStats(entidade="teste", tenant_slug="acme")
        stat.v1_count = 3
        d = stat.to_dict()
        assert d["entidade"] == "teste"
        assert d["tenant_slug"] == "acme"
        assert d["v1_count"] == 3
        assert "amostras_hash" in d
        assert "conciliacao_manual" in d

    def test_to_dict_serializa_pk_uuid(self):
        """`tenants_tenant` tem PK UUID e `uuid.UUID` nao e' JSON-serializavel:
        o relatorio da execucao inteira estourava no fim, DEPOIS de a migracao ja
        ter escrito no banco."""
        stat = EntidadeStats(entidade="tenants.tenant")
        stat.registrar_id(uuid.UUID("f47ac10b-58cc-4372-a567-0e02b2c3d479"))

        d = stat.to_dict()

        assert d["id_min_v1"] == "f47ac10b-58cc-4372-a567-0e02b2c3d479"
        json.dumps(d)  # nao deve levantar

    def test_to_dict_mantem_pk_int_legivel(self):
        stat = EntidadeStats(entidade="teste")
        stat.registrar_id(5)
        stat.registrar_id(20)

        d = stat.to_dict()

        assert d["id_min_v1"] == "5"
        assert d["id_max_v1"] == "20"
        json.dumps(d)

    def test_to_dict_sem_ids_registrados_mantem_none(self):
        d = EntidadeStats(entidade="vazia").to_dict()

        assert d["id_min_v1"] is None
        assert d["id_max_v1"] is None
        json.dumps(d)
