"""Testes de `crypto.py`: decrypt_value legado (Fernet) e re-cifragem AES-256-GCM.

O objetivo do segundo grupo de testes e validar que o JSON `{ciphertext,
nonce, tag}` produzido por `CipherManagerPy` bate EXATAMENTE com o formato
que `CipherManager::decrypt_from_jsonb` (Rust,
`infrastructure_postgres/src/crypto.rs`) espera — sem rodar o Rust, so
verificando estrutura/serializacao (base64 padrao, 3 chaves, roundtrip
decrypt->encrypt->decrypt preserva o plaintext).
"""

from __future__ import annotations

import base64

import pytest
from cryptography.fernet import Fernet

from migracao_v1.crypto import (
    CipherManagerPy,
    FernetDecryptError,
    descriptografar_legado,
)
from migracao_v1.secret import Secret

# Mesma chave de 32 bytes usada nos testes Rust de `crypto.rs`
# (`MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=` — base64 de 32 bytes válidos).
CHAVE_V2_B64 = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="


# --- descriptografar_legado (Fernet, v1) ------------------------------------


def test_descriptografar_legado_devolve_valor_original_quando_nao_e_token_fernet():
    fernet_key = Secret(Fernet.generate_key().decode())
    assert descriptografar_legado(fernet_key, "plaintext-historico") == "plaintext-historico"


def test_descriptografar_legado_devolve_vazio_para_valor_none_ou_vazio():
    fernet_key = Secret(Fernet.generate_key().decode())
    assert descriptografar_legado(fernet_key, None) == ""
    assert descriptografar_legado(fernet_key, "") == ""


def test_descriptografar_legado_decripta_token_fernet_valido():
    chave = Fernet.generate_key()
    fernet_key = Secret(chave.decode())
    token = Fernet(chave).encrypt(b"minha-api-key-secreta").decode()
    assert token.startswith("gAAAA")

    assert descriptografar_legado(fernet_key, token) == "minha-api-key-secreta"


def test_descriptografar_legado_levanta_erro_customizado_em_token_invalido():
    chave_certa = Fernet.generate_key()
    chave_errada = Fernet.generate_key()
    fernet_key_errada = Secret(chave_errada.decode())
    token = Fernet(chave_certa).encrypt(b"segredo").decode()

    with pytest.raises(FernetDecryptError):
        descriptografar_legado(fernet_key_errada, token)


def test_descriptografar_legado_erro_nao_expoe_o_valor_no_identificador():
    chave_certa = Fernet.generate_key()
    chave_errada = Fernet.generate_key()
    token = Fernet(chave_certa).encrypt(b"nao-deve-vazar-isto").decode()

    with pytest.raises(FernetDecryptError) as exc_info:
        descriptografar_legado(Secret(chave_errada.decode()), token)

    assert "nao-deve-vazar-isto" not in str(exc_info.value)
    assert "nao-deve-vazar-isto" not in repr(exc_info.value.identificador)


# --- CipherManagerPy (AES-256-GCM, v2) --------------------------------------


def test_cipher_manager_py_carrega_chave_de_32_bytes_a_partir_do_base64():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    assert len(cipher._key) == 32  # noqa: SLF001 - teste de invariante interna


def test_cipher_manager_py_rejeita_chave_com_tamanho_invalido():
    chave_curta_b64 = base64.b64encode(b"0" * 16).decode()
    with pytest.raises(ValueError, match="32 bytes"):
        CipherManagerPy.from_base64(Secret(chave_curta_b64))


def test_cipher_manager_py_rejeita_base64_invalido():
    with pytest.raises(ValueError, match="ENCRYPTION_KEY invalida"):
        CipherManagerPy.from_base64(Secret("nao-e-base64-valido!!!"))


def test_encrypt_produz_estrutura_esperada_pelo_decrypt_from_jsonb_do_rust():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    campo = cipher.encrypt(b"sk-live-123456789")

    # As 3 chaves exatas que `CipherManager::decrypt_from_jsonb` le via
    # `entry.get("ciphertext")`/`"nonce"`/`"tag"`.
    d = campo.to_jsonb()
    assert set(d.keys()) == {"ciphertext", "nonce", "tag"}

    # Todos os campos sao base64 PADRAO valido (nao urlsafe) e nao-vazios.
    for chave in ("ciphertext", "nonce", "tag"):
        valor = d[chave]
        assert valor, f"{chave} nao deveria ser vazio"
        base64.b64decode(valor, validate=True)  # levanta se nao for base64 padrao valido

    # Nonce tem 12 bytes (96 bits) e tag tem 16 bytes — mesmos tamanhos do Rust.
    assert len(base64.b64decode(d["nonce"])) == 12
    assert len(base64.b64decode(d["tag"])) == 16


def test_encrypt_gera_nonce_aleatorio_a_cada_chamada():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    c1 = cipher.encrypt(b"mesmo-plaintext")
    c2 = cipher.encrypt(b"mesmo-plaintext")
    assert c1.nonce != c2.nonce
    assert c1.ciphertext != c2.ciphertext  # AES-GCM: nonce diferente -> ciphertext diferente


def test_roundtrip_encrypt_decrypt_preserva_o_plaintext():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    original = "Texto ultra secreto de teste! áéíóú"
    campo = cipher.encrypt(original.encode())
    decriptado = cipher.decrypt(campo.ciphertext, campo.nonce, campo.tag)
    assert decriptado.decode() == original


def test_decrypt_falha_com_tag_adulterada():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    campo = cipher.encrypt(b"mensagem secreta")
    tag_bytes = bytearray(base64.b64decode(campo.tag))
    tag_bytes[0] ^= 0xFF
    tag_adulterada = base64.b64encode(bytes(tag_bytes)).decode()

    with pytest.raises(ValueError, match="integridade violada"):
        cipher.decrypt(campo.ciphertext, campo.nonce, tag_adulterada)


def test_reencrypt_str_e_um_atalho_para_encrypt_mais_to_jsonb():
    cipher = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    d = cipher.reencrypt_str("minha-chave-de-api")
    assert set(d.keys()) == {"ciphertext", "nonce", "tag"}
    bytes_decriptados = cipher.decrypt(d["ciphertext"], d["nonce"], d["tag"])
    assert bytes_decriptados.decode() == "minha-chave-de-api"


def test_fluxo_completo_fernet_para_aesgcm_preserva_o_segredo():
    """Simula o fluxo real do ETL: Fernet(v1).decrypt -> CipherManagerPy(v2).encrypt."""
    chave_fernet = Fernet.generate_key()
    token_v1 = Fernet(chave_fernet).encrypt(b"groq-api-key-real-do-cliente").decode()

    plaintext = descriptografar_legado(Secret(chave_fernet.decode()), token_v1)
    assert plaintext == "groq-api-key-real-do-cliente"

    cipher_v2 = CipherManagerPy.from_base64(Secret(CHAVE_V2_B64))
    jsonb = cipher_v2.reencrypt_str(plaintext)

    # O que o adapter Rust faria ao ler de volta (decrypt_from_jsonb):
    recuperado = cipher_v2.decrypt(jsonb["ciphertext"], jsonb["nonce"], jsonb["tag"]).decode()
    assert recuperado == "groq-api-key-real-do-cliente"
