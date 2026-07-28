"""Relatorio de conciliacao por entidade (JSON + Markdown) e mascaramento de PII.

Cada execucao do CLI produz um diretorio `reports/<run_id>/` com:
- `conciliacao.json` — dados estruturados (contagens v1 x v2, amostras de hash).
- `conciliacao.md` — mesma informacao em Markdown, para revisao humana.
- `id_map.json` — snapshot do mapa de ids daquela execucao (ver `id_map.py`).
- `rbac_de_para.md` — tabela de-para de RBAC (amostra), gerada pelo step de
  usuarios (ver `tables/core_specs.py`).
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def hash_linha(valores: list[Any]) -> str:
    """Hash estavel (sha256) de um subconjunto de colunas de uma linha.

    Usado para a amostragem de conciliacao — comparar o hash da mesma linha
    lida do v1 e do v2 detecta divergencias de transformacao sem precisar
    comparar objetos completos (tipos podem diferir sutilmente: Decimal vs
    float, datetime com/sem tz, etc.).
    """
    normalizado = json.dumps(
        [str(v) if v is not None else None for v in valores],
        sort_keys=True,
        ensure_ascii=False,
        default=str,
    )
    return hashlib.sha256(normalizado.encode("utf-8")).hexdigest()[:16]


_TELEFONE_RE = re.compile(r"\D")


def mascarar_telefone(telefone: str | None) -> str:
    """`+5511999991234` -> `+55***1234` (mantem DDI e os ultimos 4 digitos)."""
    if not telefone:
        return ""
    digitos = _TELEFONE_RE.sub("", telefone)
    if len(digitos) <= 6:
        return "***" + digitos[-2:]
    return f"+{digitos[:2]}***{digitos[-4:]}"


def mascarar_email(email: str | None) -> str:
    """`fulano@exemplo.com` -> `f***o@exemplo.com`."""
    if not email or "@" not in email:
        return ""
    local, _, dominio = email.partition("@")
    if len(local) <= 2:
        return f"{local[0]}***@{dominio}"
    return f"{local[0]}***{local[-1]}@{dominio}"


@dataclass
class EntidadeStats:
    entidade: str
    tenant_slug: str | None = None
    v1_count: int = 0
    v2_written_insert: int = 0
    v2_written_update: int = 0
    v2_count_after: int | None = None
    id_min_v1: Any = None
    id_max_v1: Any = None
    duracao_s: float = 0.0
    error_code: str | None = None
    amostras_hash: list[dict[str, Any]] = field(default_factory=list)
    conciliacao_manual: list[str] = field(default_factory=list)  # ids/identificadores problematicos

    def registrar_id(self, id_v1: Any) -> None:
        """Aceita tanto `int` (SERIAL/BigAutoField) quanto `uuid.UUID` (pk das
        tabelas `tenants_*`) — ambos sao comparaveis nativamente em Python."""
        self.id_min_v1 = id_v1 if self.id_min_v1 is None else min(self.id_min_v1, id_v1)
        self.id_max_v1 = id_v1 if self.id_max_v1 is None else max(self.id_max_v1, id_v1)

    def to_dict(self) -> dict[str, Any]:
        return {
            "entidade": self.entidade,
            "tenant_slug": self.tenant_slug,
            "v1_count": self.v1_count,
            "v2_written_insert": self.v2_written_insert,
            "v2_written_update": self.v2_written_update,
            "v2_count_after": self.v2_count_after,
            # str(): a PK nem sempre e' int. `tenants_tenant` e `tenants_tenantinvite`
            # tem PK UUID (ver TableSpec.pk_kind="uuid"), e `uuid.UUID` nao e'
            # serializavel em JSON — o relatorio da execucao inteira falhava no
            # fim, DEPOIS de a migracao ja ter escrito no banco.
            "id_min_v1": None if self.id_min_v1 is None else str(self.id_min_v1),
            "id_max_v1": None if self.id_max_v1 is None else str(self.id_max_v1),
            "duracao_s": round(self.duracao_s, 3),
            "error_code": self.error_code,
            "amostras_hash": self.amostras_hash,
            "conciliacao_manual": self.conciliacao_manual,
        }


@dataclass
class ReconciliationReport:
    run_id: str
    dry_run: bool
    iniciado_em: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    stats: list[EntidadeStats] = field(default_factory=list)

    def nova_entidade(self, entidade: str, tenant_slug: str | None = None) -> EntidadeStats:
        stat = EntidadeStats(entidade=entidade, tenant_slug=tenant_slug)
        self.stats.append(stat)
        return stat

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "dry_run": self.dry_run,
            "iniciado_em": self.iniciado_em.isoformat(),
            "entidades": [s.to_dict() for s in self.stats],
        }

    def to_markdown(self) -> str:
        linhas = [
            f"# Relatorio de conciliacao — {self.run_id}",
            "",
            f"- Modo: {'DRY-RUN (nenhuma escrita)' if self.dry_run else 'EXECUCAO REAL'}",
            f"- Iniciado em: {self.iniciado_em.isoformat()}",
            "",
            "| Entidade | Tenant | v1_count | v2_insert | v2_update | v2_count_after | id_v1 min-max | duracao_s | error_code |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for s in self.stats:
            id_range = (
                f"{s.id_min_v1}-{s.id_max_v1}" if s.id_min_v1 is not None else "-"
            )
            linhas.append(
                f"| {s.entidade} | {s.tenant_slug or '-'} | {s.v1_count} | "
                f"{s.v2_written_insert} | {s.v2_written_update} | "
                f"{s.v2_count_after if s.v2_count_after is not None else '-'} | "
                f"{id_range} | {s.duracao_s:.2f} | {s.error_code or '-'} |"
            )
        for s in self.stats:
            if s.conciliacao_manual:
                linhas.append("")
                linhas.append(f"## Conciliacao manual pendente — {s.entidade} ({s.tenant_slug or '-'})")
                for item in s.conciliacao_manual:
                    linhas.append(f"- {item}")
        return "\n".join(linhas) + "\n"

    def salvar(self, diretorio: Path) -> None:
        diretorio.mkdir(parents=True, exist_ok=True)
        (diretorio / "conciliacao.json").write_text(
            json.dumps(self.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8"
        )
        (diretorio / "conciliacao.md").write_text(self.to_markdown(), encoding="utf-8")
