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


@final
@dataclass(frozen=True)
class ConfigTenantAusenteError(AppError):
    """Sem config publicada para o tenant no Redis (FAILED_PRECONDITION).

    Não é falha da IA: é pendência de provisionamento. O `data_postgres`
    publica no boot (pre-warm) e a cada alteração de config — se caiu aqui, ou
    ele não subiu, ou o tenant é novo e nada foi salvo ainda.
    """


# --- Motor Jev (plano ia-engine-jev) ---------------------------------------
@final
@dataclass(frozen=True)
class JevIndisponivelError(AppError):
    """TypeSafe fora, lenta ou limitando (429) depois do retry (UNAVAILABLE)."""


@final
@dataclass(frozen=True)
class JevNaoConfiguradoError(AppError):
    """Chave TypeSafe ausente ou recusada na configuração geral.

    FAILED_PRECONDITION: é pendência de configuração da plataforma — a chave
    fica nas CoreSettings (`TYPESAFE_API_KEY`) —, não falha da IA.
    """


@final
@dataclass(frozen=True)
class JevPerguntaInvalidaError(AppError):
    """O Jev recusou a pergunta como malformada (INTERNAL: bug nosso)."""
