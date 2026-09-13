"""Modelos da feature ExtrairTextoDocumento."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TextoExtraido:
    """O texto lido do documento e o formato reconhecido."""

    texto: str
    formato: str
