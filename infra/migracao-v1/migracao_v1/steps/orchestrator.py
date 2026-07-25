"""Orquestracao dos steps 1-6 do plano (o step 7, midia, esta em `media.py`
por causa da dependencia opcional de `aioboto3`).

Ordem OBRIGATORIA entre os steps (dependencias de FK e de id_map):
  1. `migrar_core_basico`   — auth_user, tenants_plan, tenants_tenant,
                               tenants_subscription, tenants_paymentrecord
  2. `migrar_tenant_apps`   — operacional, clientes, atendimentos, atu_*,
                               treinamento, whatsapp (popula o id_map)
  3. `migrar_rbac`          — tenants_tenantuser, tenants_tenantinvite
                               (remapeia flow_permissions via id_map do passo 2)
  4. `migrar_credenciais`   — tenants_tenantconfig.api_keys, CoreSettings
  (5. `migrar_media`, em media.py — roda por ultimo, reescreve paths de mídia)
"""

from __future__ import annotations

import json
import logging
from datetime import datetime

from .. import db, rbac
from ..config import Config
from ..crypto import CipherManagerPy
from ..id_map import IdMap
from ..logging_utils import log_lote
from ..report import ReconciliationReport
from ..tables import core_specs, tenant_specs, whatsapp_specs
from ..tables.engine import migrate_table
from ..tables.spec import TableSpec

ENTIDADES_CORE_BASICO = [
    core_specs.AUTH_USER,
    core_specs.TENANTS_PLAN,
    core_specs.TENANTS_TENANT,
    core_specs.TENANTS_SUBSCRIPTION,
    core_specs.TENANTS_PAYMENTRECORD,
]


async def _migrar_spec_core(
    spec: TableSpec,
    v1_conn,
    v2_conn,
    *,
    cfg: Config,
    dry_run: bool,
    since: datetime | None,
    report: ReconciliationReport,
    logger: logging.Logger,
) -> None:
    stat = report.nova_entidade(spec.entidade)
    await migrate_table(
        spec,
        v1_conn,
        None if dry_run else v2_conn,
        tenant_slug=None,
        tenant_id_v2=None,
        id_map=IdMap(),  # tabelas core nao usam id_map (id_strategy != 'map')
        cfg=cfg,
        dry_run=dry_run,
        since=since,
        batch_size=cfg.batch_size,
        stat=stat,
    )
    log_lote(
        logger,
        entidade=spec.entidade,
        tenant_slug=None,
        count=stat.v1_count,
        id_min=stat.id_min_v1,
        id_max=stat.id_max_v1,
        duracao_s=stat.duracao_s,
        error_code=stat.error_code,
    )


async def migrar_core_basico(
    cfg: Config,
    *,
    dry_run: bool,
    since: datetime | None,
    report: ReconciliationReport,
    logger: logging.Logger,
    entidades_filtro: set[str] | None = None,
) -> None:
    v1_conn = await db.conectar_v1_default(cfg)
    v2_conn = await db.conectar_v2(cfg) if not dry_run else None
    try:
        for spec in ENTIDADES_CORE_BASICO:
            if entidades_filtro and spec.entidade not in entidades_filtro:
                continue
            await _migrar_spec_core(
                spec, v1_conn, v2_conn, cfg=cfg, dry_run=dry_run, since=since, report=report, logger=logger
            )
    finally:
        await v1_conn.close()
        if v2_conn is not None:
            await v2_conn.close()


