"""`TableSpec`s das entidades CORE (banco `default` da v1 — sem o problema de
DB-per-tenant): tenants, planos, assinaturas, pagamentos, usuarios, RBAC,
TenantConfig (config de IA) e CoreSettings (config global).

Ordem de execucao esperada (ver `steps/` e o README):
  1. `AUTH_USER` (usuarios precisam existir antes de `tenants_tenant.owner_id`)
  2. `TENANTS_PLAN`, `TENANTS_TENANT`, `TENANTS_SUBSCRIPTION`, `TENANTS_PAYMENTRECORD`
  3. ... (tenant apps — modulo `tenant_specs.py`, roda por fora, popula o id_map) ...
  4. `build_tenant_user_spec`/`build_tenant_invite_spec` (RBAC — depois do passo
     3 para poder remapear `flow_permissions` via id_map de FluxoAtendimento)
  5. `TENANTS_TENANTCONFIG`, `SETTINGS_MANAGER_CORESETTINGS` (credenciais)
"""

from __future__ import annotations

from typing import Any

from ..crypto import CipherManagerPy, FernetDecryptError, descriptografar_legado
from ..rbac import (
    remapear_flow_permissions,
    transformar_flow_permissions,
    transformar_module_permissions,
)
from .engine import RowContext
from .spec import ColumnSpec, FkRemap, TableSpec

# Marcador de senha inutilizavel — segue a convencao do Django (hash iniciando
# com "!" e considerado invalido/nao verificavel por `is_password_usable()`).
# O v2 usa Argon2id (`argon2::password_hash::PasswordHash::new`) — uma string
# fora do formato PHC simplesmente falha o parse e `verify_password` devolve
# `False` (ver `infrastructure_postgres/src/auth/password.rs::verify_password`
# e o teste `test_verify_invalid_hash`, que usa exatamente uma string invalida
# como esta). Login com senha antiga sempre falha "credenciais invalidas" —
# nunca um erro 500 — forcando o fluxo de redefinicao de senha pos-cutover.
PASSWORD_UNUSABLE_MARKER = "!migrated-from-v1"


def _marcador_senha_inutilizavel(_bruto: Any, _ctx: RowContext) -> str:
    return PASSWORD_UNUSABLE_MARKER


AUTH_USER = TableSpec(
    entidade="auth.user",
    v1_table="auth_user",
    v2_table="auth_user",
    scope="core",
    id_strategy="preserve",
    delta_column_v1=None,  # auth_user da v1 (Django) nao tem updated_at; sempre full load
    columns=[
        ColumnSpec("username"),
        ColumnSpec("email"),
        # NUNCA copiamos o hash PBKDF2 da v1 — decisao aprovada, ver PASSWORD_UNUSABLE_MARKER.
        #
        # `preservar_destino_quando`: se o usuario JA existe no v2 com senha
        # valida, mantem a dela. Sem isso, um superusuario criado no v2 antes da
        # carga era sobrescrito por colisao de id (a v1 tem auth_user id=1, e o
        # primeiro superusuario do v2 tambem) e o ambiente ficava SEM ACESSO
        # ADMINISTRATIVO — aconteceu de verdade no dev em 2026-07-28.
        # Senha vazia ou ja marcada como inutilizavel segue sendo sobrescrita.
        ColumnSpec(
            "password",
            v2="password_hash",
            transform=_marcador_senha_inutilizavel,
            preservar_destino_quando=(
                "{t}.password_hash IS NOT NULL AND {t}.password_hash <> '' "
                "AND {t}.password_hash NOT LIKE '!%'"
            ),
        ),
        ColumnSpec("first_name"),
        ColumnSpec("last_name"),
        ColumnSpec("is_active"),
        ColumnSpec("is_staff"),
        ColumnSpec("is_superuser"),
        ColumnSpec("last_login"),
        ColumnSpec("date_joined"),
    ],
)

TENANTS_PLAN = TableSpec(
    entidade="tenants.plan",
    v1_table="tenants_plan",
    v2_table="tenants_plan",
    scope="core",
    id_strategy="preserve",
    columns=[
        ColumnSpec("name"),
        ColumnSpec("description"),
        ColumnSpec("price"),
        ColumnSpec("max_instances"),
        ColumnSpec("max_departments"),
        ColumnSpec("active"),
        ColumnSpec("created_at"),
        # retention_days / max_storage_bytes: colunas novas na v2 (0017/0021),
        # sem equivalente na v1 — ficam NULL (= ilimitado/sem retencao forcada),
        # o mesmo comportamento conservador do default dessas colunas no v2.
    ],
)

