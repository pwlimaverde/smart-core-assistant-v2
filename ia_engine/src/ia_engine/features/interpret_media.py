"""Interpretação de mídia via LLM multimodal (RPC InterpretMedia).

Baixa imagem/vídeo/documento via URL pré-assinada e pede ao LLM de visão uma
análise completa (`analise`) e um resumo curto (`resumo`) — structured output.
"""

from __future__ import annotations

import base64
from typing import Any, cast

import httpx
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import HumanMessage

from ia_engine.domain.errors import InterpretMediaError
from ia_engine.domain.models import MediaAnalysis
from ia_engine.features._media import download_media

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


async def interpret_media(
    *,
    url: str,
    mimetype: str,
    media_type: str,
    vision_model: BaseChatModel,
    file_name: str = "",
    http_client: httpx.AsyncClient | None = None,
) -> MediaAnalysis:
    """Interpreta a mídia e retorna análise completa + resumo.

    Raises:
        MediaDownloadError: falha no download.
        InterpretMediaError: LLM retornou tipo inesperado ou análise vazia.
    """
    media_bytes = await download_media(url, client=http_client)
    media_b64 = base64.b64encode(media_bytes).decode("utf-8")
    resolved_mimetype = (mimetype or "").strip() or _DEFAULT_MIMETYPE.get(
        media_type, "application/octet-stream"
    )

    prompt = _PROMPTS.get(media_type, _PROMPTS["imageMessage"])
    if media_type == "documentMessage" and file_name:
        prompt = f"{prompt}\n\nNome do arquivo: {file_name}"
    prompt = f"{prompt}{_OUTPUT_INSTRUCTION}"

    content: list[Any] = [
        {"type": "text", "text": prompt},
        {
            "type": "image_url",
            "image_url": {"url": f"data:{resolved_mimetype};base64,{media_b64}"},
        },
    ]
    message = HumanMessage(content=cast(Any, content))

    structured = vision_model.with_structured_output(MediaAnalysis)
    result: Any = await structured.ainvoke([message])

    if isinstance(result, MediaAnalysis):
        analysis = result
    elif isinstance(result, dict):
        data = cast(dict[str, Any], result)
        analysis = MediaAnalysis(
            analise=str(data.get("analise", "")),
            resumo=str(data.get("resumo", "")),
        )
    else:
        raise InterpretMediaError(
            "LLM retornou tipo inesperado para a análise de mídia"
        )

    if not (analysis.analise or "").strip():
        raise InterpretMediaError("LLM retornou análise vazia para a mídia")
    return analysis
