"""Exceções técnicas da camada LLM.

São lançadas pelas fábricas/datasources e traduzidas para casos de domínio
(`AppError`) pelos repositórios das features, via `map_error` — nunca chegam
ao chamador do usecase.
"""

from __future__ import annotations


class ProviderConfigException(Exception):
    """Config de provedor inválida ou falha ao inicializar o modelo."""


class LlmOutputInesperadoException(Exception):
    """O LLM retornou um tipo/conteúdo fora do contrato esperado."""
