"""`TableSpec`s do modulo WhatsApp/Evolution (item 6 do plano).

Fonte v1: `evolution_sync/models.py` — `EvolutionInstance`, `EvolutionContact`,
`WhiteList` (TENANT_APPS, banco fisico por tenant). As outras DUAS fontes de
credencial Evolution citadas no plano (`operacional.Departamento.api_key` e
`operacional.AppInstance.api_key`) ja sao migradas em `tenant_specs.py`
(`DEPARTAMENTO`/`APP_INSTANCE`) SEM re-cifragem — elas nunca tiveram Fernet
na v1 e continuam em texto plano na v2 (debito tecnico documentado no README,
igual ao comportamento da v1). As tres fontes NAO sao unificadas — cada uma
mantem seu proprio call-site na v2, exatamente como orientado no plano.

`EvolutionInstance.api_key` (v1, SEM Fernet — texto plano) e re-cifrado com
o MESMO `CipherManagerPy` do item 5 antes de gravar em `whatsapp_instance`.

`whatsapp_instance.api_key` e `JSONB` (migration `0023_whatsapp_instance_
api_key_encrypted.sql`, fase N8) — o adapter Rust (`infrastructure_postgres::
integracoes::whatsapp`) agora le/escreve via `CipherManager::encrypt_to_json`/
`decrypt_json_entry`, no mesmo formato `{"ciphertext","nonce","tag"}` de
`tenants_tenantconfig.api_keys`. O transform abaixo devolve o dict Python
diretamente — o codec jsonb registrado em `db.py::conectar_v2` serializa.
"""

from __future__ import annotations

from typing import Any

from ..crypto import CipherManagerPy
from .engine import RowContext
from .spec import ColumnSpec, FkRemap, TableSpec


def _transform_provider_constante(_bruto: Any, _ctx: RowContext) -> str:
    return "evolution"


def _criar_transform_api_key(v2_cipher: CipherManagerPy):
    def _transform(bruto: str | None, _ctx: RowContext) -> dict[str, str]:
        if not bruto:
            return {}
        return v2_cipher.reencrypt_str(bruto)

    return _transform


def build_whatsapp_instance_spec(v2_cipher: CipherManagerPy) -> TableSpec:
    return TableSpec(
        entidade="whatsapp.instance",
        v1_table="evolution_sync_instance",
        v2_table="whatsapp_instance",
        scope="tenant",
        id_strategy="map",
        columns=[
            ColumnSpec("name"),
            ColumnSpec("instance_id"),
            ColumnSpec("api_key", transform=_criar_transform_api_key(v2_cipher)),
            ColumnSpec("phone_number"),
            ColumnSpec("active"),
            ColumnSpec("connection_state"),
            ColumnSpec("last_state_check"),
            ColumnSpec("media_storage_backend"),
            # provider: coluna nova na v2, sem equivalente na v1 — sempre
            # 'evolution' neste ETL (fonte "bruto" e o proprio pk, ignorado).
            ColumnSpec("id", v2="provider", transform=_transform_provider_constante),
            ColumnSpec("subscribed_events"),
            ColumnSpec("last_connection_state"),
            ColumnSpec("created_at"),
        ],
    )


# Coluna fisica no v1 e `contact_id`/`instance_id` — Django usa esse sufixo
# `_id` automaticamente para o nome fisico de campos `ForeignKey` (o
# atributo Python e `contact`/`instance`, mas a coluna no banco e `*_id`).
EVOLUTION_CONTACT = TableSpec(
    entidade="whatsapp.contact",
    v1_table="evolution_sync_contact",
    v2_table="whatsapp_contact",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="updated_at",
    fk_remaps=(
        FkRemap("contact_id", "clientes.contato", nullable=True),
        FkRemap("instance_id", "whatsapp.instance", nullable=False),
    ),
    columns=[
        ColumnSpec("contact_id"),
        ColumnSpec("instance_id"),
        ColumnSpec("jid"),
        ColumnSpec("lid"),
        ColumnSpec("addressing_mode"),
        ColumnSpec("active"),
        ColumnSpec("metadados"),
        ColumnSpec("created_at"),
        ColumnSpec("updated_at"),
    ],
)

WHITELIST = TableSpec(
    entidade="whatsapp.whitelist",
    v1_table="evolution_sync_whitelist",
    v2_table="whatsapp_whitelist",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,
    fk_remaps=(FkRemap("contact_id", "clientes.contato", nullable=True),),
    columns=[
        ColumnSpec("contact_id"),
        ColumnSpec("name"),
        ColumnSpec("phone_number"),
        ColumnSpec("active"),
        ColumnSpec("created_at"),
    ],
)
