"""Modelos internos da feature Responder."""

from __future__ import annotations

from dataclasses import dataclass

from ia_engine.domain.models import RespostaBot


@dataclass(frozen=True)
class ResponderData:
    """Dado bruto do datasource: structured output + vetores para o score."""

    resposta: RespostaBot
    message_vec: tuple[float, ...]
    response_vec: tuple[float, ...]
    training_vec: tuple[float, ...] | None
