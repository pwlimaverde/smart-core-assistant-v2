"""Parâmetros da feature ExtrairTextoDocumento — só dados."""

from __future__ import annotations

from dataclasses import dataclass

from py_return_success_or_error import Parameters


@dataclass(frozen=True)
class ExtrairTextoParameters(Parameters):
    """Documento sempre por URL pré-assinada, nunca binário inline."""

    url: str
    mimetype: str
    nome_arquivo: str
