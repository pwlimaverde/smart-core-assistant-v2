"""Mapa de correspondencia id_v1 -> id_v2, por (tenant, entidade).

Necessario porque a v1 e DB-per-tenant: cada tenant tem sua propria sequencia
de ids (`SERIAL`/`BigAutoField`) comecando em 1, entao dois tenants podem ter
um `Atendimento` id=42 completamente diferente. Ao consolidar tudo num unico
banco v2, colisoes sao esperadas — nao tentamos preservar o id original para
as tabelas TENANT_APPS (decisao documentada no README: diferente do que o
plano permitia "preservar quando possivel", este ETL sempre gera id novo via
SERIAL do v2 e mantem o mapa, por uniformidade e simplicidade de codigo,
mesmo sabendo que hoje so ha um tenant ativo em producao).

Persistencia dupla:
1. Um arquivo "vivo" (`--state-dir/id_map.json`) e lido no inicio e
   sobrescrito no fim de cada execucao — e o que da idempotencia entre
   execucoes (uma segunda rodada reconhece ids ja migrados e faz UPDATE em
   vez de duplicar).
2. Um snapshot **versionado por execucao** (`reports/<run_id>/id_map.json`)
   e sempre gravado tambem, para auditoria historica (o plano pede
   explicitamente "arquivo JSON versionado por execucao").
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class IdMapKey:
    tenant_slug: str
    entidade: str
    id_v1: int

    def as_str(self) -> str:
        # chave textual estavel para serializacao JSON (dict keys tem que ser str)
        return f"{self.tenant_slug}␟{self.entidade}␟{self.id_v1}"

    @staticmethod
    def from_str(s: str) -> "IdMapKey":
        tenant_slug, entidade, id_v1 = s.split("␟")
        return IdMapKey(tenant_slug=tenant_slug, entidade=entidade, id_v1=int(id_v1))


@dataclass
class IdMap:
    """Mapa em memoria, carregavel/salvavel em JSON."""

    _dados: dict[str, int] = field(default_factory=dict)
    sujo: bool = False  # True se houve alteracao desde o ultimo load/save

    def get(self, tenant_slug: str, entidade: str, id_v1: int) -> int | None:
        return self._dados.get(IdMapKey(tenant_slug, entidade, id_v1).as_str())

    def set(self, tenant_slug: str, entidade: str, id_v1: int, id_v2: int) -> None:
        chave = IdMapKey(tenant_slug, entidade, id_v1).as_str()
        if self._dados.get(chave) != id_v2:
            self._dados[chave] = id_v2
            self.sujo = True

    def __len__(self) -> int:
        return len(self._dados)

    def entradas_por_entidade(self, tenant_slug: str, entidade: str) -> dict[int, int]:
        """Devolve `{id_v1: id_v2}` para uma entidade/tenant — usado no remapeamento de FKs."""
        prefixo = f"{tenant_slug}␟{entidade}␟"
        resultado: dict[int, int] = {}
        for chave, id_v2 in self._dados.items():
            if chave.startswith(prefixo):
                id_v1 = int(chave.rsplit("␟", 1)[1])
                resultado[id_v1] = id_v2
        return resultado

    def to_dict(self) -> dict[str, int]:
        return dict(self._dados)

    @classmethod
    def load(cls, path: Path) -> "IdMap":
        if not path.exists():
            return cls()
        conteudo = json.loads(path.read_text(encoding="utf-8"))
        return cls(_dados=dict(conteudo))

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(self._dados, indent=2, sort_keys=True, ensure_ascii=False),
            encoding="utf-8",
        )
        self.sujo = False
