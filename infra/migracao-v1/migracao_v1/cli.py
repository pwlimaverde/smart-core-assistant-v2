"""CLI: `python -m migracao_v1 [opcoes]` (ou `migracao-v1` apos `pip install`).

Exemplos:
    # Carga completa, so relatando o que faria (nao escreve nada):
    python -m migracao_v1 --dry-run

    # Carga completa real, todos os steps exceto midia:
    python -m migracao_v1

    # So a entidade de tenants, execucao real:
    python -m migracao_v1 --entidade tenants.tenant

    # Delta desde um checkpoint (janela de cutover reduzida):
    python -m migracao_v1 --since 2026-07-01T00:00:00+00:00

    # Um unico tenant (util para testar antes do cutover em massa):
    python -m migracao_v1 --tenant acme

    # Incluir o step de midia (exige V1_MEDIA_ROOT + S3_* + `pip install -e ".[storage]"`):
    python -m migracao_v1 --steps core,tenant_apps,rbac,credenciais,media
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from datetime import datetime, timezone

from . import db
from .config import Config, ConfigError
from .id_map import IdMap
from .logging_utils import configurar_logging
from .report import ReconciliationReport
from .steps import media as media_step
from .steps import orchestrator

STEPS_DISPONIVEIS = ["core", "tenant_apps", "rbac", "credenciais", "media"]
STEPS_DEFAULT = ["core", "tenant_apps", "rbac", "credenciais"]  # midia fica de fora por padrao (deps extra)


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="migracao_v1",
        description="ETL de migracao v1 (Django, DB-per-tenant) -> v2 (Rust, single-DB + RLS).",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Nao escreve nada no v2 — so relata contagens/amostras do que seria migrado.",
    )
    p.add_argument(
        "--entidade",
        action="append",
        default=None,
        metavar="NOME",
        help=(
            "Filtra por entidade (ex.: 'tenants.tenant', 'clientes.contato'). "
            "Repetivel. Sem esta flag, migra TODAS as entidades dos steps selecionados."
        ),
    )
    p.add_argument(
        "--steps",
        default=",".join(STEPS_DEFAULT),
        help=f"Lista separada por virgula dos steps a rodar. Disponiveis: {', '.join(STEPS_DISPONIVEIS)}.",
    )
    p.add_argument(
        "--since",
        default=None,
        metavar="ISO_TIMESTAMP",
        help="Modo delta: migra so linhas com updated_at/data_atualizacao >= este timestamp (ISO 8601).",
    )
    p.add_argument(
        "--tenant",
        default=None,
        metavar="SLUG",
        help="Restringe os steps tenant-scoped (tenant_apps/media) a um unico tenant (por slug).",
    )
    p.add_argument(
        "--nivel-log",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
    )
    return p.parse_args(argv)


def _parse_since(valor: str | None) -> datetime | None:
    if not valor:
        return None
    dt = datetime.fromisoformat(valor)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


async def _registrar_audit_log(cfg: Config, *, event: str, message: str, context: dict) -> None:
    """`migracao.iniciada`/`migracao.concluida` no audit_log global (via v2_dsn,
    que deve apontar para uma role admin/BYPASSRLS — evento sem tenant_id, ação
    de sistema). Best-effort: nao aborta o ETL se a escrita de auditoria falhar
    (ex.: `audit_log` ainda nao migrada no ambiente-alvo) — so loga o aviso.
    Nao chamado em --dry-run (nenhuma escrita no v2 durante dry-run, por design)."""
    try:
        conn = await db.conectar_v2(cfg)
    except Exception:  # noqa: BLE001 - best-effort, nao pode quebrar o ETL
        logging.getLogger("migracao_v1").warning(
            f"audit_log: falha ao conectar para registrar evento '{event}' — pulado"
        )
        return
    try:
        await conn.execute(
            "INSERT INTO audit_log (tenant_id, service, event, message, context) "
            "VALUES (NULL, 'migracao_v1', $1, $2, $3)",
            event,
            message,
            context,
        )
    except Exception as exc:  # noqa: BLE001 - best-effort, nao pode quebrar o ETL
        logging.getLogger("migracao_v1").warning(f"audit_log: falha ao registrar evento '{event}': {exc}")
    finally:
        await conn.close()


async def _run(args: argparse.Namespace) -> int:
    logger = configurar_logging(args.nivel_log)
    steps_selecionados = [s.strip() for s in args.steps.split(",") if s.strip()]
    for s in steps_selecionados:
        if s not in STEPS_DISPONIVEIS:
            logger.error(f"step desconhecido: {s} (disponiveis: {STEPS_DISPONIVEIS})")
            return 2

    entidades_filtro = set(args.entidade) if args.entidade else None
    since = _parse_since(args.since)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ("-dryrun" if args.dry_run else "")

    try:
        precisa_cripto = "credenciais" in steps_selecionados or "tenant_apps" in steps_selecionados
        precisa_midia = "media" in steps_selecionados
        cfg = Config.from_env(require_crypto=precisa_cripto, require_media=precisa_midia)
    except ConfigError as exc:
        logger.error(str(exc))
        return 2

    report = ReconciliationReport(run_id=run_id, dry_run=args.dry_run)
    id_map = IdMap.load(cfg.state_dir / "id_map.json")
    rbac_de_para_md: str | None = None

    if not args.dry_run:
        await _registrar_audit_log(
            cfg,
            event="migracao.iniciada",
            message=f"ETL v1->v2 iniciado (run_id={run_id})",
            context={"run_id": run_id, "steps": steps_selecionados, "since": args.since},
        )

    try:
        if "core" in steps_selecionados:
            await orchestrator.migrar_core_basico(
                cfg, dry_run=args.dry_run, since=since, report=report, logger=logger,
                entidades_filtro=entidades_filtro,
            )

        if "tenant_apps" in steps_selecionados:
            await orchestrator.migrar_tenant_apps(
                cfg, dry_run=args.dry_run, since=since, id_map=id_map, report=report, logger=logger,
                only_tenant_slug=args.tenant, entidades_filtro=entidades_filtro,
            )

        if "rbac" in steps_selecionados:
            rbac_de_para_md = await orchestrator.migrar_rbac(
                cfg, dry_run=args.dry_run, since=since, id_map=id_map, report=report, logger=logger,
                entidades_filtro=entidades_filtro,
            )

        if "credenciais" in steps_selecionados:
            await orchestrator.migrar_credenciais(
                cfg, dry_run=args.dry_run, since=since, report=report, logger=logger,
                entidades_filtro=entidades_filtro,
            )

        if "media" in steps_selecionados:
            await media_step.migrar_midia_mensagens(
                cfg, dry_run=args.dry_run, id_map=id_map, report=report, logger=logger,
                only_tenant_slug=args.tenant,
            )
    finally:
        if not args.dry_run and id_map.sujo:
            id_map.save(cfg.state_dir / "id_map.json")

        run_dir = cfg.reports_dir / run_id
        report.salvar(run_dir)
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / "id_map.json").write_text(
            json.dumps(id_map.to_dict(), indent=2, sort_keys=True), encoding="utf-8"
        )
        if rbac_de_para_md is not None:
            (run_dir / "rbac_de_para.md").write_text(rbac_de_para_md, encoding="utf-8")
        logger.info(f"relatorio salvo em {run_dir.resolve()}")

    algum_erro = any(s.error_code for s in report.stats)
    if not args.dry_run:
        await _registrar_audit_log(
            cfg,
            event="migracao.concluida",
            message=f"ETL v1->v2 concluido (run_id={run_id}, erro={algum_erro})",
            context={
                "run_id": run_id,
                "steps": steps_selecionados,
                "entidades": [
                    {
                        "entidade": s.entidade,
                        "v1_count": s.v1_count,
                        "v2_written_insert": s.v2_written_insert,
                        "v2_written_update": s.v2_written_update,
                        "error_code": s.error_code,
                    }
                    for s in report.stats
                ],
            },
        )
    return 1 if algum_erro else 0


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    codigo = asyncio.run(_run(args))
    sys.exit(codigo)


if __name__ == "__main__":
    main()
