"""Datasource da feature Transcribe: todo o I/O da feature.

Baixa o áudio via URL pré-assinada, delega a transcrição ao `AudioTranscriber`
construído pela fábrica e gera o resumo best-effort com o chat model. Falhas
técnicas propagam como exceção — a tradução para erro de domínio é do
`TranscribeRepository`.
"""

from __future__ import annotations

from collections.abc import Callable

import httpx
from langchain_core.language_models.chat_models import BaseChatModel
from py_return_success_or_error import DataSource

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.transcribe.domain.models import TranscricaoBruta
from ia_engine.features.transcribe.domain.parameters import (
    TranscribeParameters,
)
from ia_engine.features.transcribe.domain.services import AudioTranscriber
from ia_engine.shared.media import download_media

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]
TranscriberFactory = Callable[[LlmProviderSpec], AudioTranscriber]

_SUMMARY_FALLBACK_LEN = 200


class TranscribeDataSource(
    DataSource[TranscricaoBruta, TranscribeParameters]
):
    """Download + transcrição + resumo (best-effort)."""

    def __init__(
        self,
        *,
        transcriber_factory: TranscriberFactory,
        chat_model_factory: ChatModelFactory,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._transcriber_factory = transcriber_factory
        self._chat_model_factory = chat_model_factory
        self._http_client = http_client

    async def __call__(
        self, parameters: TranscribeParameters
    ) -> TranscricaoBruta:
        transcriber = self._transcriber_factory(
            parameters.transcription_provider
        )
        audio_bytes = await download_media(
            parameters.url, client=self._http_client
        )
        lang = (parameters.language or "pt").strip() or "pt"

        transcricao = (
            await transcriber(audio_bytes, parameters.mimetype, lang)
        ).strip()
        if not transcricao:
            # Sem texto não há o que resumir; o process decide a falha.
            return TranscricaoBruta(transcricao="", resumo="")

        summarizer = self._chat_model_factory(
            parameters.transcription_provider
        )
        resumo = await _summarize(transcricao, summarizer)
        return TranscricaoBruta(transcricao=transcricao, resumo=resumo)


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