async def migrar_tenant_apps(
    cfg: Config,
    *,
    dry_run: bool,
    since: datetime | None,
    id_map: IdMap,
    report: ReconciliationReport,
    logger: logging.Logger,
    only_tenant_slug: str | None = None,
    entidades_filtro: set[str] | None = None,
) -> list[str]:
    """Migra as TENANT_APPS de cada tenant descoberto via `TenantDatabase`.

    Retorna a lista de avisos de descoberta (tenants pulados por
    `connection_valid=false` ou falha de decriptacao Fernet).
    """
    v1_default_conn = await db.conectar_v1_default(cfg)
    v2_conn = await db.conectar_v2(cfg) if not dry_run else None
    v2_cipher = CipherManagerPy.from_base64(cfg.v2_encryption_key) if cfg.v2_encryption_key else None

    specs = list(tenant_specs.TENANT_APP_SPECS)
    if v2_cipher is not None:
        specs += [
            whatsapp_specs.build_whatsapp_instance_spec(v2_cipher),
            whatsapp_specs.EVOLUTION_CONTACT,
            whatsapp_specs.WHITELIST,
        ]
    else:
        logger.warning(
            "ENCRYPTION_KEY ausente — pulando migracao de whatsapp_instance/contact/whitelist "
            "(exige CipherManagerPy para re-cifrar EvolutionInstance.api_key)"
        )

    try:
        tenant_dbs, avisos = await db.descobrir_tenant_databases(v1_default_conn, cfg)
        for aviso in avisos:
            logger.warning(aviso)

        for tenant_cfg in tenant_dbs:
            if only_tenant_slug and tenant_cfg.tenant_slug != only_tenant_slug:
                continue

            tenant_conn = await db.abrir_conexao_tenant(tenant_cfg)
            try:
                for spec in specs:
                    if entidades_filtro and spec.entidade not in entidades_filtro:
                        continue
                    stat = report.nova_entidade(spec.entidade, tenant_slug=tenant_cfg.tenant_slug)
                    await migrate_table(
                        spec,
                        tenant_conn,
                        None if dry_run else v2_conn,
                        tenant_slug=tenant_cfg.tenant_slug,
                        tenant_id_v2=tenant_cfg.tenant_id,
                        id_map=id_map,
                        cfg=cfg,
                        dry_run=dry_run,
                        since=since,
                        batch_size=cfg.batch_size,
                        stat=stat,
                    )
                    log_lote(
                        logger,
                        entidade=spec.entidade,
                        tenant_slug=tenant_cfg.tenant_slug,
                        count=stat.v1_count,
                        id_min=stat.id_min_v1,
                        id_max=stat.id_max_v1,
                        duracao_s=stat.duracao_s,
                        error_code=stat.error_code,
                    )
            finally:
                await tenant_conn.close()
        return avisos
    finally:
        await v1_default_conn.close()
        if v2_conn is not None:
            await v2_conn.close()


async def migrar_rbac(
    cfg: Config,
    *,
    dry_run: bool,
    since: datetime | None,
    id_map: IdMap,
    report: ReconciliationReport,
    logger: logging.Logger,
    entidades_filtro: set[str] | None = None,
    amostra_rbac_de_para: int = 25,
) -> str:
    """Migra `tenants_tenantuser`/`tenants_tenantinvite`.

    Roda DEPOIS de `migrar_tenant_apps` — o remapeamento de `flow_permissions`
    consulta o id_map de `operacional.fluxo_atendimento` que esse step popula.

    Retorna o markdown da tabela de-para de RBAC (plano, item 2) — o chamador
    (`cli.py`) grava em `<run_dir>/rbac_de_para.md`.
    """
    v1_conn = await db.conectar_v1_default(cfg)
    v2_conn = await db.conectar_v2(cfg) if not dry_run else None
    try:
        linhas_tenant = await v1_conn.fetch("SELECT id, slug FROM tenants_tenant")
        tenant_id_to_slug = {str(r["id"]): r["slug"] for r in linhas_tenant}

        markdown_de_para = await _gerar_rbac_de_para(v1_conn, tenant_id_to_slug, amostra_rbac_de_para)

        specs = [
            core_specs.build_tenant_user_spec(tenant_id_to_slug),
            core_specs.build_tenant_invite_spec(tenant_id_to_slug),
        ]
        for spec in specs:
            if entidades_filtro and spec.entidade not in entidades_filtro:
                continue
            stat = report.nova_entidade(spec.entidade)
            await migrate_table(
                spec,
                v1_conn,
                None if dry_run else v2_conn,
                tenant_slug=None,
                tenant_id_v2=None,
                id_map=id_map,
                cfg=cfg,
                dry_run=dry_run,
                since=since,
                batch_size=cfg.batch_size,
                stat=stat,
            )
            log_lote(
                logger,
                entidade=spec.entidade,
                tenant_slug=None,
                count=stat.v1_count,
                id_min=stat.id_min_v1,
                id_max=stat.id_max_v1,
                duracao_s=stat.duracao_s,
                error_code=stat.error_code,
            )
        return markdown_de_para
    finally:
        await v1_conn.close()
        if v2_conn is not None:
            await v2_conn.close()


