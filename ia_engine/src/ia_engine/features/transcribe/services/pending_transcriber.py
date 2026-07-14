"""Transcritor padrão (produção): integração real ainda pendente."""

from __future__ import annotations


class PendingTranscriber:
    """Mantém a assinatura de `AudioTranscriber`; falha de forma clara.

    A chamada real ao provedor de transcrição (whisper/groq/etc.) ainda não
    foi plugada. O `NotImplementedError` é traduzido pelo repositório para o
    caso de domínio `TranscricaoIndisponivelError`. Nos testes, injeta-se um
    fake.
    """

    async def __call__(
        self, audio_bytes: bytes, mimetype: str, language: str
    ) -> str:
        raise NotImplementedError(
            "transcrição de áudio pendente de integração com provedor "
            "(whisper/groq); injete um AudioTranscriber concreto"
        )
