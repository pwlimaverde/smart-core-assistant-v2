"""Repositório da feature Transcribe: exceção técnica → erro de domínio."""

from __future__ import annotations

from py_return_success_or_error import ErrorGeneric, RepositoryBase

from ia_engine.domain.errors import MediaDownloadError, ProviderConfigError
from ia_engine.features.transcribe.domain.errors import (
    TranscribeError,
    TranscricaoIndisponivelError,
)
from ia_engine.features.transcribe.domain.models import TranscricaoBruta
from ia_engine.features.transcribe.domain.parameters import (
    TranscribeParameters,
)
from ia_engine.llm.errors import ProviderConfigException
from ia_engine.shared.media import MediaDownloadException


class TranscribeRepository(
    RepositoryBase[TranscricaoBruta, TranscribeParameters, TranscribeError]
):
    """Traduz as falhas técnicas do datasource para a união fechada."""

    def map_error(
        self, exception: Exception, parameters: TranscribeParameters
    ) -> TranscribeError:
        match exception:
            case ProviderConfigException():
                return ProviderConfigError(message=str(exception))
            case MediaDownloadException():
                return MediaDownloadError(message=str(exception))
            case NotImplementedError():
                return TranscricaoIndisponivelError(message=str(exception))
            case _:
                return ErrorGeneric(
                    message=f"{type(exception).__name__}: {exception}"
                )
