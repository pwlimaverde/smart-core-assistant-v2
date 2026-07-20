"""Testes do datasource da feature InterpretMedia — montagem do prompt.

Cobre o ramo `documentMessage` com `file_name` preenchido (o nome do
arquivo é anexado ao prompt) — mock só na fronteira externa (chat model e
download de mídia).
"""

from __future__ import annotations

from typing import Any

import pytest
from langchain_core.messages import HumanMessage
from langchain_core.runnables import Runnable, RunnableLambda

from ia_engine.domain.models import LlmProviderSpec, MediaAnalysis
from ia_engine.features.interpret_media.datasources.interpret_media_datasource import (
    InterpretMediaDataSource,
)
from ia_engine.features.interpret_media.domain.parameters import (
    InterpretMediaParameters,
)

SPEC = LlmProviderSpec(provider="openai", model="gpt-4o-mini")


class _CapturingChat:
    """Fake mínimo: captura a mensagem enviada em `with_structured_output`."""

    def __init__(self) -> None:
        self.captured_messages: list[HumanMessage] = []

    def with_structured_output(
        self, _schema: Any, **_kwargs: Any
    ) -> Runnable[Any, Any]:
        async def _invoke(messages: list[HumanMessage]) -> MediaAnalysis:
            self.captured_messages.extend(messages)
            return MediaAnalysis(analise="conteúdo do documento", resumo="ok")

        return RunnableLambda(_invoke)


@pytest.mark.asyncio
async def test_document_message_com_file_name_anexa_nome_ao_prompt(
    monkeypatch: pytest.MonkeyPatch,
):
    async def _fake_download(_url: str, **_kwargs: Any) -> bytes:
        return b"%PDF-fake-bytes"

    monkeypatch.setattr(
        "ia_engine.features.interpret_media.datasources"
        ".interpret_media_datasource.download_media",
        _fake_download,
    )
    chat = _CapturingChat()
    datasource = InterpretMediaDataSource(chat_model_factory=lambda _spec: chat)

    await datasource(
        InterpretMediaParameters(
            url="https://r2.example/contrato.pdf",
            mimetype="application/pdf",
            media_type="documentMessage",
            file_name="contrato-2026.pdf",
            vision_provider=SPEC,
        )
    )

    assert len(chat.captured_messages) == 1
    prompt_text = chat.captured_messages[0].content[0]["text"]
    assert "Nome do arquivo: contrato-2026.pdf" in prompt_text
