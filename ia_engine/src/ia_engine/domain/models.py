"""Modelos de domínio (pydantic v2 nativo).

Alguns servem de schema para `with_structured_output`; outros são resultados
internos das features, convertidos para proto pelo `servicer`.
"""

from __future__ import annotations

from dataclasses import dataclass

from pydantic import BaseModel, Field


@dataclass(frozen=True)
class LlmProviderSpec:
    """Config de provedor LLM já desacoplada do proto.

    O `servicer` converte `pb.LlmProviderConfig` para este valor de domínio —
    as camadas internas (parameters/datasources) nunca importam proto. A
    `api_key` chega por request e nunca é logada nem persistida.
    """

    provider: str
    model: str
    api_key: str = ""
    temperature: float = 0.0
    extra_params: tuple[tuple[str, str], ...] = ()


class RespostaBot(BaseModel):
    """Structured output da geração de resposta do bot (RPC Responder)."""

    resposta_texto: str = Field(
        description="Resposta completa e educada para o usuário final",
    )
    acao_transferencia: str | None = Field(
        default=None,
        description=(
            "Nome EXATO do setor para transferência. Preencha apenas se for "
            "necessário transferir o atendimento, usando o nome conforme "
            "listado nos setores disponíveis."
        ),
    )
    confianca: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Score de confiança da resposta (0.0 a 1.0)",
    )


class MediaAnalysis(BaseModel):
    """Structured output da análise de mídia (transcrição/interpretação)."""

    analise: str = Field(
        description=(
            "Descrição/transcrição completa e detalhada do conteúdo da mídia, "
            "em português (contexto interno do bot)."
        ),
    )
    resumo: str = Field(
        default="",
        description=(
            "Resumo geral curto (1-3 frases), em português, do que se trata a "
            "mídia — para exibir ao atendente."
        ),
    )


class AnaliseAvaliacao(BaseModel):
    """Structured output da análise de sentimento/avaliação (RPC Sentimento)."""

    nota: int = Field(
        description="Nota de avaliação numérica, escala 1-5",
    )
    sentimento: str = Field(
        description="Sentimento do cliente ('positivo' ou 'negativo')",
    )
    feedback: str | None = Field(
        default=None,
        description="Texto original do feedback, se houver",
    )


class IntentItem(BaseModel):
    """Intenção detectada na mensagem."""

    tipo: str
    confianca: float = 1.0


class EntidadeItem(BaseModel):
    """Entidade extraída da mensagem."""

    tipo: str
    valor: str
    confianca: float = 1.0


class IntentsEntidades(BaseModel):
    """Resultado da análise prévia (RPC Analyse)."""

    intents: list[IntentItem] = Field(default_factory=list)
    entidades: list[EntidadeItem] = Field(default_factory=list)


class RespostaFinal(BaseModel):
    """Resultado consolidado do RPC Responder (pós score/transferência)."""

    resposta_texto: str
    transferir_atendimento: bool
    fluxo_transferencia: str
    confiabilidade: float
