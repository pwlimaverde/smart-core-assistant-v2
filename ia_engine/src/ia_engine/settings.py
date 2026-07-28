"""Configuração do processo (pydantic-settings).

Contém apenas configuração de infraestrutura do serviço. NUNCA guarda
`api_key` de provedor LLM — essa chega sempre por request (`LlmProviderConfig`).
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuração lida do ambiente."""

    model_config = SettingsConfigDict(
        env_prefix="",
        env_file=".env",
        extra="ignore",
    )

    grpc_port: int = 50060
    grpc_host: str = "0.0.0.0"
    # Fonte da config de tenant: o Rust publica `tenant:config:<uuid>` aqui e
    # sinaliza mudanças pelo canal de invalidação. O `ia_engine` nunca fala com
    # o Postgres (ver gerenciamento_configuracoes_ia.md). Mesma instância de
    # cache dos serviços Rust (REDIS_URL), não a de barramento (REDIS_BUS_URL).
    redis_url: str = "redis://redis:6379/0"
    otel_exporter_otlp_endpoint: str | None = None
    smartcore_env: str = "dev"
    grpc_max_workers: int = 16
    # Graceful shutdown: prazo (s) para drenar RPCs em andamento no SIGTERM.
    grpc_grace_seconds: float = 10.0
    # Transcrição de áudio desligada por padrão (custo/latência). O pipeline de
    # mídia do worker respeita a flag por tenant antes de chamar; esta é o
    # kill-switch global do processo — com ela off, o RPC Transcribe
    # curto-circuita e devolve resposta vazia.
    transcription_enabled: bool = False


def get_settings() -> Settings:
    return Settings()
