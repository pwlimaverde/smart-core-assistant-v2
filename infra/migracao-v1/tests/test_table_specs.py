"""Testes de `tables/spec.py` (validacao declarativa) e sanity-check de que
TODAS as `TableSpec`s reais do projeto (core/tenant/whatsapp) se constroem
sem violar os invariantes do motor (ver `TableSpec.__post_init__`).

Estes testes NAO tocam banco — so validam a construcao dos objetos Python.
"""

from __future__ import annotations

import pytest

from migracao_v1.crypto import CipherManagerPy
from migracao_v1.secret import Secret
from migracao_v1.tables import core_specs, tenant_specs, whatsapp_specs
from migracao_v1.tables.engine import _build_setval_sql
from migracao_v1.tables.spec import ColumnSpec, TableSpec

CHAVE_V2_B64 = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="


class TestValidacaoTableSpec:
    def test_coluna_colidindo_com_pk_v2_levanta_erro(self):
        with pytest.raises(ValueError, match="colide com pk_v2"):
            TableSpec(
                entidade="teste",
                v1_table="t1",
                v2_table="t2",
                scope="core",
                id_strategy="preserve",
                columns=[ColumnSpec("id")],
            )

    def test_natural_sem_conflict_cols_levanta_erro(self):
        with pytest.raises(ValueError, match="natural_conflict_cols"):
            TableSpec(
                entidade="teste",
                v1_table="t1",
                v2_table="t2",
                scope="core",
                id_strategy="natural",
                columns=[],
            )

    def test_tenant_scope_com_preserve_levanta_erro(self):
        with pytest.raises(ValueError, match="preserve"):
            TableSpec(
                entidade="teste",
                v1_table="t1",
                v2_table="t2",
                scope="tenant",
                id_strategy="preserve",
                columns=[],
            )

    def test_tenant_scope_com_map_e_permitido(self):
        spec = TableSpec(
            entidade="teste",
            v1_table="t1",
            v2_table="t2",
            scope="tenant",
            id_strategy="map",
            columns=[ColumnSpec("nome")],
        )
        assert spec.entidade == "teste"

    def test_v2_cast_por_coluna_so_inclui_colunas_com_cast(self):
        spec = TableSpec(
            entidade="teste",
            v1_table="t1",
            v2_table="t2",
            scope="tenant",
            id_strategy="map",
            columns=[
                ColumnSpec("nome"),
                ColumnSpec("embedding", v1_cast="::text", v2_cast="::vector"),
            ],
        )
        assert spec.v2_cast_por_coluna() == {"embedding": "::vector"}


class TestEntidadesUnicasNoProjeto:
    """Cada `entidade` e usada como chave do id_map e do relatorio — nomes
    duplicados entre `TableSpec`s diferentes causariam colisao silenciosa."""

    def test_entidades_tenant_apps_sao_unicas(self):
        entidades = [s.entidade for s in tenant_specs.TENANT_APP_SPECS]
        assert len(entidades) == len(set(entidades))

    def test_entidades_core_basico_sao_unicas(self):
        entidades = [
            core_specs.AUTH_USER.entidade,
            core_specs.TENANTS_PLAN.entidade,
            core_specs.TENANTS_TENANT.entidade,
            core_specs.TENANTS_SUBSCRIPTION.entidade,
            core_specs.TENANTS_PAYMENTRECORD.entidade,
        ]
        assert len(entidades) == len(set(entidades))


