"""Re-cifragem de credenciais: Fernet (v1) -> AES-256-GCM (v2).

Espelha exatamente duas pecas do legado/novo sistema:

1. `descriptografar_legado`: replica `tenants/utils/encryption.py::decrypt_value`
   da v1 (Django) — so tenta decriptar se o valor comeca com o prefixo padrao
   do Fernet ("gAAAA"); caso contrario devolve o valor como estava (plaintext
   historico marcado erroneamente como criptografado).

2. `CipherManagerPy`: replica `infrastructure_postgres/src/crypto.rs::CipherManager`
   (Rust) bit a bit, para que o jsonb `{"ciphertext","nonce","tag"}` gravado por
   este ETL seja decriptavel por `CipherManager::decrypt_from_jsonb` no v2 SEM
   nenhuma alteracao no codigo Rust:
   - Chave mestra: 32 bytes, decodificados de base64 **padrao** (nao urlsafe).
   - AES-256-GCM, nonce de 96 bits (12 bytes) gerado por CSPRNG, sem AAD.
   - `AESGCM.encrypt` do `cryptography` ja devolve `ciphertext || tag`
     (tag de 16 bytes no final) — exatamente o layout que o Rust produz via
     `aes_gcm::Aes256Gcm` e depois separa com `split_at(len - 16)`.

REGRA DE SEGURANCA (doc do plano, item 5): plaintext de credencial nunca é
escrito em disco nem logado — este modulo so o mantem em memoria entre o
decrypt (Fernet) e o re-encrypt (AES-GCM). Nenhuma funcao aqui usa `logging`.
"""

from __future__ import annotations

import base64
import os
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag
from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .secret import Secret

FERNET_TOKEN_PREFIX = "gAAAA"
_TAG_LEN_BYTES = 16
_NONCE_LEN_BYTES = 12


class FernetDecryptError(Exception):
    """Levantado quando um token Fernet individual falha ao decriptar.

    O chamador deve capturar por credencial/linha (nao abortar o lote todo) e
    registrar `identificador` na lista de conciliacao manual (doc do plano,
    item 5: "isola para uma lista de conciliacao manual, nao aborta o lote").
    """

    def __init__(self, identificador: str) -> None:
        self.identificador = identificador
        super().__init__(f"falha ao decriptar valor Fernet legado: {identificador}")


def descriptografar_legado(fernet_key: Secret, valor: str | None) -> str:
    """Replica `decrypt_value` da v1: so decripta se parecer um token Fernet.

    Args:
        fernet_key: chave Fernet da v1 (`ENCRYPTION_KEY` do Django), envelopada.
        valor: valor armazenado no banco v1 (pode ja estar em plaintext por
            engano historico — nesse caso e devolvido como esta, igual a v1).

    Raises:
        FernetDecryptError: quando o valor parece um token Fernet valido mas
            a decriptacao falha (chave errada, token corrompido, etc.).
    """
    if not valor or not isinstance(valor, str):
        return valor or ""

    if not valor.strip().startswith(FERNET_TOKEN_PREFIX):
        return valor

    try:
        f = Fernet(fernet_key.reveal().encode())
        return f.decrypt(valor.strip().encode()).decode()
    except (InvalidToken, ValueError) as exc:
        # identificador de diagnostico SEM conteudo do valor (nunca logar o token)
        raise FernetDecryptError(identificador=f"token_len={len(valor)}") from exc


@dataclass
class EncryptedField:
    """Estrutura persistida no jsonb v2 — espelha `CipherManager::encrypt`."""

    ciphertext: str
    nonce: str
    tag: str

    def to_jsonb(self) -> dict[str, str]:
        return {"ciphertext": self.ciphertext, "nonce": self.nonce, "tag": self.tag}


class CipherManagerPy:
    """Porta Python de `infrastructure_postgres::crypto::CipherManager`.

    Usada apenas por este ETL (nunca pelo runtime v2) para produzir o mesmo
    formato de jsonb que o adapter Rust consome via `decrypt_from_jsonb`.
    """

    def __init__(self, key: bytes) -> None:
        if len(key) != 32:
            raise ValueError("a chave mestra precisa ter exatamente 32 bytes (256 bits)")
        self._key = key

    @classmethod
    def from_base64(cls, key_b64: Secret) -> "CipherManagerPy":
        """Carrega a chave mestra a partir de uma string base64 **padrao**.

        Mesma variavel de ambiente que o Rust le: `ENCRYPTION_KEY`.
        """
        try:
            key_bytes = base64.b64decode(key_b64.reveal().strip(), validate=True)
        except Exception as exc:  # noqa: BLE001 - queremos normalizar o erro
            raise ValueError("ENCRYPTION_KEY invalida (base64)") from exc
        return cls(key_bytes)

    def encrypt(self, plaintext: bytes) -> EncryptedField:
        """Encripta `plaintext`. Nonce de 12 bytes gerado por CSPRNG a cada chamada."""
        aesgcm = AESGCM(self._key)
        nonce = os.urandom(_NONCE_LEN_BYTES)
        ct_and_tag = aesgcm.encrypt(nonce, plaintext, None)
        ciphertext, tag = (
            ct_and_tag[: -_TAG_LEN_BYTES],
            ct_and_tag[-_TAG_LEN_BYTES:],
        )
        return EncryptedField(
            ciphertext=base64.b64encode(ciphertext).decode(),
            nonce=base64.b64encode(nonce).decode(),
            tag=base64.b64encode(tag).decode(),
        )

    def decrypt(self, ciphertext_b64: str, nonce_b64: str, tag_b64: str) -> bytes:
        """Decripta a partir dos tres componentes base64 (usado so em testes)."""
        aesgcm = AESGCM(self._key)
        ct = base64.b64decode(ciphertext_b64)
        nonce = base64.b64decode(nonce_b64)
        tag = base64.b64decode(tag_b64)
        try:
            return aesgcm.decrypt(nonce, ct + tag, None)
        except InvalidTag as exc:
            raise ValueError("integridade violada ou chave invalida") from exc

    def reencrypt_str(self, plaintext: str) -> dict[str, str]:
        """Atalho: encripta uma string e devolve o dict pronto para jsonb."""
        return self.encrypt(plaintext.encode()).to_jsonb()