async def _gerar_rbac_de_para(v1_conn, tenant_id_to_slug: dict[str, str], limite: int) -> str:
    """Le uma amostra de `tenants_tenantuser` e monta o markdown de-para
    (module_permissions original x escopos v2) via `rbac.montar_markdown_de_para`."""
    linhas = await v1_conn.fetch(
        "SELECT user_id, tenant_id, role, module_permissions FROM tenants_tenantuser "
        "ORDER BY user_id LIMIT $1",
        limite,
    )
    amostras: list[rbac.AmostraDePara] = []
    for linha in linhas:
        module_permissions = linha["module_permissions"]
        if isinstance(module_permissions, str):
            module_permissions = json.loads(module_permissions) if module_permissions else {}
        amostras.append(
            {
                "tenant_slug": tenant_id_to_slug.get(str(linha["tenant_id"]), "?"),
                "user_id": linha["user_id"],
                "role": linha["role"],
                "module_permissions_original": module_permissions,
                "escopos_gerados": rbac.transformar_module_permissions(module_permissions),
            }
        )
    return rbac.montar_markdown_de_para(amostras)


async def migrar_credenciais(
    cfg: Config,
    *,
    dry_run: bool,
    since: datetime | None,
    report: ReconciliationReport,
    logger: logging.Logger,
    entidades_filtro: set[str] | None = None,
) -> None:
    """Migra `tenants_tenantconfig.api_keys` e `settings_manager_coresettings`
    (re-cifragem Fernet -> AES-256-GCM)."""
    if cfg.v1_fernet_key is None or cfg.v2_encryption_key is None:
        raise ValueError(
            "V1_ENCRYPTION_KEY e ENCRYPTION_KEY sao obrigatorias para o step de credenciais"
        )
    v2_cipher = CipherManagerPy.from_base64(cfg.v2_encryption_key)

    v1_conn = await db.conectar_v1_default(cfg)
    v2_conn = await db.conectar_v2(cfg) if not dry_run else None
    try:
        specs = [
            core_specs.build_tenant_config_spec(cfg.v1_fernet_key, v2_cipher),
            core_specs.build_core_settings_spec(cfg.v1_fernet_key, v2_cipher),
        ]
        for spec in specs:
            if entidades_filtro and spec.entidade not in entidades_filtro:
                continue
            stat = report.nova_entidade(spec.entidade)
            await migrate_table(
                spec,
                v1_conn,
                None if dry_run else v2_conn,
                tenant_slug=None,
                tenant_id_v2=None,
                id_map=IdMap(),
                cfg=cfg,
                dry_run=dry_run,
                since=since,
                batch_size=cfg.batch_size,
                stat=stat,
            )
            log_lote(
                logger,
                entidade=spec.entidade,
                tenant_slug=None,
                count=stat.v1_count,
                id_min=stat.id_min_v1,
                id_max=stat.id_max_v1,
                duracao_s=stat.duracao_s,
                error_code=stat.error_code,
            )
    finally:
        await v1_conn.close()
        if v2_conn is not None:
            await v2_conn.close()
