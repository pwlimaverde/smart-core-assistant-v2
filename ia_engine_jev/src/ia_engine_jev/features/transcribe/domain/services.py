"""Contratos (ports) da feature Transcribe."""

from __future__ import annotations

from typing import Protocol


class AudioTranscriber(Protocol):
    """Contrato de um transcritor de áudio (bytes -> texto)."""

    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str: ...
