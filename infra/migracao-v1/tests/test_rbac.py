"""Testes da transformacao RBAC: `module_permissions` aninhado (v1) -> array
de escopos `"modulo:acao"` (v2), e o remapeamento de `flow_permissions`.
"""

from __future__ import annotations

from migracao_v1.rbac import (
    montar_markdown_de_para,
    remapear_flow_permissions,
    transformar_flow_permissions,
    transformar_module_permissions,
)


class TestTransformarModulePermissions:
    def test_apenas_acoes_true_viram_escopos(self):
        entrada = {"atendimentos": {"view": True, "edit": True, "delete": False}}
        escopos = transformar_module_permissions(entrada)
        assert set(escopos) == {"atendimentos:view", "atendimentos:edit"}
        assert "atendimentos:delete" not in escopos

    def test_multiplos_modulos_geram_escopos_para_cada_um(self):
        entrada = {
            "atendimentos": {"view": True},
            "clientes": {"view": True, "edit": True},
        }
        escopos = transformar_module_permissions(entrada)
        assert set(escopos) == {"atendimentos:view", "clientes:view", "clientes:edit"}

    def test_saida_e_deterministica_ordenada_por_modulo_e_acao(self):
        entrada = {
            "zzz_modulo": {"view": True},
            "aaa_modulo": {"zebra": True, "abacate": True},
        }
        assert transformar_module_permissions(entrada) == [
            "aaa_modulo:abacate",
            "aaa_modulo:zebra",
            "zzz_modulo:view",
        ]

    def test_dict_vazio_ou_none_gera_lista_vazia(self):
        assert transformar_module_permissions({}) == []
        assert transformar_module_permissions(None) == []

    def test_valor_nao_dict_para_um_modulo_e_ignorado_sem_lancar_excecao(self):
        entrada = {"atendimentos": "nao-e-um-dict", "clientes": {"view": True}}
        assert transformar_module_permissions(entrada) == ["clientes:view"]

    def test_exemplo_do_plano_module_permissions_completo(self):
        # Exemplo do formato real da v1 (TenantUser.module_permissions).
        entrada = {
            "atendimentos": {"view": True, "edit": True, "delete": False},
            "clientes": {"view": True, "edit": False, "delete": False},
            "operacional": {"view": False, "edit": False, "delete": False},
        }
        escopos = transformar_module_permissions(entrada)
        assert set(escopos) == {"atendimentos:view", "atendimentos:edit", "clientes:view"}
        # 'operacional' nao aparece — todas as acoes sao False.
        assert not any(e.startswith("operacional:") for e in escopos)


class TestTransformarFlowPermissions:
    def test_normaliza_lista_de_ints(self):
        assert transformar_flow_permissions([1, 2, 3]) == [1, 2, 3]

    def test_converte_strings_numericas(self):
        assert transformar_flow_permissions(["1", "2"]) == [1, 2]

    def test_descarta_entradas_invalidas_silenciosamente(self):
        assert transformar_flow_permissions([1, "abc", None, 3.5, 4]) == [1, 3, 4]

    def test_lista_vazia_ou_none(self):
        assert transformar_flow_permissions([]) == []
        assert transformar_flow_permissions(None) == []


class TestRemapearFlowPermissions:
    def test_remapeia_ids_encontrados_no_mapa(self):
        remapeados, nao_encontrados = remapear_flow_permissions([10, 20], {10: 1001, 20: 1002})
        assert remapeados == [1001, 1002]
        assert nao_encontrados == []

    def test_preserva_id_v1_quando_nao_encontrado_e_sinaliza(self):
        remapeados, nao_encontrados = remapear_flow_permissions([10, 99], {10: 1001})
        assert remapeados == [1001, 99]
        assert nao_encontrados == [99]

    def test_lista_vazia_nao_gera_pendencias(self):
        remapeados, nao_encontrados = remapear_flow_permissions([], {})
        assert remapeados == []
        assert nao_encontrados == []


class TestMontarMarkdownDePara:
    def test_gera_cabecalho_com_contagem_da_amostra(self):
        md = montar_markdown_de_para(
            [
                {
                    "tenant_slug": "acme",
                    "user_id": 1,
                    "role": "admin",
                    "module_permissions_original": {"atendimentos": {"view": True}},
                    "escopos_gerados": ["atendimentos:view"],
                }
            ]
        )
        assert "Amostra de 1 usuario" in md
        assert "acme" in md
        assert "atendimentos:view" in md
        assert '"atendimentos"' in md  # original serializado em JSON na coluna de-para

    def test_lista_vazia_gera_relatorio_valido_sem_linhas_de_dados(self):
        md = montar_markdown_de_para([])
        assert "Amostra de 0 usuario" in md

    def test_escopos_vazios_aparecem_como_nenhum(self):
        md = montar_markdown_de_para(
            [
                {
                    "tenant_slug": "acme",
                    "user_id": 2,
                    "role": "viewer",
                    "module_permissions_original": {"atendimentos": {"view": False}},
                    "escopos_gerados": [],
                }
            ]
        )
        assert "(nenhum)" in md
