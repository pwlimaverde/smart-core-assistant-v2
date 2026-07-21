"""Transcritor real via API (SDK `openai`, `base_url` intercambiável).

Estratégia de fallback encadeada: primary Groq `whisper-large-v3-turbo`
(único com suporte nativo a ogg/opus do WhatsApp), fallback OpenAI
`gpt-4o-mini-transcribe`. Se todos os provedores falharem, degrada
graciosamente devolvendo texto vazio — NUNCA levanta exceção para cima
(o `process` do usecase decide a falha de domínio a partir do texto vazio).

Segurança/observabilidade:
- `api_key` sempre em `SecretStr` (repr redigido); nunca logada.
- Áudio bruto e texto transcrito NUNCA em log, em nenhum nível.
- Span `ia.transcribe` por tentativa, com atributos provedor/modelo/duração e
  `error_code` na falha — retry/fallback fica visível no trace.
"""

from __future__ import annotations

import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any, Protocol

from loguru import logger
from openai import AsyncOpenAI
from opentelemetry import trace
from opentelemetry.trace import StatusCode
from pydantic import SecretStr

from ia_engine.domain.models import LlmProviderSpec

_tracer = trace.get_tracer("ia_engine")

_GROQ_BASE_URL = "https://api.groq.com/openai/v1"
_DEFAULT_GROQ_MODEL = "whisper-large-v3-turbo"
_DEFAULT_OPENAI_MODEL = "gpt-4o-mini-transcribe"
_GROQ_PROVIDER = "groq"
_OPENAI_PROVIDER = "openai"

# Chaves opcionais em `extra_params` para armar o fallback OpenAI por tenant
# (resolvidas pelo worker; sem mudança de proto). Ausentes => sem fallback.
_FALLBACK_KEY_PARAM = "openai_fallback_api_key"
_FALLBACK_MODEL_PARAM = "openai_fallback_model"

_MIME_EXT = {
    "audio/ogg": "ogg",
    "audio/opus": "ogg",
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/mp4": "m4a",
    "audio/m4a": "m4a",
    "audio/x-m4a": "m4a",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/webm": "webm",
    "audio/flac": "flac",
}


class AsyncTranscriptionClient(Protocol):
    """Forma mínima do cliente usada aqui (duck-typing p/ testes sem rede)."""

    @property
    def audio(self) -> Any: ...


ClientFactory = Callable[[str, str | None], AsyncTranscriptionClient]


def _default_client_factory(
    api_key: str, base_url: str | None
) -> AsyncTranscriptionClient:
    return AsyncOpenAI(api_key=api_key, base_url=base_url)


@dataclass(frozen=True)
class TranscriberAttempt:
    """Uma tentativa de transcrição contra um provedor específico."""

    provider: str  # rótulo p/ observabilidade: "groq" | "openai"
    model: str
    api_key: SecretStr
    base_url: str | None = None


def _audio_filename(mimetype: str) -> str:
    ext = _MIME_EXT.get((mimetype or "").strip().lower(), "ogg")
    return f"audio.{ext}"


class ApiTranscriber:
    """Transcritor com fallback encadeado; degrada para "" sem levantar."""

    def __init__(
        self,
        attempts: Sequence[TranscriberAttempt],
        *,
        client_factory: ClientFactory = _default_client_factory,
    ) -> None:
        self._attempts = tuple(attempts)
        self._client_factory = client_factory

    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str:
        filename = _audio_filename(mimetype)
        content_type = (mimetype or "audio/ogg").strip() or "audio/ogg"
        for attempt in self._attempts:
            text = await self._try(
                attempt, audio_bytes, filename, content_type, language
            )
            if text:
                return text
        if self._attempts:
            logger.warning(
                "transcrição falhou em todas as tentativas (n={})",
                len(self._attempts),
            )
        return ""

    async def _try(
        self,
        attempt: TranscriberAttempt,
        audio_bytes: bytes,
        filename: str,
        content_type: str,
        language: str,
    ) -> str:
        start = time.perf_counter()
        with _tracer.start_as_current_span("ia.transcribe") as span:
            span.set_attribute("ia.transcribe.provider", attempt.provider)
            span.set_attribute("ia.transcribe.model", attempt.model)
            try:
                client = self._client_factory(
                    attempt.api_key.get_secret_value(), attempt.base_url
                )
                result = await client.audio.transcriptions.create(
                    model=attempt.model,
                    file=(filename, audio_bytes, content_type),
                    language=language,
                )
                text = (getattr(result, "text", "") or "").strip()
                span.set_attribute(
                    "ia.transcribe.duration_ms",
                    (time.perf_counter() - start) * 1000,
                )
                if not text:
                    span.set_attribute("ia.transcribe.error_code", "empty_result")
                return text
            except Exception as exc:  # noqa: BLE001 — degrada, nunca propaga
                span.set_attribute(
                    "ia.transcribe.duration_ms",
                    (time.perf_counter() - start) * 1000,
                )
                # Só o tipo da exceção (nunca a mensagem: pode conter fragmento
                # de chave/detalhe do provedor).
                span.set_attribute(
                    "ia.transcribe.error_code", type(exc).__name__
                )
                span.set_status(StatusCode.ERROR)
                return ""


def _extra(spec: LlmProviderSpec) -> dict[str, str]:
    return {key: value for key, value in spec.extra_params if key}


def build_transcriber(spec: LlmProviderSpec) -> ApiTranscriber:
    """Monta o `ApiTranscriber` a partir da config resolvida por tenant.

    Primary = provedor do `spec` (Groq por padrão, único com ogg/opus nativo).
    Fallback OpenAI só é armado se `extra_params[openai_fallback_api_key]`
    vier preenchido (resolvido pelo worker por tenant). Sem chave alguma, o
    transcritor não tem tentativas e degrada para "".
    """
    provider = (spec.provider or _GROQ_PROVIDER).strip().lower()
    extra = _extra(spec)
    attempts: list[TranscriberAttempt] = []

    if spec.api_key:
        if provider == _OPENAI_PROVIDER:
            attempts.append(
                TranscriberAttempt(
                    provider=_OPENAI_PROVIDER,
                    model=(spec.model or _DEFAULT_OPENAI_MODEL),
                    api_key=SecretStr(spec.api_key),
                    base_url=None,
                )
            )
        else:
            attempts.append(
                TranscriberAttempt(
                    provider=_GROQ_PROVIDER,
                    model=(spec.model or _DEFAULT_GROQ_MODEL),
                    api_key=SecretStr(spec.api_key),
                    base_url=_GROQ_BASE_URL,
                )
            )

    fallback_key = extra.get(_FALLBACK_KEY_PARAM)
    if fallback_key and provider != _OPENAI_PROVIDER:
        attempts.append(
            TranscriberAttempt(
                provider=_OPENAI_PROVIDER,
                model=extra.get(_FALLBACK_MODEL_PARAM) or _DEFAULT_OPENAI_MODEL,
                api_key=SecretStr(fallback_key),
                base_url=None,
            )
        )

    return ApiTranscriber(attempts)
