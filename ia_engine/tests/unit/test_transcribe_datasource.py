"""Testes do datasource da feature Transcribe (`transcribe_datasource.py`).

Cobre o resumo best-effort (`_summarize`/`_fallback_resumo`, funções puras)
e o caminho de transcrição vazia (não chama o resumidor) — mock só na
fronteira externa (o `AudioTranscriber`/chat model e o download de mídia,
nunca a lógica de domínio).
"""

from __future__ import annotations

from typing import Any

import pytest

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.transcribe.datasources.transcribe_datasource import (
    TranscribeDataSource,
    _fallback_resumo,
    _summarize,
)
from ia_engine.features.transcribe.domain.parameters import TranscribeParameters

SPEC = LlmProviderSpec(provider="openai", model="gpt-4o-mini")


# ------------------------------------------------------------ _fallback_resumo
def test_fallback_resumo_texto_curto_mantido_integral():
    assert _fallback_resumo("  áudio curto  ") == "áudio curto"


def test_fallback_resumo_texto_longo_e_truncado_com_reticencias():
    texto = "x" * 250
    resumo = _fallback_resumo(texto)
    assert resumo.endswith("...")
    assert len(resumo) == 200


# ------------------------------------------------------------------ _summarize
class _RaisingModel:
    async def ainvoke(self, _prompt: str) -> Any:
        raise RuntimeError("provedor indisponível")


class _OkModel:
    def __init__(self, content: str) -> None:
        self._content = content

    async def ainvoke(self, _prompt: str) -> Any:
        class _Resp:
            content = self._content

        return _Resp()


@pytest.mark.asyncio
async def test_summarize_com_falha_do_modelo_degrada_para_fallback():
    """Resumo nunca quebra o fluxo principal: falha do chat model vira o
    recorte determinístico da transcrição."""
    resumo = await _summarize("transcrição bem longa " * 20, _RaisingModel())
    assert resumo == _fallback_resumo("transcrição bem longa " * 20)


@pytest.mark.asyncio
async def test_summarize_com_sucesso_usa_conteudo_do_modelo():
    resumo = await _summarize("olá mundo", _OkModel("resumo gerado"))
    assert resumo == "resumo gerado"


@pytest.mark.asyncio
async def test_summarize_resposta_vazia_degrada_para_fallback():
    resumo = await _summarize("texto original", _OkModel("   "))
    assert resumo == _fallback_resumo("texto original")


# --------------------------------------------------------------- datasource
class _FakeTranscriberVazio:
    async def __call__(
        self, _audio_bytes: bytes, _mimetype: str, _language: str
    ) -> str:
        return "   "


class _FakeTranscriberComTexto:
    async def __call__(
        self, _audio_bytes: bytes, _mimetype: str, _language: str
    ) -> str:
        return "conteúdo transcrito"


@pytest.mark.asyncio
async def test_datasource_transcricao_vazia_nao_chama_resumidor(
    monkeypatch: pytest.MonkeyPatch,
):
    async def _fake_download(_url: str, **_kwargs: Any) -> bytes:
        return b"audio-bytes"

    monkeypatch.setattr(
        "ia_engine.features.transcribe.datasources.transcribe_datasource"
        ".download_media",
        _fake_download,
    )
    chamado = False

    def _chat_model_factory(_spec: LlmProviderSpec) -> _OkModel:
        nonlocal chamado
        chamado = True
        return _OkModel("não deveria ser usado")

    datasource = TranscribeDataSource(
        transcriber_factory=lambda _spec: _FakeTranscriberVazio(),
        chat_model_factory=_chat_model_factory,
    )
    resultado = await datasource(
        TranscribeParameters(
            url="https://r2.example/audio.ogg",
            mimetype="audio/ogg",
            language="pt",
            transcription_provider=SPEC,
        )
    )
    assert resultado.transcricao == ""
    assert resultado.resumo == ""
    assert chamado is False


@pytest.mark.asyncio
async def test_datasource_com_transcricao_gera_resumo(
    monkeypatch: pytest.MonkeyPatch,
):
    async def _fake_download(_url: str, **_kwargs: Any) -> bytes:
        return b"audio-bytes"

    monkeypatch.setattr(
        "ia_engine.features.transcribe.datasources.transcribe_datasource"
        ".download_media",
        _fake_download,
    )
    datasource = TranscribeDataSource(
        transcriber_factory=lambda _spec: _FakeTranscriberComTexto(),
        chat_model_factory=lambda _spec: _OkModel("resumo curto"),
    )
    resultado = await datasource(
        TranscribeParameters(
            url="https://r2.example/audio.ogg",
            mimetype="audio/ogg",
            language="",
            transcription_provider=SPEC,
        )
    )
    assert resultado.transcricao == "conteúdo transcrito"
    assert resultado.resumo == "resumo curto"
