"""Transcrição de áudio (RPC Transcribe).

Baixa o áudio via URL pré-assinada e delega a transcrição a um `AudioTranscriber`
injetado. A chamada real ao provedor de transcrição (Whisper/Groq/etc.) fica
pendente de integração com uma lib específica de áudio — LangChain 1.x não expõe
transcrição de áudio de forma unificada. A INTERFACE (assinatura, contrato de
erro/degradação) está completa e o resumo já usa o chat model do request.
"""

from __future__ import annotations

from typing import Protocol

import httpx
from langchain_core.language_models.chat_models import BaseChatModel

from ia_engine.domain.errors import TranscribeError
from ia_engine.domain.models import MediaAnalysis
from ia_engine.features._media import download_media

_SUMMARY_FALLBACK_LEN = 200


class AudioTranscriber(Protocol):
    """Contrato de um transcritor de áudio (bytes -> texto)."""

    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str: ...


class PendingTranscriber:
    """Transcritor padrão (produção): integração real ainda pendente.

    Mantém a assinatura de `AudioTranscriber`; falha de forma clara até que a
    lib de transcrição de áudio seja plugada. Nos testes, injeta-se um fake.
    """

    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str:
        raise TranscribeError(
            "transcrição de áudio pendente de integração com provedor "
            "(whisper/groq); injete um AudioTranscriber concreto"
        )


async def transcribe(
    *,
    url: str,
    mimetype: str,
    language: str,
    transcriber: AudioTranscriber,
    summarizer_model: BaseChatModel,
    http_client: httpx.AsyncClient | None = None,
) -> MediaAnalysis:
    """Transcreve o áudio e gera um resumo curto.

    Retorna ``MediaAnalysis`` com ``analise`` = transcrição literal e
    ``resumo`` = resumo curto (1-3 frases).

    Raises:
        MediaDownloadError: falha no download.
        TranscribeError: transcrição vazia ou falha do transcritor.
    """
    audio_bytes = await download_media(url, client=http_client)
    lang = (language or "pt").strip() or "pt"

    transcricao = (await transcriber(audio_bytes, mimetype, lang)).strip()
    if not transcricao:
        raise TranscribeError("transcrição retornou texto vazio")

    resumo = await _summarize(transcricao, summarizer_model)
    return MediaAnalysis(analise=transcricao, resumo=resumo)


async def _summarize(transcricao: str, model: BaseChatModel) -> str:
    """Resume a transcrição via chat model; degrada para recorte em falha."""
    prompt = (
        "Resuma em português, em 1 a 3 frases, o conteúdo do áudio transcrito "
        "abaixo. Responda apenas com o resumo.\n\n"
        f"Transcrição:\n{transcricao}"
    )
    try:
        response = await model.ainvoke(prompt)
        content = getattr(response, "content", response)
        resumo = (content if isinstance(content, str) else str(content)).strip()
        return resumo or _fallback_resumo(transcricao)
    except Exception:  # noqa: BLE001 — resumo nunca quebra o fluxo principal
        return _fallback_resumo(transcricao)


def _fallback_resumo(text: str) -> str:
    text = text.strip()
    if len(text) <= _SUMMARY_FALLBACK_LEN:
        return text
    return text[: _SUMMARY_FALLBACK_LEN - 3].rstrip() + "..."
