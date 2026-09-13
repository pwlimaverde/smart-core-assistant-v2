"""União fechada de erros da feature ExtrairTextoDocumento (B9 / N10 E5)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import final

from py_return_success_or_error import AppError, ErrorGeneric

from ia_engine.domain.errors import MediaDownloadError


@final
@dataclass(frozen=True)
class FormatoNaoSuportadoError(AppError):
    """O arquivo não é de um formato que sabemos ler."""


@final
@dataclass(frozen=True)
class DocumentoIlegivelError(AppError):
    """Arquivo corrompido ou protegido por senha."""


@final
@dataclass(frozen=True)
class TextoVazioError(AppError):
    """O arquivo foi lido e não tinha texto (ex.: PDF só com imagens)."""


type ExtrairTextoError = (
    MediaDownloadError
    | FormatoNaoSuportadoError
    | DocumentoIlegivelError
    | TextoVazioError
    | ErrorGeneric
)
