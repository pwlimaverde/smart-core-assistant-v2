"""Datasource da feature ExtrairTextoDocumento: todo o I/O da feature.

Baixa o documento pela URL pré-assinada e o lê com `services.leitores`. Falhas
técnicas propagam como exceção — a tradução para erro de domínio é do
`ExtrairTextoRepository`.
"""

from __future__ import annotations

import httpx
from py_return_success_or_error import DataSource

from ia_engine.features.extrair_texto.domain.models import TextoExtraido
from ia_engine.features.extrair_texto.domain.parameters import (
    ExtrairTextoParameters,
)
from ia_engine.features.extrair_texto.services.leitores import extrair
from ia_engine.shared.media import download_media


class ExtrairTextoDataSource(DataSource[TextoExtraido, ExtrairTextoParameters]):
    """Download + leitura do documento."""

    def __init__(self, *, http_client: httpx.AsyncClient | None = None) -> None:
        self._http_client = http_client

    async def __call__(self, parameters: ExtrairTextoParameters) -> TextoExtraido:
        conteudo = await download_media(parameters.url, client=self._http_client)
        texto, formato = extrair(conteudo, parameters.mimetype, parameters.nome_arquivo)
        return TextoExtraido(texto=texto, formato=formato)