TENANTS_TENANT = TableSpec(
    entidade="tenants.tenant",
    v1_table="tenants_tenant",
    v2_table="tenants_tenant",
    scope="core",
    id_strategy="preserve",
    pk_kind="uuid",
    delta_column_v1="updated_at",
    columns=[
        ColumnSpec("name"),
        ColumnSpec("slug"),
        ColumnSpec("api_key"),
        ColumnSpec("owner_id"),
        ColumnSpec("email"),
        ColumnSpec("phone"),
        ColumnSpec("active"),
        ColumnSpec("setup_completed"),
        ColumnSpec("onboarding_step"),
        ColumnSpec("access_code"),
        ColumnSpec("created_at"),
        ColumnSpec("updated_at"),
    ],
)

TENANTS_SUBSCRIPTION = TableSpec(
    entidade="tenants.subscription",
    v1_table="tenants_subscription",
    v2_table="tenants_subscription",
    scope="core",
    id_strategy="preserve",
    delta_column_v1="updated_at",
    columns=[
        ColumnSpec("tenant_id"),
        ColumnSpec("plan_id"),
        ColumnSpec("status"),
        ColumnSpec("current_period_start"),
        ColumnSpec("current_period_end"),
        ColumnSpec("payment_gateway"),
        ColumnSpec("external_customer_id"),
        ColumnSpec("external_subscription_id"),
        ColumnSpec("updated_at"),
    ],
)

TENANTS_PAYMENTRECORD = TableSpec(
    entidade="tenants.paymentrecord",
    v1_table="tenants_paymentrecord",
    v2_table="tenants_paymentrecord",
    scope="core",
    id_strategy="preserve",
    columns=[
        ColumnSpec("tenant_id"),
        ColumnSpec("amount"),
        ColumnSpec("payment_date"),
        ColumnSpec("payment_method"),
        ColumnSpec("period_start"),
        ColumnSpec("period_end"),
        ColumnSpec("notes"),
        ColumnSpec("recorded_by_id"),
        ColumnSpec("created_at"),
    ],
)


def _transform_module_permissions(bruto: Any, _ctx: RowContext) -> list[str]:
    # NOTA: nao sinalizamos "module_permissions nao vazio mas 0 escopos" como
    # conciliacao manual — e um caso legitimo e comum (usuario com todas as
    # acoes em False, ex.: perfil recem-criado ainda sem permissoes
    # concedidas). A amostra de hash de cada linha (ver `report.py`) ja
    # permite auditar manualmente qualquer transformacao suspeita.
    return transformar_module_permissions(bruto)


def _criar_transform_flow_permissions(tenant_id_to_slug: dict[str, str]):
    def _transform(bruto: Any, ctx: RowContext) -> list[int]:
        ids_v1 = transformar_flow_permissions(bruto)
        if not ids_v1:
            return []
        tenant_id = str(ctx.row["tenant_id"])
        tenant_slug = tenant_id_to_slug.get(tenant_id)
        if tenant_slug is None:
            ctx.stat.conciliacao_manual.append(
                f"flow_permissions: tenant_id={tenant_id} sem slug conhecido — ids preservados sem remapear"
            )
            return ids_v1
        mapa = ctx.id_map.entradas_por_entidade(tenant_slug, "operacional.fluxo_atendimento")
        remapeados, nao_encontrados = remapear_flow_permissions(ids_v1, mapa)
        if nao_encontrados:
            ctx.stat.conciliacao_manual.append(
                f"flow_permissions (tenant={tenant_slug}): fluxo ids nao encontrados no id_map, "
                f"preservados como v1: {nao_encontrados}"
            )
        return remapeados

    return _transform


