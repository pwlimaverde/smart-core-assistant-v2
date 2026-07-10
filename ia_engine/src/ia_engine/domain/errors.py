"""Exceções de domínio por feature.

O `servicer` mapeia estas exceções para `grpc.StatusCode` apropriados. Nenhuma
mensagem de erro deve conter `api_key` ou outros segredos.
"""

from __future__ import annotations


class IaEngineError(Exception):
    """Base de todos os erros de domínio do ia_engine."""


class ProviderConfigError(IaEngineError):
    """Config de provedor LLM inválida/ausente (INVALID_ARGUMENT)."""


class InvalidRequestError(IaEngineError):
    """Request malformado do cliente (INVALID_ARGUMENT)."""


class MediaDownloadError(IaEngineError):
    """Falha ao baixar mídia da URL pré-assinada (FAILED_PRECONDITION)."""


class TranscribeError(IaEngineError):
    """Falha na transcrição de áudio."""


class InterpretMediaError(IaEngineError):
    """Falha na interpretação de mídia (imagem/vídeo/documento)."""


class AnalyseError(IaEngineError):
    """Falha na análise prévia (intents/entidades)."""


class EmbeddingError(IaEngineError):
    """Falha na geração/validação de embeddings."""


class ResponderError(IaEngineError):
    """Falha na geração da resposta do bot."""


class SentimentoError(IaEngineError):
    """Falha na análise de sentimento/avaliação."""
