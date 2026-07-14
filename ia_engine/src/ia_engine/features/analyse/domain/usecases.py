"""Usecase da feature Analyse: converte o structured output em domínio."""

from __future__ import annotations

from typing import Any

from py_return_success_or_error import (
    ErrorGeneric,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)
from pydantic import BaseModel

from ia_engine.domain.errors import LlmRespostaInvalidaError
from ia_engine.domain.models import (
    EntidadeItem,
    IntentItem,
    IntentsEntidades,
)
from ia_engine.features.analyse.domain.errors import AnalyseError
from ia_engine.features.analyse.domain.parameters import AnalyseParameters


class AnalyseUsecase(
    UsecaseBaseCallData[
        IntentsEntidades, Any, AnalyseParameters, AnalyseError
    ]
):
    """FETCH (LLM com schema dinâmico) → PROCESS (parse para o domínio)."""

    def process(
        self, data: Any, parameters: AnalyseParameters
    ) -> ReturnSuccessOrError[IntentsEntidades, AnalyseError]:
        if isinstance(data, BaseModel):
            raw: dict[str, Any] = data.model_dump()
        elif isinstance(data, dict):
            raw = data
        else:
            return self.fail(
                LlmRespostaInvalidaError(
                    message="LLM retornou tipo inesperado na análise prévia"
                )
            )

        intents = [
            IntentItem(
                tipo=str(i.get("tipo", "")),
                confianca=float(i.get("confianca", 1.0)),
            )
            for i in raw.get("intents", [])
            if str(i.get("tipo", "")).strip()
        ]
        entidades = [
            EntidadeItem(
                tipo=str(e.get("tipo", "")),
                valor=str(e.get("valor", "")),
                confianca=float(e.get("confianca", 1.0)),
            )
            for e in raw.get("entidades", [])
            if str(e.get("tipo", "")).strip()
        ]
        return self.ok(
            IntentsEntidades(intents=intents, entidades=entidades)
        )

    def on_unexpected(self, exception: Exception) -> AnalyseError:
        return ErrorGeneric(
            message=f"{type(exception).__name__}: {exception}"
        )
