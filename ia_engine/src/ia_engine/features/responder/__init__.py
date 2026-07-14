"""Feature Responder (RPC Responder): resposta do bot + score + transferência.

API pública da feature — o `servicer` e os testes importam daqui, inclusive
as funções puras de score/decisão (testáveis sem LLM).
"""

from ia_engine.features.responder.datasources.responder_datasource import (
    ResponderDataSource,
)
from ia_engine.features.responder.domain.errors import ResponderError
from ia_engine.features.responder.domain.models import ResponderData
from ia_engine.features.responder.domain.parameters import (
    CampoColetado,
    CampoPendente,
    ResponderParameters,
)
from ia_engine.features.responder.domain.usecases import (
    ResponderUsecase,
    calculate_embedding_similarity,
    detect_transfer_in_text,
    evaluate_triple_similarity,
    mapear_acao_para_fluxo,
    resolve_resposta,
)
from ia_engine.features.responder.repositories.responder_repository import (
    ResponderRepository,
)

__all__ = [
    "CampoColetado",
    "CampoPendente",
    "ResponderData",
    "ResponderDataSource",
    "ResponderError",
    "ResponderParameters",
    "ResponderRepository",
    "ResponderUsecase",
    "calculate_embedding_similarity",
    "detect_transfer_in_text",
    "evaluate_triple_similarity",
    "mapear_acao_para_fluxo",
    "resolve_resposta",
]
