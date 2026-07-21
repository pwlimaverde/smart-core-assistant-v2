"""Feature Transcribe (RPC Transcribe): transcrição de áudio + resumo.

API pública da feature — o `servicer` e os testes importam daqui.
"""

from ia_engine.features.transcribe.datasources.transcribe_datasource import (
    TranscribeDataSource,
)
from ia_engine.features.transcribe.domain.errors import (
    TranscribeError,
    TranscricaoIndisponivelError,
    TranscricaoVaziaError,
)
from ia_engine.features.transcribe.domain.parameters import (
    TranscribeParameters,
)
from ia_engine.features.transcribe.domain.services import AudioTranscriber
from ia_engine.features.transcribe.domain.usecases import TranscribeUsecase
from ia_engine.features.transcribe.repositories.transcribe_repository import (
    TranscribeRepository,
)
from ia_engine.features.transcribe.services.api_transcriber import (
    ApiTranscriber,
    TranscriberAttempt,
    build_transcriber,
)

__all__ = [
    "ApiTranscriber",
    "AudioTranscriber",
    "TranscribeDataSource",
    "TranscribeError",
    "TranscribeParameters",
    "TranscribeRepository",
    "TranscribeUsecase",
    "TranscriberAttempt",
    "TranscricaoIndisponivelError",
    "TranscricaoVaziaError",
    "build_transcriber",
]
