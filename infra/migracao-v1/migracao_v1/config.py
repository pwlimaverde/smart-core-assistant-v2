"""Configuracao via variaveis de ambiente.

Nenhum default de producao e embutido aqui — todas as credenciais sao
obrigatorias e lidas do ambiente. Os campos sensiveis (`Secret`) nunca sao
expostos por `repr()`/log (ver `secret.py`).

Variaveis reconhecidas:
- ``V1_DEFAULT_DATABASE_URL`` (obrigatoria p/ steps core): DSN Postgres do
  banco ``default`` da v1 (tenants, planos, usuarios, TenantDatabase).
- ``V1_ENCRYPTION_KEY`` (obrigatoria p/ step 5): chave Fernet da v1
  (``settings.ENCRYPTION_KEY`` do Django).
- ``V2_DATABASE_URL`` (obrigatoria): DSN Postgres do v2 (single-DB).
- ``ENCRYPTION_KEY`` (obrigatoria p/ step 5/6): mesma variavel que o Rust
  ``CipherManager::new_from_env`` le — chave mestra AES-256-GCM em base64
  padrao (32 bytes decodificados).
- ``V1_MEDIA_ROOT`` (obrigatoria p/ step 7): diretorio local do
  ``MEDIA_ROOT`` da v1.
- ``S3_ENDPOINT`` / ``S3_REGION`` / ``S3_ACCESS_KEY_ID`` /
  ``S3_SECRET_ACCESS_KEY`` / ``S3_BUCKET`` / ``S3_FORCE_PATH_STYLE``
  (obrigatorias p/ step 7): mesmas variaveis que
  ``infrastructure_storage::connection::S3Config::from_env`` le no v2.
- ``MIGRACAO_STATE_DIR`` (opcional, default ``./migracao_v1_state``): onde o
  ``id_map.json`` "vivo" e persistido entre execucoes.
- ``MIGRACAO_REPORTS_DIR`` (opcional, default ``./reports``): onde os
  relatorios versionados por execucao sao gravados.
- ``MIGRACAO_BATCH_SIZE`` (opcional, default ``500``).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .secret import Secret


class ConfigError(Exception):
    pass


def _obrigatoria(nome: str) -> str:
    valor = os.environ.get(nome)
    if not valor:
        raise ConfigError(f"variavel de ambiente obrigatoria ausente: {nome}")
    return valor


def _opcional(nome: str, default: str) -> str:
    return os.environ.get(nome, default)


@dataclass
class S3Settings:
    endpoint: str
    region: str
    access_key_id: str
    secret_access_key: Secret
    bucket: str
    force_path_style: bool

    @classmethod
    def from_env(cls) -> "S3Settings":
        return cls(
            endpoint=_obrigatoria("S3_ENDPOINT"),
            region=_opcional("S3_REGION", "auto"),
            access_key_id=_obrigatoria("S3_ACCESS_KEY_ID"),
            secret_access_key=Secret(_obrigatoria("S3_SECRET_ACCESS_KEY")),
            bucket=_obrigatoria("S3_BUCKET"),
            force_path_style=_opcional("S3_FORCE_PATH_STYLE", "true").lower() == "true",
        )


@dataclass
class Config:
    v1_default_dsn: str
    v2_dsn: str
    v1_fernet_key: Secret | None
    v2_encryption_key: Secret | None
    v1_media_root: Path | None
    state_dir: Path
    reports_dir: Path
    batch_size: int

    @classmethod
    def from_env(cls, *, require_crypto: bool = False, require_media: bool = False) -> "Config":
        v1_fernet_key = os.environ.get("V1_ENCRYPTION_KEY")
        v2_encryption_key = os.environ.get("ENCRYPTION_KEY")
        if require_crypto:
            if not v1_fernet_key:
                raise ConfigError("variavel de ambiente obrigatoria ausente: V1_ENCRYPTION_KEY")
            if not v2_encryption_key:
                raise ConfigError("variavel de ambiente obrigatoria ausente: ENCRYPTION_KEY")

        v1_media_root_str = os.environ.get("V1_MEDIA_ROOT")
        if require_media and not v1_media_root_str:
            raise ConfigError("variavel de ambiente obrigatoria ausente: V1_MEDIA_ROOT")

        return cls(
            v1_default_dsn=_obrigatoria("V1_DEFAULT_DATABASE_URL"),
            v2_dsn=_obrigatoria("V2_DATABASE_URL"),
            v1_fernet_key=Secret(v1_fernet_key) if v1_fernet_key else None,
            v2_encryption_key=Secret(v2_encryption_key) if v2_encryption_key else None,
            v1_media_root=Path(v1_media_root_str) if v1_media_root_str else None,
            state_dir=Path(_opcional("MIGRACAO_STATE_DIR", "./migracao_v1_state")),
            reports_dir=Path(_opcional("MIGRACAO_REPORTS_DIR", "./reports")),
            batch_size=int(_opcional("MIGRACAO_BATCH_SIZE", "500")),
        )
