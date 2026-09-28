"""Feature Sentimento (RPC Sentimento): avaliação do atendimento."""

from ia_engine_jev.features.sentimento.datasources.sentimento_datasource import (
    SentimentoDataSource,
)
from ia_engine_jev.features.sentimento.domain.errors import SentimentoError
from ia_engine_jev.features.sentimento.domain.parameters import (
    SentimentoParameters,
)
from ia_engine_jev.features.sentimento.domain.usecases import SentimentoUsecase
from ia_engine_jev.features.sentimento.repositories.sentimento_repository import (
    SentimentoRepository,
)

__all__ = [
    "SentimentoDataSource",
    "SentimentoError",
    "SentimentoParameters",
    "SentimentoRepository",
    "SentimentoUsecase",
]
