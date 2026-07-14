"""Modelos internos da feature Transcribe."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TranscricaoBruta:
    """Dado bruto do datasource: transcrição literal + resumo best-effort.

    Quando a transcrição vem vazia, o datasource devolve ambos vazios e o
    `process` decide a falha de domínio (`TranscricaoVaziaError`).
    """

    transcricao: str
    resumo: str
