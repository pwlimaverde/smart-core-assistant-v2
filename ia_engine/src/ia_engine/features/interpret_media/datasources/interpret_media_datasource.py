"""Datasource da feature InterpretMedia: download + LLM multimodal.

Baixa imagem/vídeo/documento via URL pré-assinada e pede ao LLM de visão o
structured output `MediaAnalysis`. Devolve o resultado BRUTO do LLM — a
validação/conversão é regra do usecase.
"""

from __future__ import annotations

import base64
from collections.abc import Callable
from typing import Any, cast

import httpx
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import HumanMessage
from py_return_success_or_error import DataSource

from ia_engine.domain.models import LlmProviderSpec, MediaAnalysis
from ia_engine.features.interpret_media.domain.parameters import (
    InterpretMediaParameters,
)
from ia_engine.shared.media import download_media

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]

_OUTPUT_INSTRUCTION = (
    "\n\nResponda em português com DOIS campos: 'analise' = a descrição/conteúdo "
    "completo e detalhado pedido acima (contexto interno); e 'resumo' = um "
    "resumo geral curto (1 a 3 frases) do que se trata a mídia, para exibir a "
    "um atendente."
)

_PROMPTS: dict[str, str] = {
    "imageMessage": (
        "Descreva detalhadamente o conteúdo desta imagem em português. Foque "
        "nos elementos principais, textos visíveis, objetos, pessoas e contexto "
        "geral. Se houver texto legível na imagem, transcreva-o."
    ),
    "videoMessage": (
        "Descreva detalhadamente o conteúdo deste vídeo em português. Inclua as "
        "principais cenas, ações, diálogos (se houver áudio), textos visíveis e "
        "o contexto geral."
    ),
    "documentMessage": (
        "Extraia e organize todo o conteúdo textual deste documento em "
        "português. Mantenha a estrutura original (títulos, listas, tabelas) "
        "quando possível. Se estiver em outro idioma, traduza para português."
    ),
}

_DEFAULT_MIMETYPE: dict[str, str] = {
    "imageMessage": "image/jpeg",
    "videoMessage": "video/mp4",
    "documentMessage": "application/pdf",
}


class InterpretMediaDataSource(
    DataSource[Any, InterpretMediaParameters]
):
    """Download da mídia + chamada multimodal com structured output."""

    def __init__(
        self,
        *,
        chat_model_factory: ChatModelFactory,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._chat_model_factory = chat_model_factory
        self._http_client = http_client

    async def __call__(
        self, parameters: InterpretMediaParameters
    ) -> Any:
        vision_model = self._chat_model_factory(parameters.vision_provider)
        media_bytes = await download_media(
            parameters.url, client=self._http_client
        )
        media_b64 = base64.b64encode(media_bytes).decode("utf-8")
        resolved_mimetype = (
            parameters.mimetype or ""
        ).strip() or _DEFAULT_MIMETYPE.get(
            parameters.media_type, "application/octet-stream"
        )

        prompt = _PROMPTS.get(parameters.media_type, _PROMPTS["imageMessage"])
        if parameters.media_type == "documentMessage" and parameters.file_name:
            prompt = f"{prompt}\n\nNome do arquivo: {parameters.file_name}"
        prompt = f"{prompt}{_OUTPUT_INSTRUCTION}"

        content: list[Any] = [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:{resolved_mimetype};base64,{media_b64}"
                },
            },
        ]
        message = HumanMessage(content=cast(Any, content))

        structured = vision_model.with_structured_output(MediaAnalysis)
        return await structured.ainvoke([message])
