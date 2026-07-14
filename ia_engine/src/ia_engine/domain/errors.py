"""Casos de erro de domínio compartilhados entre features.

No padrão py-return-success-or-error os erros são **valores** imutáveis
(`AppError`) que trafegam dentro de `Failure` — nunca exceções lançadas.
Cada feature declara sua união fechada em `features/<nome>/domain/errors.py`,
reutilizando os casos daqui quando a falha é comum a mais de uma feature.

O `servicer` mapeia estes casos para `grpc.StatusCode`. Nenhuma mensagem de
erro deve conter `api_key` ou outros segredos.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import final

from py_return_success_or_error import AppError


@final
@dataclass(frozen=True)
class InvalidRequestError(AppError):
    """Request malformado do cliente (INVALID_ARGUMENT).

    Erro de transporte: emitido pela validação do `servicer`, antes de
    qualquer usecase — não participa das uniões fechadas das features.
    """


@final
@dataclass(frozen=True)
class ProviderConfigError(AppError):
    """Config de provedor LLM inválida/ausente (INVALID_ARGUMENT)."""


@final
@dataclass(frozen=True)
class MediaDownloadError(AppError):
    """Falha ao baixar mídia da URL pré-assinada (FAILED_PRECONDITION)."""


@final
@dataclass(frozen=True)
class LlmRespostaInvalidaError(AppError):
    """LLM retornou tipo/conteúdo inesperado (INTERNAL)."""
