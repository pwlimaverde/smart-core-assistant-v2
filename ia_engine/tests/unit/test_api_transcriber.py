"""Testes do transcritor real via API (`services/api_transcriber.py`).

Nenhum teste toca rede: o cliente `AsyncOpenAI` é substituído por um fake
duck-typado via `client_factory`. Cobre o caminho feliz (Groq), o fallback
(Groq falha → OpenAI), a degradação graciosa (ambos falham → "") e a
montagem das tentativas por `build_transcriber` (incl. chave em `SecretStr`
redigida no repr).
"""

from __future__ import annotations

from typing import Any

import pytest
from pydantic import SecretStr

from ia_engine.domain.models import LlmProviderSpec
from ia_engine.features.transcribe.services.api_transcriber import (
    _GROQ_BASE_URL,
    ApiTranscriber,
    TranscriberAttempt,
    _audio_filename,
    _default_client_factory,
    build_transcriber,
)


# ------------------------------------------------------------- fake client
class _FakeResult:
    def __init__(self, text: str) -> None:
        self.text = text


class _FakeTranscriptions:
    def __init__(self, recorder: _Recorder, base_url: str | None) -> None:
        self._recorder = recorder
        self._base_url = base_url

    async def create(self, **kwargs: Any) -> _FakeResult:
        self._recorder.calls.append((self._base_url, kwargs))
        action = self._recorder.script[self._base_url]
        if isinstance(action, Exception):
            raise action
        return _FakeResult(action)


class _FakeAudio:
    def __init__(self, transcriptions: _FakeTranscriptions) -> None:
        self.transcriptions = transcriptions


class _FakeClient:
    def __init__(self, recorder: _Recorder, base_url: str | None) -> None:
        self.audio = _FakeAudio(_FakeTranscriptions(recorder, base_url))


class _Recorder:
    """Roteia comportamento por `base_url` e registra as chamadas/keys."""

    def __init__(self, script: dict[str | None, str | Exception]) -> None:
        self.script = script
        self.calls: list[tuple[str | None, dict[str, Any]]] = []
        self.keys: list[str] = []

    def factory(self, api_key: str, base_url: str | None) -> _FakeClient:
        self.keys.append(api_key)
        return _FakeClient(self, base_url)


def _attempts() -> list[TranscriberAttempt]:
    return [
        TranscriberAttempt(
            provider="groq",
            model="whisper-large-v3-turbo",
            api_key=SecretStr("gsk-test"),
            base_url=_GROQ_BASE_URL,
        ),
        TranscriberAttempt(
            provider="openai",
            model="gpt-4o-mini-transcribe",
            api_key=SecretStr("sk-test"),
            base_url=None,
        ),
    ]


# ------------------------------------------------------------------ ApiTranscriber
@pytest.mark.asyncio
async def test_sucesso_via_groq_nao_chama_fallback():
    rec = _Recorder({_GROQ_BASE_URL: "olá do groq", None: "não deveria"})
    transcriber = ApiTranscriber(_attempts(), client_factory=rec.factory)

    texto = await transcriber(b"audio", "audio/ogg", "pt")

    assert texto == "olá do groq"
    assert [base for base, _ in rec.calls] == [_GROQ_BASE_URL]  # só Groq
    assert rec.keys == ["gsk-test"]


@pytest.mark.asyncio
async def test_groq_falha_faz_fallback_para_openai():
    rec = _Recorder(
        {_GROQ_BASE_URL: RuntimeError("groq 503"), None: "olá da openai"}
    )
    transcriber = ApiTranscriber(_attempts(), client_factory=rec.factory)

    texto = await transcriber(b"audio", "audio/ogg", "pt")

    assert texto == "olá da openai"
    assert [base for base, _ in rec.calls] == [_GROQ_BASE_URL, None]


@pytest.mark.asyncio
async def test_ambos_falham_degrada_para_vazio():
    rec = _Recorder(
        {_GROQ_BASE_URL: RuntimeError("groq"), None: RuntimeError("openai")}
    )
    transcriber = ApiTranscriber(_attempts(), client_factory=rec.factory)

    texto = await transcriber(b"audio", "audio/ogg", "pt")

    assert texto == ""
    assert len(rec.calls) == 2  # tentou os dois antes de degradar


@pytest.mark.asyncio
async def test_resultado_vazio_do_provedor_tenta_o_proximo():
    rec = _Recorder({_GROQ_BASE_URL: "   ", None: "openai salvou"})
    transcriber = ApiTranscriber(_attempts(), client_factory=rec.factory)

    texto = await transcriber(b"audio", "audio/ogg", "pt")

    assert texto == "openai salvou"