def build_tenant_user_spec(tenant_id_to_slug: dict[str, str]) -> TableSpec:
    """Constroi o `TableSpec` de `tenants_tenantuser`.

    Recebe o mapa `tenant_id -> slug` (lido de `tenants_tenant` ja migrada)
    porque o remapeamento de `flow_permissions` precisa saber em qual
    namespace de tenant consultar o id_map de `FluxoAtendimento` — e o
    `id_map` e chaveado por slug (ver `id_map.py`), nao por `tenant_id`.
    IMPORTANTE: rode isto DEPOIS do step de tenant-apps (item 3), senao o
    id_map de fluxos estara vazio e todos os ids serao preservados como v1
    (sinalizados na conciliacao manual).
    """
    return TableSpec(
        entidade="tenants.tenantuser",
        v1_table="tenants_tenantuser",
        v2_table="tenants_tenantuser",
        scope="core",
        id_strategy="preserve",
        columns=[
            ColumnSpec("user_id"),
            ColumnSpec("tenant_id"),
            ColumnSpec("role"),
            ColumnSpec("module_permissions", transform=_transform_module_permissions),
            ColumnSpec(
                "flow_permissions", transform=_criar_transform_flow_permissions(tenant_id_to_slug)
            ),
            ColumnSpec("is_active"),
            ColumnSpec("created_at"),
            ColumnSpec("created_by_id"),
        ],
    )


def build_tenant_invite_spec(tenant_id_to_slug: dict[str, str]) -> TableSpec:
    """Mesma logica de `build_tenant_user_spec`, para `tenants_tenantinvite`."""
    return TableSpec(
        entidade="tenants.tenantinvite",
        v1_table="tenants_tenantinvite",
        v2_table="tenants_tenantinvite",
        scope="core",
        id_strategy="preserve",
        pk_kind="uuid",
        columns=[
            ColumnSpec("tenant_id"),
            ColumnSpec("email"),
            ColumnSpec("name"),
            ColumnSpec("role"),
            ColumnSpec("module_permissions", transform=_transform_module_permissions),
            ColumnSpec(
                "flow_permissions", transform=_criar_transform_flow_permissions(tenant_id_to_slug)
            ),
            ColumnSpec("token"),
            ColumnSpec("expires_at"),
            ColumnSpec("used"),
            ColumnSpec("created_at"),
            ColumnSpec("created_by_id"),
        ],
    )


# ---------------------------------------------------------------------------
# Credenciais (item 5 do plano): TenantConfig.api_keys e CoreSettings.value
# ---------------------------------------------------------------------------


def _criar_transform_api_keys(v1_fernet_key, v2_cipher: CipherManagerPy):
    def _transform(bruto: dict[str, Any] | None, ctx: RowContext) -> dict[str, Any]:
        if not bruto:
            return {}
        saida: dict[str, Any] = {}
        for servico, valor_fernet in bruto.items():
            if not valor_fernet:
                continue
            try:
                plaintext = descriptografar_legado(v1_fernet_key, valor_fernet)
            except FernetDecryptError:
                ctx.stat.conciliacao_manual.append(
                    f"tenants.tenantconfig: falha ao decriptar api_keys['{servico}'] "
                    f"(tenant_id={ctx.row['tenant_id']}) — chave omitida, requer nova configuracao manual"
                )
                continue
            if not plaintext:
                continue
            saida[servico] = v2_cipher.reencrypt_str(plaintext)
        return saida

    return _transform


def build_tenant_config_spec(v1_fernet_key, v2_cipher: CipherManagerPy) -> TableSpec:
    """`tenants_tenantconfig` — TenantConfig vive no banco `default` (app
    `tenants` esta em `CORE_APPS`), apesar do nome sugerir tenant-scoped.
    Upsert por `tenant_id` (natural) — o id serial proprio da v1 e irrelevante."""
    return TableSpec(
        entidade="tenants.tenantconfig",
        v1_table="tenants_tenantconfig",
        v2_table="tenants_tenantconfig",
        scope="core",
        id_strategy="natural",
        natural_conflict_cols=("tenant_id",),
        delta_column_v1="updated_at",
        columns=[
            ColumnSpec("tenant_id"),
            ColumnSpec("dados_empresa"),
            ColumnSpec("persona_bot"),
            ColumnSpec("bot_agent_name"),
            ColumnSpec("msg_fallback"),
            ColumnSpec("msg_sem_info"),
            ColumnSpec("msg_transferencia"),
            ColumnSpec("entity_types"),
            ColumnSpec("llm_class"),
            ColumnSpec("model"),
            ColumnSpec("transcription_provider"),
            ColumnSpec("transcription_model"),
            ColumnSpec("vision_provider"),
            ColumnSpec("vision_model"),
            ColumnSpec("api_keys", transform=_criar_transform_api_keys(v1_fernet_key, v2_cipher)),
            ColumnSpec("updated_at"),
            ColumnSpec("brand_name"),
            ColumnSpec("primary_color"),
            ColumnSpec("secondary_color"),
            ColumnSpec("timezone"),
            ColumnSpec("language_code"),
            # llm_temperature, embeddings_class, embeddings_model, chunk_size,
            # chunk_overlap, similarity_threshold, vector_distance_threshold:
            # colunas novas na v2 sem equivalente na v1 — ficam NULL (usa o
            # fallback global do CoreSettings, igual ao comportamento da v1
            # quando o campo do tenant esta vazio).
        ],
    )


