"""Feature ExtrairTextoDocumento (B9 / N10 E5): texto de documento de treinamento.

API pública da feature — o `servicer` e os testes importam daqui.
"""

from ia_engine.features.extrair_texto.datasources.extrair_texto_datasource import (
    ExtrairTextoDataSource,
)
from ia_engine.features.extrair_texto.domain.errors import (
    DocumentoIlegivelError,
    ExtrairTextoError,
    FormatoNaoSuportadoError,
    TextoVazioError,
)
from ia_engine.features.extrair_texto.domain.models import TextoExtraido
from ia_engine.features.extrair_texto.domain.parameters import (
    ExtrairTextoParameters,
)
from ia_engine.features.extrair_texto.domain.usecases import ExtrairTextoUsecase
from ia_engine.features.extrair_texto.repositories.extrair_texto_repository import (
    ExtrairTextoRepository,
)

__all__ = [
    "DocumentoIlegivelError",
    "ExtrairTextoDataSource",
    "ExtrairTextoError",
    "ExtrairTextoParameters",
    "ExtrairTextoRepository",
    "ExtrairTextoUsecase",
    "FormatoNaoSuportadoError",
    "TextoExtraido",
    "TextoVazioError",
]
