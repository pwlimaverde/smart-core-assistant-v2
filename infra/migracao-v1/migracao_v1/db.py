"""Conexoes: banco `default` da v1, bancos fisicos por tenant, e o v2.

A v1 e DB-per-tenant (ver `old/.../app/tenants/db_router.py`): `CORE_APPS`
(tenants, settings_manager, auth) vivem no banco `default`; `TENANT_APPS`
(clientes, atendimentos, operacional, evolution_sync, trello_sync,
treinamento, atendimento_unificado) sao roteadas em runtime para um banco
Postgres FISICO por tenant, descrito pela linha correspondente em
`tenants_tenantdatabase` (banco `default`).

Este modulo:
1. Conecta no banco `default` da v1 (`V1_DEFAULT_DATABASE_URL`).
2. Descobre a lista de tenants + suas credenciais de banco fisico
   (decriptando a senha Fernet — nunca loga o plaintext).
3. Abre uma conexao por tenant sob demanda (`abrir_conexao_tenant`).
4. Conecta no v2 (`V2_DATABASE_URL`, single-DB).
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import asyncpg

from .config import Config
from .crypto import FernetDecryptError, descriptografar_legado


async def _registrar_codec_jsonb(conn: asyncpg.Connection) -> None:
    """asyncpg NAO serializa/desserializa json/jsonb automaticamente por
    padrao (por padrao troca esses tipos como `str` bruta). O motor
    (`tables/engine.py`) e varios `TableSpec` (module_permissions,
    subscribed_events, metadados, api_keys...) leem/escrevem dict/list Python
    direto nessas colunas — sem este codec, qualquer bind de um dict/list
    para uma coluna jsonb falha em runtime com DataError."""
    for tipo in ("json", "jsonb"):
        await conn.set_type_codec(
            tipo,
            encoder=json.dumps,
            decoder=json.loads,
            schema="pg_catalog",
            format="text",
        )


@dataclass
class TenantDbConfig:
    tenant_id: str  # UUID (str) — id do Tenant no banco default (identico no v2)
    tenant_slug: str
    host: str
    port: int
    database_name: str
    username: str
    password_plaintext: str  # mantido em memoria apenas; NUNCA logar/gravar em disco
    ssl_mode: str
    connection_valid: bool

    def dsn(self) -> str:
        # Nao usar em logs — contem a senha em plaintext.
        return (
            f"postgresql://{self.username}:{self.password_plaintext}"
            f"@{self.host}:{self.port}/{self.database_name}"
        )


async def conectar_v1_default(cfg: Config) -> asyncpg.Connection:
    conn = await asyncpg.connect(cfg.v1_default_dsn)
    await _registrar_codec_jsonb(conn)
    return conn


async def conectar_v2(cfg: Config) -> asyncpg.Connection:
    conn = await asyncpg.connect(cfg.v2_dsn)
    await _registrar_codec_jsonb(conn)
    return conn


async def descobrir_tenant_databases(
    v1_default_conn: asyncpg.Connection, cfg: Config
) -> tuple[list[TenantDbConfig], list[str]]:
    """Le `tenants_tenant` JOIN `tenants_tenantdatabase` e decripta as senhas.

    Retorna `(configs_validas, avisos)` — tenants com `connection_valid=false`
    ou sem linha em `tenants_tenantdatabase` sao pulados e reportados em
    `avisos` (nao abortam a descoberta dos demais).
    """
    if cfg.v1_fernet_key is None:
        raise ValueError("V1_ENCRYPTION_KEY nao configurada — necessaria para decriptar TenantDatabase")

    linhas = await v1_default_conn.fetch(
        """
        SELECT t.id AS tenant_id, t.slug AS tenant_slug,
               td.host, td.port, td.database_name, td.username,
               td.password, td.ssl_mode, td.connection_valid
        FROM tenants_tenant t
        JOIN tenants_tenantdatabase td ON td.tenant_id = t.id
        ORDER BY t.slug
        """
    )

    configs: list[TenantDbConfig] = []
    avisos: list[str] = []
    for linha in linhas:
        if not linha["connection_valid"]:
            avisos.append(f"tenant '{linha['tenant_slug']}': connection_valid=false, pulado")
            continue
        try:
            senha = descriptografar_legado(cfg.v1_fernet_key, linha["password"])
        except FernetDecryptError:
            avisos.append(
                f"tenant '{linha['tenant_slug']}': falha ao decriptar senha do TenantDatabase "
                "(Fernet InvalidToken) — pulado, requer conciliacao manual"
            )
            continue

        configs.append(
            TenantDbConfig(
                tenant_id=str(linha["tenant_id"]),
                tenant_slug=linha["tenant_slug"],
                host=linha["host"],
                port=linha["port"],
                database_name=linha["database_name"],
                username=linha["username"],
                password_plaintext=senha,
                ssl_mode=linha["ssl_mode"],
                connection_valid=linha["connection_valid"],
            )
        )
    return configs, avisos


async def abrir_conexao_tenant(tenant_cfg: TenantDbConfig) -> asyncpg.Connection:
    """Abre uma conexao no banco fisico do tenant. O DSN carrega a senha em
    plaintext apenas em memoria — nunca e logado nem persistido."""
    ssl = "require" if tenant_cfg.ssl_mode not in ("disable", "", None) else None
    conn = await asyncpg.connect(
        host=tenant_cfg.host,
        port=tenant_cfg.port,
        database=tenant_cfg.database_name,
        user=tenant_cfg.username,
        password=tenant_cfg.password_plaintext,
        ssl=ssl,
    )
    await _registrar_codec_jsonb(conn)
    return conn
