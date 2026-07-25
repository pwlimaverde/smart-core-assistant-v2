"""Suporte a carga full x delta (`--since <timestamp>`).

Duas passadas exigidas pelo plano (secao "Requisitos transversais"):
- Full load: `since=None`, todas as linhas.
- Delta: apenas linhas cujo `updated_at`/`data_atualizacao` (ou equivalente)
  seja `>= since`. Nao ha deteccao sofisticada de delta (CDC, etc.) — e uma
  comparacao simples de timestamp, suficiente para reduzir a janela de
  downtime do cutover reprocessando so o que mudou desde a carga full.

Linhas sem coluna de timestamp de atualizacao (ex.: tabelas somente-insercao
como `oraculo_movimento_fluxo`, que nao tem update apos criada) sempre sao
incluidas em modo delta — nao ha como saber se "mudaram" sem timestamp, e
excluir arriscaria perder dados; o custo de reprocessar linhas
imutaveis e apenas um upsert idempotente a mais.
"""

from __future__ import annotations

from datetime import datetime


def incluir_no_delta(valor_timestamp: datetime | None, since: datetime | None) -> bool:
    """Decide se uma linha entra na carga, dado o filtro `--since`.

    Regras:
    - `since is None` -> carga full, sempre inclui.
    - `valor_timestamp is None` -> tabela/linha sem coluna de controle de
      atualizacao; inclui sempre (nao ha como filtrar com seguranca).
    - Caso contrario, inclui apenas se `valor_timestamp >= since`.
    """
    if since is None:
        return True
    if valor_timestamp is None:
        return True
    return valor_timestamp >= since


def clausula_since_sql(coluna: str | None, indice_parametro: int) -> str:
    """Monta o fragmento SQL parametrizado (`$N`) do filtro `--since`.

    Retorna string vazia quando a tabela nao tem coluna de controle
    (`coluna is None`) — o filtro e aplicado em memoria nesse caso via
    `incluir_no_delta`, ou simplesmente omitido (carga completa da tabela).
    """
    if coluna is None:
        return ""
    return f" AND {coluna} >= ${indice_parametro}"
