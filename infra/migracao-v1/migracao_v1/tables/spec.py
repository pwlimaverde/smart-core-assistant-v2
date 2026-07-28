"""Estruturas declarativas que descrevem "como migrar uma tabela".

O objetivo e ter UM motor generico (`tables/engine.py`, testavel em isolado)
consumido por dezenas de tabelas (`tables/core_specs.py`,
`tables/tenant_specs.py`) descritas apenas como dados — em vez de repetir a
logica de upsert/idempotencia/dry-run/relatorio em cada tabela.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Literal

IdStrategy = Literal["preserve", "map", "natural"]
Scope = Literal["core", "tenant"]
PkKind = Literal["int", "uuid"]
"""Tipo da PK v1 usada na paginacao por keyset (`WHERE pk > sentinela ORDER BY pk`).
`uuid.UUID` e ordenavel em Python (compara por `.int`), entao a paginacao
funciona igual para os dois tipos — so o sentinela inicial muda (`0` vs
`UUID(int=0)`, o UUID nulo, que nunca e gerado por `uuid_generate_v4()`)."""

# Assinatura do transform de coluna: recebe o valor bruto da coluna v1 e o
# RowContext (definido em engine.py, importado la para evitar ciclo) e
# devolve o valor pronto para gravar na coluna v2.
ColumnTransform = Callable[[Any, Any], Any]


@dataclass(frozen=True)
class ColumnSpec:
    v1: str
    """Nome da coluna na tabela v1 de origem."""
    v2: str | None = None
    """Nome da coluna na tabela v2 de destino (default: igual a `v1`)."""
    transform: ColumnTransform | None = None
    """Funcao opcional `(valor_v1, RowContext) -> valor_v2`. Default: identidade."""
    v1_cast: str | None = None
    """Cast SQL aplicado na leitura (ex.: `"::text"` para colunas `vector` do
    pgvector — `asyncpg` nao tem codec nativo para o tipo `vector`)."""
    v2_cast: str | None = None
    """Cast SQL aplicado no placeholder de escrita (ex.: `"::vector"`)."""
    preservar_destino_quando: str | None = None
    """Expressao SQL que, quando VERDADEIRA para a linha ja existente no v2,
    faz o UPDATE manter o valor do destino em vez de sobrescrever com o da v1.

    Use `{t}` como placeholder da tabela de destino. Serve para colunas em que
    o v2 pode ter um valor MELHOR que o da v1 — o caso real e' `auth_user.
    password_hash`: o ETL escreve o marcador `!migrated-from-v1` de proposito,
    mas se o superusuario do v2 ja tiver senha valida (criado antes da carga),
    sobrescreve-la significa perder o acesso administrativo do ambiente.
    """

    def nome_v2(self) -> str:
        return self.v2 or self.v1


@dataclass(frozen=True)
class FkRemap:
    """Descreve uma coluna v2 cujo valor precisa ser reescrito via `IdMap`.

    A coluna ja deve existir no dict de valores v2 (via `ColumnSpec`) contendo
    o id **v1** bruto — o engine substitui pelo id v2 mapeado apos montar a
    linha, na ordem declarada em `TableSpec.fk_remaps` (por isso a ordem de
    `TableSpec`s importa: entidades referenciadas devem ser migradas antes).
    """

    coluna_v2: str
    entidade_referenciada: str
    nullable: bool = True


@dataclass(frozen=True)
class TableSpec:
    entidade: str
    """Identificador unico usado em relatorios, `id_map` e `--entidade` do CLI."""
    v1_table: str
    v2_table: str
    columns: list[ColumnSpec]
    scope: Scope
    id_strategy: IdStrategy
    pk_v1: str = "id"
    pk_v2: str = "id"
    pk_kind: PkKind = "int"
    natural_conflict_cols: tuple[str, ...] | None = None
    fk_remaps: tuple[FkRemap, ...] = field(default_factory=tuple)
    delta_column_v1: str | None = None
    """Coluna v1 usada pelo filtro `--since` (ex.: `updated_at`, `data_atualizacao`)."""

    def __post_init__(self) -> None:
        if self.id_strategy == "natural" and not self.natural_conflict_cols:
            raise ValueError(
                f"TableSpec({self.entidade}): id_strategy='natural' exige natural_conflict_cols"
            )
        if self.scope == "tenant" and self.id_strategy == "preserve":
            raise ValueError(
                f"TableSpec({self.entidade}): tabelas 'tenant' (DB-per-tenant na v1) nao podem "
                "usar id_strategy='preserve' — colisao de ids entre tenants e esperada; use 'map'."
            )
        for c in self.columns:
            if c.nome_v2() == self.pk_v2:
                raise ValueError(
                    f"TableSpec({self.entidade}): coluna '{c.nome_v2()}' colide com pk_v2 — "
                    "o pk nunca deve aparecer em `columns` (o engine o trata separadamente)."
                )

    def v2_cast_por_coluna(self) -> dict[str, str]:
        """Mapa `nome_v2 -> cast SQL` (ex.: `"::vector"`), usado pelo engine
        para montar os placeholders de INSERT/UPDATE corretamente."""
        return {c.nome_v2(): c.v2_cast for c in self.columns if c.v2_cast}

    def preservacao_por_coluna(self) -> dict[str, str]:
        """Mapa `nome_v2 -> condicao SQL` das colunas que nao devem ser
        sobrescritas quando o destino ja tem valor melhor (ver
        `ColumnSpec.preservar_destino_quando`)."""
        return {
            c.nome_v2(): c.preservar_destino_quando
            for c in self.columns
            if c.preservar_destino_quando
        }
