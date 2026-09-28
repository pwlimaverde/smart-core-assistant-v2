"""Proto ↔ domínio do motor Jev, e o que se lê da config do tenant.

Fica fora do `servicer` para ser testável sem gRPC: são funções puras.
"""

from __future__ import annotations

from typing import Any

from ia_engine_jev.config.models import RuntimeConfig
from ia_engine_jev.domain.jev import EntidadeDef, Fluxo, IntentDef, Trecho

ESTRATEGIAS = ("regex", "lista", "varios", "data", "livre")


def intents_do_proto(intents: Any) -> tuple[IntentDef, ...]:
    return tuple(
        IntentDef(
            tag=i.tag,
            grupo=i.grupo,
            descricao=i.descricao,
            exemplo=i.exemplo,
            comportamento=i.comportamento,
        )
        for i in intents
        if i.tag
    )


def entidades_da_config(
    config: RuntimeConfig, do_request: Any = ()
) -> tuple[EntidadeDef, ...]:
    """Tipos de entidade: os do request, se vierem; senão os da config.

    A estratégia de cada tipo vem de `jev_config.entidades.<tipo>`; sem ela,
    `livre` (presença pelo Jev, valor copiado pela LLM e conferido).
    """
    vindos = tuple(
        EntidadeDef(
            tipo=e.tipo,
            descricao=e.descricao,
            estrategia=e.estrategia if e.estrategia in ESTRATEGIAS else "livre",
            opcoes=tuple(e.opcoes),
        )
        for e in do_request
        if e.tipo
    )
    if vindos:
        return vindos
    cfg_entidades = (config.jev_config or {}).get("entidades")
    estrategias: dict[str, Any] = (
        cfg_entidades if isinstance(cfg_entidades, dict) else {}
    )
    resultado: list[EntidadeDef] = []
    for tipo, descricao in config.entity_descricoes.items():
        if not tipo.strip():
            continue
        cfg = estrategias.get(tipo) if isinstance(estrategias.get(tipo), dict) else {}
        estrategia = str(cfg.get("estrategia", "livre")) if cfg else "livre"
        opcoes = cfg.get("opcoes", []) if cfg else []
        resultado.append(
            EntidadeDef(
                tipo=tipo,
                descricao=descricao or "",
                estrategia=estrategia if estrategia in ESTRATEGIAS else "livre",
                opcoes=tuple(str(o) for o in opcoes if str(o).strip())
                if isinstance(opcoes, list)
                else (),
            )
        )
    return tuple(resultado)


def fluxos_do_proto(pares: Any) -> tuple[Fluxo, ...]:
    return tuple(Fluxo(chave=kv.key, fluxo_id=kv.value) for kv in pares if kv.key)


def trechos_do_proto(trechos: Any, dados_treinamento: str) -> tuple[Trecho, ...]:
    """Trechos separados; um worker antigo manda tudo colado — vira um só."""
    separados = tuple(
        Trecho(id=t.id or str(n), conteudo=t.conteudo, distancia=t.distancia)
        for n, t in enumerate(trechos)
        if (t.conteudo or "").strip()
    )
    if separados:
        return separados
    if (dados_treinamento or "").strip():
        return (Trecho(id="0", conteudo=dados_treinamento),)
    return ()


def usa_jev(config: RuntimeConfig) -> bool:
    """Há chave da plataforma? Sem ela, o motor Jev responde pelo caminho da LLM."""
    return bool((config.typesafe_api_key or "").strip())