class TestConstrucaoDasSpecsReais:
    """Todas as specs "de fabrica" (que dependem de chaves/mapas em runtime)
    devem se construir sem erro com entradas minimas plausiveis."""

    def test_specs_core_estaticas_ja_construidas_no_import_sao_validas(self):
        for spec in [
            core_specs.AUTH_USER,
            core_specs.TENANTS_PLAN,
            core_specs.TENANTS_TENANT,
            core_specs.TENANTS_SUBSCRIPTION,
            core_specs.TENANTS_PAYMENTRECORD,
        ]:
            assert isinstance(spec, TableSpec)
            assert spec.scope == "core"

    def test_build_tenant_user_spec_com_mapa_vazio(self):
        spec = core_specs.build_tenant_user_spec({})
        assert spec.entidade == "tenants.tenantuser"

    def test_build_tenant_invite_spec_com_mapa_vazio(self):
        spec = core_specs.build_tenant_invite_spec({})
        assert spec.entidade == "tenants.tenantinvite"
        assert spec.pk_kind == "uuid"

    def test_build_tenant_config_e_core_settings_specs(self):
        cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
        fernet_key = Secret("chave-fernet-fake")
        spec1 = core_specs.build_tenant_config_spec(fernet_key, cipher)
        spec2 = core_specs.build_core_settings_spec(fernet_key, cipher)
        assert spec1.natural_conflict_cols == ("tenant_id",)
        assert spec2.natural_conflict_cols == ("key",)

    def test_core_settings_normaliza_a_key_para_maiusculo(self):
        """A v1 grava as chaves em minusculo e o consumidor Rust le em
        MAIUSCULO (`core.get("OPENAI_API_KEY")`), que e o case semeado pela
        migration 0009. Sem esta normalizacao o upsert por `key` nao casa com
        as linhas semeadas: o ETL insere linhas minusculas que ninguem le e o
        v2 segue com os defaults (`ChatOpenAI`/`gpt-4o-mini`, chave vazia) em
        vez da config real da v1 — bot sem chave, sem erro de migracao."""
        cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
        spec = core_specs.build_core_settings_spec(Secret("chave-fernet-fake"), cipher)

        coluna_key = next(c for c in spec.columns if c.v1 == "key")
        assert coluna_key.transform is not None, "a coluna `key` precisa normalizar o case"

        for v1_key, esperado in [
            ("openai_api_key", "OPENAI_API_KEY"),
            ("llm_class", "LLM_CLASS"),
            ("vector_distance_threshold", "VECTOR_DISTANCE_THRESHOLD"),
            ("MODEL", "MODEL"),  # ja maiusculo: idempotente
        ]:
            assert coluna_key.transform(v1_key, None) == esperado

    def test_tenant_app_specs_tem_a_ordem_de_dependencia_esperada(self):
        ordem = [s.entidade for s in tenant_specs.TENANT_APP_SPECS]
        # departamento antes de fluxo antes de etapa antes de atendente
        assert ordem.index("operacional.departamento") < ordem.index("operacional.fluxo_atendimento")
        assert ordem.index("operacional.fluxo_atendimento") < ordem.index("operacional.etapa_fluxo")
        assert ordem.index("operacional.etapa_fluxo") < ordem.index("operacional.atendente")
        # contato antes de atendimento antes de mensagem
        assert ordem.index("clientes.contato") < ordem.index("atendimentos.atendimento")
        assert ordem.index("atendimentos.atendimento") < ordem.index("atendimentos.mensagem")
        # treinamento antes de documento
        assert ordem.index("treinamento.treinamento") < ordem.index("treinamento.documento")

    def test_build_whatsapp_instance_spec(self):
        cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
        spec = whatsapp_specs.build_whatsapp_instance_spec(cipher)
        assert spec.v2_table == "whatsapp_instance"
        assert spec.scope == "tenant"


class TestRessincronizacaoDeSequence:
    """`id_strategy='preserve'` grava a PK explicitamente e por isso NAO avanca a
    sequence do SERIAL — sem o `setval` de fechamento, o primeiro INSERT normal do
    v2 pos-cutover reusaria um id ja migrado (`duplicate key`)."""

    def test_setval_usa_max_mais_um_com_is_called_false(self):
        sql = _build_setval_sql("public.auth_user_id_seq", core_specs.AUTH_USER)
        assert "setval('public.auth_user_id_seq'" in sql
        assert "COALESCE((SELECT MAX(id) FROM auth_user), 0) + 1" in sql
        # is_called=false => o proximo nextval devolve exatamente esse valor
        # (cobre tabela vazia -> 1 e tabela carregada -> MAX+1 com a mesma formula)
        assert sql.rstrip(")").endswith("false")

    def test_setval_respeita_pk_v2_customizada(self):
        spec = TableSpec(
            entidade="teste",
            v1_table="t1",
            v2_table="t2",
            scope="core",
            id_strategy="preserve",
            pk_v2="codigo",
            columns=[ColumnSpec("nome")],
        )
        sql = _build_setval_sql("t2_codigo_seq", spec)
        assert "MAX(codigo) FROM t2" in sql

    def test_todas_as_specs_preserve_de_core_tem_pk_int_ou_uuid_conhecida(self):
        # A ressincronizacao e ignorada quando `pg_get_serial_sequence` devolve
        # NULL (PK UUID). Este teste documenta quais specs dependem do setval.
        preserve_int = [
            s
            for s in (
                core_specs.AUTH_USER,
                core_specs.TENANTS_PLAN,
                core_specs.TENANTS_TENANT,
                core_specs.TENANTS_SUBSCRIPTION,
                core_specs.TENANTS_PAYMENTRECORD,
            )
            if s.id_strategy == "preserve" and s.pk_kind == "int"
        ]
        assert {s.v2_table for s in preserve_int} == {
            "auth_user",
            "tenants_plan",
            "tenants_subscription",
            "tenants_paymentrecord",
        }
