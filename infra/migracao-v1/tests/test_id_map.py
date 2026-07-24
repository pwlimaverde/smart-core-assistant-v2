"""Testes do mapa de correspondencia id_v1 -> id_v2 (`id_map.py`)."""

from __future__ import annotations

from pathlib import Path

from migracao_v1.id_map import IdMap


def test_get_devolve_none_quando_nao_existe():
    m = IdMap()
    assert m.get("acme", "clientes.contato", 42) is None


def test_set_e_get_roundtrip():
    m = IdMap()
    m.set("acme", "clientes.contato", 42, 1001)
    assert m.get("acme", "clientes.contato", 42) == 1001


def test_chaves_diferentes_nao_colidem_entre_tenants():
    m = IdMap()
    m.set("acme", "clientes.contato", 1, 100)
    m.set("globex", "clientes.contato", 1, 999)  # mesmo id_v1, tenant diferente
    assert m.get("acme", "clientes.contato", 1) == 100
    assert m.get("globex", "clientes.contato", 1) == 999


def test_chaves_diferentes_nao_colidem_entre_entidades():
    m = IdMap()
    m.set("acme", "clientes.contato", 1, 100)
    m.set("acme", "clientes.cliente", 1, 200)
    assert m.get("acme", "clientes.contato", 1) == 100
    assert m.get("acme", "clientes.cliente", 1) == 200


def test_sujo_marca_alteracoes_pendentes():
    m = IdMap()
    assert m.sujo is False
    m.set("acme", "clientes.contato", 1, 100)
    assert m.sujo is True


def test_set_com_mesmo_valor_nao_marca_sujo_novamente():
    m = IdMap()
    m.set("acme", "clientes.contato", 1, 100)
    m.sujo = False
    m.set("acme", "clientes.contato", 1, 100)  # idempotente
    assert m.sujo is False


def test_entradas_por_entidade_filtra_por_tenant_e_entidade():
    m = IdMap()
    m.set("acme", "operacional.fluxo_atendimento", 1, 10)
    m.set("acme", "operacional.fluxo_atendimento", 2, 20)
    m.set("acme", "operacional.departamento", 1, 999)  # entidade diferente, nao deve aparecer
    m.set("globex", "operacional.fluxo_atendimento", 1, 555)  # tenant diferente

    resultado = m.entradas_por_entidade("acme", "operacional.fluxo_atendimento")
    assert resultado == {1: 10, 2: 20}


def test_save_e_load_roundtrip(tmp_path: Path):
    caminho = tmp_path / "id_map.json"
    m1 = IdMap()
    m1.set("acme", "clientes.contato", 1, 100)
    m1.set("acme", "clientes.cliente", 5, 500)
    m1.save(caminho)
    assert m1.sujo is False

    m2 = IdMap.load(caminho)
    assert m2.get("acme", "clientes.contato", 1) == 100
    assert m2.get("acme", "clientes.cliente", 5) == 500
    assert len(m2) == 2


def test_load_de_arquivo_inexistente_devolve_mapa_vazio(tmp_path: Path):
    m = IdMap.load(tmp_path / "nao-existe.json")
    assert len(m) == 0


def test_save_cria_diretorios_intermediarios(tmp_path: Path):
    caminho = tmp_path / "sub" / "dir" / "id_map.json"
    m = IdMap()
    m.set("acme", "clientes.contato", 1, 100)
    m.save(caminho)
    assert caminho.exists()
