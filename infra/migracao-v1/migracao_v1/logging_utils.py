"""Logging estruturado por lote — sem PII em claro (doc do plano, transversal).

Cada linha de log de lote e um JSON de uma linha (`logging` padrao + um
`Formatter` custom), contendo apenas: entidade, tenant, contagens, ids
min/max, duracao e error_code. Telefones/emails, quando precisam aparecer
(ex.: um erro especifico de linha), passam por `report.mascarar_telefone`/
`mascarar_email` antes de chegar aqui. Nenhuma funcao deste modulo aceita
plaintext de credencial — isso e responsabilidade do `crypto.py`, que nunca
loga.
"""

from __future__ import annotations

import json
import logging
import sys
from typing import Any


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        extra = getattr(record, "batch_fields", None)
        if extra:
            payload.update(extra)
        return json.dumps(payload, ensure_ascii=False, default=str)


def configurar_logging(nivel: str = "INFO") -> logging.Logger:
    logger = logging.getLogger("migracao_v1")
    logger.setLevel(nivel)
    if not logger.handlers:
        handler = logging.StreamHandler(stream=sys.stdout)
        handler.setFormatter(_JsonFormatter())
        logger.addHandler(handler)
    return logger


def log_lote(
    logger: logging.Logger,
    *,
    entidade: str,
    tenant_slug: str | None,
    count: int,
    id_min: int | None,
    id_max: int | None,
    duracao_s: float,
    error_code: str | None = None,
) -> None:
    """Loga um lote processado — os unicos campos permitidos sao estes (sem PII)."""
    campos = {
        "entidade": entidade,
        "tenant_slug": tenant_slug,
        "count": count,
        "id_min": id_min,
        "id_max": id_max,
        "duracao_s": round(duracao_s, 3),
        "error_code": error_code,
    }
    nivel = logging.ERROR if error_code else logging.INFO
    logger.log(nivel, "lote processado", extra={"batch_fields": campos})