def _criar_transform_core_settings_value(v1_fernet_key, v2_cipher: CipherManagerPy):
    def _transform(bruto: str, ctx: RowContext) -> str:
        encrypted = bool(ctx.row["encrypted"])
        if not encrypted or not bruto:
            return bruto or ""
        try:
            plaintext = descriptografar_legado(v1_fernet_key, bruto)
        except FernetDecryptError:
            ctx.stat.conciliacao_manual.append(
                f"settings_manager.coresettings: falha ao decriptar key='{ctx.row['key']}' "
                "— valor mantido como estava na v1 (provavelmente inutilizavel), requer conciliacao manual"
            )
            return bruto
        # IMPORTANTE: `settings_manager_coresettings.value` e TEXT (nao jsonb)
        # e o consumidor Rust (`infrastructure_postgres::tenants::settings::
        # load_all_settings`) espera o formato "ct_b64:nonce_b64:tag_b64"
        # (`row.value.splitn(3, ':')`) — DIFERENTE do jsonb usado por
        # `tenants_tenantconfig.api_keys` (`decrypt_from_jsonb`). Nao usar JSON aqui.
        campo = v2_cipher.encrypt(plaintext.encode())
        return f"{campo.ciphertext}:{campo.nonce}:{campo.tag}"

    return _transform


def _transform_core_settings_key(bruto: str, ctx: RowContext) -> str:
    """Normaliza a chave para MAIUSCULO — a v1 grava em minusculo.

    A v1 le as CoreSettings pela chave literal do banco (`config_loader.
    _get_core_settings`: `settings_dict[obj.key]`) e gravou tudo em minusculo
    (`openai_api_key`, `llm_class`, `model`). O consumidor v2 busca em
    MAIUSCULO: `tenants::config::carregar` faz `core.get("OPENAI_API_KEY")`,
    `core.get("LLM_CLASS")`, etc., e a migration 0009 semeia as linhas nesse
    case.

    Sem esta normalizacao o upsert por `key` nao casa com as linhas semeadas:
    o ETL INSERE 30 linhas novas em minusculo, que nenhum codigo le, e o v2
    segue rodando com os defaults da migration (`ChatOpenAI`/`gpt-4o-mini`,
    `OPENAI_API_KEY` vazia) em vez da config real da v1
    (`ChatGoogleGenerativeAI`/`gemini-2.5-flash-lite`). O sintoma seria um bot
    silenciosamente sem chave de API — nao um erro de migracao.
    """
    return (bruto or "").upper()


def build_core_settings_spec(v1_fernet_key, v2_cipher: CipherManagerPy) -> TableSpec:
    """`settings_manager_coresettings` — tabela global (sem tenant_id), upsert
    por `key` (a v2 ja semeia linhas default via migration `ON CONFLICT (key)
    DO NOTHING`; aqui fazemos `DO UPDATE` de proposito para trazer os valores
    reais configurados na v1, sobrescrevendo os defaults semeados)."""
    return TableSpec(
        entidade="settings.coresettings",
        v1_table="settings_manager_coresettings",
        v2_table="settings_manager_coresettings",
        scope="core",
        id_strategy="natural",
        natural_conflict_cols=("key",),
        delta_column_v1="updated_at",
        columns=[
            ColumnSpec("key", transform=_transform_core_settings_key),
            ColumnSpec("value", transform=_criar_transform_core_settings_value(v1_fernet_key, v2_cipher)),
            ColumnSpec("encrypted"),
            ColumnSpec("description"),
            ColumnSpec("created_at"),
            ColumnSpec("updated_at"),
        ],
    )