@pytest.mark.asyncio
async def test_sem_tentativas_degrada_para_vazio():
    rec = _Recorder({})
    transcriber = ApiTranscriber([], client_factory=rec.factory)

    texto = await transcriber(b"audio", "audio/ogg", "pt")

    assert texto == ""
    assert rec.calls == []


@pytest.mark.asyncio
async def test_passa_filename_e_content_type_corretos():
    rec = _Recorder({_GROQ_BASE_URL: "ok", None: "x"})
    transcriber = ApiTranscriber(_attempts(), client_factory=rec.factory)

    await transcriber(b"audio-bytes", "audio/ogg", "pt")

    _, kwargs = rec.calls[0]
    filename, data, content_type = kwargs["file"]
    assert filename == "audio.ogg"
    assert data == b"audio-bytes"
    assert content_type == "audio/ogg"
    assert kwargs["language"] == "pt"
    assert kwargs["model"] == "whisper-large-v3-turbo"


# --------------------------------------------------------------- helpers puros
@pytest.mark.parametrize(
    ("mimetype", "esperado"),
    [
        ("audio/ogg", "audio.ogg"),
        ("audio/mpeg", "audio.mp3"),
        ("audio/mp4", "audio.m4a"),
        ("audio/wav", "audio.wav"),
        ("audio/desconhecido", "audio.ogg"),
        ("", "audio.ogg"),
    ],
)
def test_audio_filename(mimetype: str, esperado: str):
    assert _audio_filename(mimetype) == esperado


# ----------------------------------------------------------- build_transcriber
def test_build_transcriber_groq_primary_unico_attempt():
    spec = LlmProviderSpec(provider="groq", model="", api_key="gsk-x")
    transcriber = build_transcriber(spec)
    attempts = transcriber._attempts  # type: ignore[attr-defined]
    assert len(attempts) == 1
    assert attempts[0].provider == "groq"
    assert attempts[0].base_url == _GROQ_BASE_URL
    assert attempts[0].model == "whisper-large-v3-turbo"  # default aplicado


def test_build_transcriber_provider_vazio_assume_groq():
    spec = LlmProviderSpec(provider="", model="", api_key="gsk-x")
    attempts = build_transcriber(spec)._attempts  # type: ignore[attr-defined]
    assert attempts[0].provider == "groq"


def test_build_transcriber_arma_fallback_openai_via_extra_params():
    spec = LlmProviderSpec(
        provider="groq",
        model="whisper-large-v3-turbo",
        api_key="gsk-x",
        extra_params=(
            ("openai_fallback_api_key", "sk-fallback"),
            ("openai_fallback_model", "gpt-4o-transcribe"),
        ),
    )
    attempts = build_transcriber(spec)._attempts  # type: ignore[attr-defined]
    assert [a.provider for a in attempts] == ["groq", "openai"]
    assert attempts[1].model == "gpt-4o-transcribe"


def test_build_transcriber_openai_primary_sem_fallback_duplicado():
    spec = LlmProviderSpec(
        provider="openai",
        model="gpt-4o-mini-transcribe",
        api_key="sk-x",
        extra_params=(("openai_fallback_api_key", "sk-ignorado"),),
    )
    attempts = build_transcriber(spec)._attempts  # type: ignore[attr-defined]
    assert [a.provider for a in attempts] == ["openai"]  # não duplica openai


def test_build_transcriber_sem_api_key_sem_tentativas():
    spec = LlmProviderSpec(provider="groq", model="", api_key="")
    attempts = build_transcriber(spec)._attempts  # type: ignore[attr-defined]
    assert attempts == ()


def test_default_client_factory_constroi_async_openai_com_base_url():
    """A fábrica real constrói o `AsyncOpenAI` (sem rede na construção); o
    `base_url` do Groq é repassado. Chave fictícia, nenhuma chamada emitida."""
    client = _default_client_factory("gsk-x", _GROQ_BASE_URL)
    assert str(client.base_url).startswith("https://api.groq.com")


def test_api_key_redigida_no_repr_do_attempt():
    attempt = TranscriberAttempt(
        provider="groq",
        model="m",
        api_key=SecretStr("gsk-super-secreta"),
        base_url=_GROQ_BASE_URL,
    )
    assert "gsk-super-secreta" not in repr(attempt)
