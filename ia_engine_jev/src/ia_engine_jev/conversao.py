"""Proto ↔ domínio do motor Jev, e o que se lê da config do tenant.

Fica fora do `servicer` para ser testável sem gRPC: são funções puras.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from typing import Any

from ia_engine_jev.config.models import RuntimeConfig
from ia_engine_jev.domain.jev import (
    APOS_COLETA,
    Dado,
    EntidadeDef,
    Fluxo,
    Horario,
    IntentDef,
    Politica,
    Trecho,
)

ESTRATEGIAS = ("regex", "lista", "varios", "data", "livre")
MAX_PERGUNTAS_PADRAO = 2
_HORA = re.compile(r"^(\d{1,2}):(\d{2})$")


def intents_do_proto(intents: Any) -> tuple[IntentDef, ...]:
    return tuple(
        IntentDef(
            tag=i.tag,
            grupo=i.grupo,
            descricao=i.descricao,
            exemplo=i.exemplo,
            comportamento=i.comportamento,
            campos_coleta=tuple(c.strip() for c in i.campos_coleta if c.strip()),
            max_perguntas=i.max_perguntas
            if i.max_perguntas > 0
            else MAX_PERGUNTAS_PADRAO,
            apos_coleta=i.apos_coleta if i.apos_coleta in APOS_COLETA else "transferir",
        )
        for i in intents
        if i.tag
    )


def dados_da_coleta(
    intents: Sequence[IntentDef],
    entidades: Sequence[EntidadeDef],
    campos: Sequence[tuple[str, str, str]] = (),
) -> tuple[Dado, ...]:
    """Todos os dados que alguma intenção coleta, com nome e definição.

    `campos`: (slug, nome, descrição) dos campos do cartão. O id da coleta é
    um tipo de entidade ou um slug de campo; sem nenhum dos dois, vale o
    próprio texto como nome (o tenant escreveu "arte pronta?", por exemplo).
    """
    por_entidade = {e.tipo: e.descricao for e in entidades}
    por_campo = {slug: (nome, descricao) for slug, nome, descricao in campos}
    vistos: dict[str, Dado] = {}
    for intent in intents:
        for id_ in intent.campos_coleta:
            if id_ in vistos:
                continue
            if id_ in por_campo:
                nome, descricao = por_campo[id_]
                vistos[id_] = Dado(id_, nome or id_, descricao)
            else:
                vistos[id_] = Dado(id_, id_, por_entidade.get(id_, ""))
    return tuple(vistos.values())


def _minutos(texto: Any, padrao: int) -> int:
    m = _HORA.match(str(texto or "").strip())
    if not m:
        return padrao
    h, mi = int(m.group(1)), int(m.group(2))
    return h * 60 + mi if 0 <= h <= 23 and 0 <= mi <= 59 else padrao


def _textos(valor: Any) -> tuple[str, ...]:
    if not isinstance(valor, list):
        return ()
    return tuple(str(v).strip() for v in valor if str(v).strip())


def politica_da_config(config: RuntimeConfig) -> Politica:
    """A política do tenant em `jev_config` (tudo opcional).

    Formato: `nao_fornecemos: {itens, alternativa, transferir}`,
    `nunca_pedir: [...]`, `horario: {fuso, dias, inicio, fim, aviso}`,
    `llm: {redacao, escalada}`, `trechos_max`. Valor torto é ignorado.
    """
    cfg = config.jev_config if isinstance(config.jev_config, dict) else {}
    nf = cfg.get("nao_fornecemos")
    nf = nf if isinstance(nf, dict) else {}
    llm = cfg.get("llm")
    llm = llm if isinstance(llm, dict) else {}
    horario: Horario | None = None
    h = cfg.get("horario")
    if isinstance(h, dict):
        dias = tuple(
            int(d)
            for d in h.get("dias", [0, 1, 2, 3, 4])
            if str(d).isdigit() and int(d) <= 6
        )
        horario = Horario(
            fuso=str(h.get("fuso") or "America/Sao_Paulo"),
            dias=dias or (0, 1, 2, 3, 4),
            inicio_min=_minutos(h.get("inicio"), 8 * 60),
            fim_min=_minutos(h.get("fim"), 18 * 60),
            aviso=str(h.get("aviso") or "").strip(),
        )
    trechos_max = cfg.get("trechos_max", 3)
    return Politica(
        nao_fornecemos=_textos(nf.get("itens")),
        alternativa=str(nf.get("alternativa") or "").strip(),
        transferir_nao_fornecido=bool(nf.get("transferir", True)),
        nunca_pedir=_textos(cfg.get("nunca_pedir")),
        horario=horario,
        modelo_redacao=str(llm.get("redacao") or "").strip(),
        modelo_escalada=str(llm.get("escalada") or "").strip(),
        trechos_max=trechos_max
        if isinstance(trechos_max, int) and 1 <= trechos_max <= 10
        else 3,
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
