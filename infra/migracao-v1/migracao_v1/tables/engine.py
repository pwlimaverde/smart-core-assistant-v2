"""Motor generico de migracao de uma `TableSpec`.

Este e o unico lugar onde a logica de upsert/idempotencia/dry-run/
delta/relatorio existe de fato — cada tabela e apenas dados (`TableSpec`).

NOTA IMPORTANTE (limite deste round de trabalho, ver mensagem de entrega):
este modulo fala com um banco Postgres real via `asyncpg` e por isso **nao
tem cobertura de pytest neste round** (não há infraestrutura de banco
disponivel neste ambiente). A logica pura que ele orquestra — transformacao
RBAC, re-cifragem Fernet->AES-GCM, filtro de delta — esta isolada em modulos
proprios (`rbac.py`, `crypto.py`, `delta.py`) que SAO testados. Antes do
primeiro uso real, rode este motor contra um Postgres de teste (dry-run
primeiro) e valide manualmente com o relatorio de conciliacao.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any

import asyncpg

from ..config import Config
from ..id_map import IdMap
from ..report import EntidadeStats, hash_linha
from .spec import TableSpec


@dataclass
class RowContext:
    """Contexto passado a cada `ColumnSpec.transform`."""

    tenant_slug: str | None
    tenant_id_v2: str | None
    id_map: IdMap
    cfg: Config
    row: asyncpg.Record
    """Linha bruta v1 completa — util quando um transform precisa de mais de
    uma coluna de origem (ex.: nenhum caso atual, mas mantido por flexibilidade)."""
    stat: EntidadeStats
    """Permite que um transform (ex.: re-cifragem de credenciais) registre
    itens de conciliacao manual por linha/chave (ex.: uma chave Fernet
    individual que falhou ao decriptar) sem abortar a linha inteira."""


def _montar_linha_v2(spec: TableSpec, row: asyncpg.Record, ctx: RowContext) -> dict[str, Any]:
    valores: dict[str, Any] = {}
    for col in spec.columns:
        bruto = row[col.v1]
        valores[col.nome_v2()] = col.transform(bruto, ctx) if col.transform else bruto
    if spec.scope == "tenant":
        valores["tenant_id"] = ctx.tenant_id_v2
    return valores


def _aplicar_fk_remaps(
    spec: TableSpec, valores: dict[str, Any], tenant_slug: str | None, id_map: IdMap, stat: EntidadeStats
) -> None:
    for remap in spec.fk_remaps:
        bruto = valores.get(remap.coluna_v2)
        if bruto is None:
            continue  # FK nula na origem — nada a remapear
        mapeado = id_map.get(tenant_slug or "", remap.entidade_referenciada, int(bruto))
        if mapeado is None:
            stat.conciliacao_manual.append(
                f"{spec.entidade}: FK {remap.coluna_v2}={bruto} nao encontrada no id_map de "
                f"'{remap.entidade_referenciada}' (tenant={tenant_slug}) — "
                f"{'setado NULL' if remap.nullable else 'linha mantida com id v1 original (RISCO)'}"
            )
            if not remap.nullable:
                continue  # mantem o valor v1 bruto — melhor que perder o dado, mas fica sinalizado
            valores[remap.coluna_v2] = None
        else:
            valores[remap.coluna_v2] = mapeado


def _build_select_sql(spec: TableSpec, *, tem_since: bool) -> str:
    """Monta o SELECT paginado por keyset. Parametros sempre na ordem
    `$1=last_seen, [$2=since,] $N=batch_size` — `tem_since` decide se `$2` existe.
    """
    partes = [spec.pk_v1] + [
        f"{c.v1}{c.v1_cast}" if c.v1_cast else c.v1 for c in spec.columns if c.v1 != spec.pk_v1
    ]
    # NOTA: quando `v1_cast` renomeia efetivamente a coluna no resultset (ex.:
    # `embedding::text`), o asyncpg ainda expõe o registro pelo nome original
    # da coluna (`embedding`), entao a leitura por `row[col.v1]` continua valida.
    cols_v1 = ", ".join(partes)
    sql = f"SELECT {cols_v1} FROM {spec.v1_table} WHERE {spec.pk_v1} > $1"
    limit_idx = 2
    if tem_since:
        assert spec.delta_column_v1
        sql += f" AND {spec.delta_column_v1} >= $2"
        limit_idx = 3
    sql += f" ORDER BY {spec.pk_v1} ASC LIMIT ${limit_idx}"
    return sql


async def _iter_batches(
    src_conn: asyncpg.Connection, spec: TableSpec, since: datetime | None, batch_size: int
):
    """Pagina por keyset (`pk > last_seen`) — evita `OFFSET` custoso em tabelas grandes.

    Funciona tanto para pk inteira quanto UUID (`uuid.UUID` e ordenavel em
    Python via `.int`); o sentinela inicial e o "menor valor possivel" de
    cada tipo.
    """
    tem_since = since is not None and spec.delta_column_v1 is not None
    sql = _build_select_sql(spec, tem_since=tem_since)
    last_seen: Any = uuid.UUID(int=0) if spec.pk_kind == "uuid" else 0
    while True:
        args: list[Any] = [last_seen]
        if tem_since:
            args.append(since)
        args.append(batch_size)
        linhas = await src_conn.fetch(sql, *args)
        if not linhas:
            return
        yield linhas
        last_seen = linhas[-1][spec.pk_v1]
        if len(linhas) < batch_size:
            return


def _build_upsert_sql(spec: TableSpec, colunas: list[str], *, incluir_pk: bool) -> str:
    casts = spec.v2_cast_por_coluna()
    todas = ([spec.pk_v2] if incluir_pk else []) + colunas
    placeholders = ", ".join(f"${i + 1}{casts.get(c, '')}" for i, c in enumerate(todas))
    campos = ", ".join(todas)

    if spec.id_strategy == "preserve":
        conflito = spec.pk_v2
    else:
        assert spec.natural_conflict_cols
        conflito = ", ".join(spec.natural_conflict_cols)

    sets = ", ".join(f"{c} = EXCLUDED.{c}" for c in colunas)
    return (
        f"INSERT INTO {spec.v2_table} ({campos}) VALUES ({placeholders}) "
        f"ON CONFLICT ({conflito}) DO UPDATE SET {sets} "
        f"RETURNING {spec.pk_v2}, (xmax = 0) AS inserted"
    )


async def _upsert_preserve_ou_natural(
    dst_conn: asyncpg.Connection,
    spec: TableSpec,
    id_v1: int | None,
    valores: dict[str, Any],
    stat: EntidadeStats,
) -> None:
    """`valores` contem SOMENTE as colunas de dado (nunca o pk) — o pk e
    tratado a parte para `id_strategy='preserve'` (`id_v1` vira o pk v2
    diretamente) e e omitido para `id_strategy='natural'` (`id_v1=None`,
    deixa o `SERIAL` do v2 gerar)."""
    colunas = list(valores.keys())
    incluir_pk = spec.id_strategy == "preserve"
    sql = _build_upsert_sql(spec, colunas, incluir_pk=incluir_pk)
    args = ([id_v1] if incluir_pk else []) + [valores[c] for c in colunas]
    linha = await dst_conn.fetchrow(sql, *args)
    if linha and linha["inserted"]:
        stat.v2_written_insert += 1
    else:
        stat.v2_written_update += 1


async def _upsert_map(
    dst_conn: asyncpg.Connection,
    spec: TableSpec,
    valores: dict[str, Any],
    *,
    tenant_slug: str,
    id_v1: int,
    id_map: IdMap,
    stat: EntidadeStats,
) -> None:
    id_v2_existente = id_map.get(tenant_slug, spec.entidade, id_v1)
    colunas = list(valores.keys())
    casts = spec.v2_cast_por_coluna()

    if id_v2_existente is not None:
        sets = ", ".join(f"{c} = ${i + 2}{casts.get(c, '')}" for i, c in enumerate(colunas))
        sql = f"UPDATE {spec.v2_table} SET {sets} WHERE {spec.pk_v2} = $1"
        await dst_conn.execute(sql, id_v2_existente, *[valores[c] for c in colunas])
        stat.v2_written_update += 1
        return

    placeholders = ", ".join(f"${i + 1}{casts.get(c, '')}" for i, c in enumerate(colunas))
    campos = ", ".join(colunas)
    sql = f"INSERT INTO {spec.v2_table} ({campos}) VALUES ({placeholders}) RETURNING {spec.pk_v2}"
    novo_id = await dst_conn.fetchval(sql, *[valores[c] for c in colunas])
    id_map.set(tenant_slug, spec.entidade, id_v1, novo_id)
    stat.v2_written_insert += 1


async def migrate_table(
    spec: TableSpec,
    src_conn: asyncpg.Connection,
    dst_conn: asyncpg.Connection | None,
    *,
    tenant_slug: str | None,
    tenant_id_v2: str | None,
    id_map: IdMap,
    cfg: Config,
    dry_run: bool,
    since: datetime | None,
    batch_size: int,
    stat: EntidadeStats,
) -> None:
    """Migra uma tabela inteira (todos os lotes) de `src_conn` para `dst_conn`.

    `dst_conn` pode ser `None` apenas quando `dry_run=True` (nesse caso o
    motor so conta linhas de origem, sem tentar classificar insert/update).
    """
    if spec.scope == "tenant" and (tenant_slug is None or tenant_id_v2 is None):
        raise ValueError(f"TableSpec({spec.entidade}): scope='tenant' exige tenant_slug/tenant_id_v2")
    if not dry_run and dst_conn is None:
        raise ValueError("dst_conn e obrigatorio fora de dry-run")

    inicio = time.monotonic()
    amostra_max = 5

    async for lote in _iter_batches(src_conn, spec, since, batch_size):
        for row in lote:
            id_v1 = row[spec.pk_v1]
            stat.v1_count += 1
            stat.registrar_id(id_v1)

            ctx = RowContext(
                tenant_slug=tenant_slug,
                tenant_id_v2=tenant_id_v2,
                id_map=id_map,
                cfg=cfg,
                row=row,
                stat=stat,
            )
            valores = _montar_linha_v2(spec, row, ctx)
            _aplicar_fk_remaps(spec, valores, tenant_slug, id_map, stat)

            if len(stat.amostras_hash) < amostra_max:
                stat.amostras_hash.append(
                    {"id_v1": id_v1, "hash": hash_linha(list(valores.values()))}
                )

            if dry_run:
                continue

            assert dst_conn is not None
            if spec.id_strategy in ("preserve", "natural"):
                pk_a_gravar = id_v1 if spec.id_strategy == "preserve" else None
                await _upsert_preserve_ou_natural(dst_conn, spec, pk_a_gravar, valores, stat)
            else:
                assert tenant_slug is not None
                await _upsert_map(
                    dst_conn,
                    spec,
                    valores,
                    tenant_slug=tenant_slug,
                    id_v1=id_v1,
                    id_map=id_map,
                    stat=stat,
                )

    stat.duracao_s = time.monotonic() - inicio

    if dst_conn is not None and not dry_run:
        if spec.scope == "tenant":
            stat.v2_count_after = await dst_conn.fetchval(
                f"SELECT COUNT(*) FROM {spec.v2_table} WHERE tenant_id = $1", tenant_id_v2
            )
        else:
            stat.v2_count_after = await dst_conn.fetchval(f"SELECT COUNT(*) FROM {spec.v2_table}")
