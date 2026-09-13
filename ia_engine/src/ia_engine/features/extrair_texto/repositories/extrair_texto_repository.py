"""Repositório da feature ExtrairTextoDocumento: exceção técnica → erro."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import MediaDownloadError
from ia_engine.features.extrair_texto.domain.errors import (
    DocumentoIlegivelError,
    ExtrairTextoError,
    FormatoNaoSuportadoError,
)
from ia_engine.features.extrair_texto.domain.models import TextoExtraido
from ia_engine.features.extrair_texto.domain.parameters import (
    ExtrairTextoParameters,
)
from ia_engine.features.extrair_texto.services.leitores import (
    DocumentoIlegivelException,
    FormatoNaoSuportadoException,
)
from ia_engine.shared.media import MediaDownloadException


class ExtrairTextoRepository(
    RepositoryBase[TextoExtraido, ExtrairTextoParameters, ExtrairTextoError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: ExtrairTextoParameters
    ) -> ExtrairTextoError:
        match exception:
            case MediaDownloadException():
                return MediaDownloadError(message=str(exception))
            case FormatoNaoSuportadoException():
                return FormatoNaoSuportadoError(message=str(exception))
            case DocumentoIlegivelException():
                return DocumentoIlegivelError(message=str(exception))
            case _:
                return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")
