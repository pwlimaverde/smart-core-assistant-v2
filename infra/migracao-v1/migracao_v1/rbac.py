"""Transformacao de RBAC: `module_permissions` aninhado (v1) -> array de escopos (v2).

Decisao ja aprovada (ver prompt do plano, item 2): a v1 guarda
`{modulo: {view: bool, edit: bool, delete: bool}}`; a v2 espera um array de
strings `"modulo:acao"` (ou um objeto flat `{escopo: bool}` — mas usamos
array, que e o formato mais direto). A funcao `derivar_escopos` em
`server/crates/application/src/auth/login.rs` aceita ambos os formatos; ver
testes la (`derivar_escopos_usa_module_permissions_quando_e_array`).

`flow_permissions` (lista de ints) e copiado sem transformacao — ver
`transformar_flow_permissions`.
"""

from __future__ import annotations

import json
from typing import Any, TypedDict


def transformar_module_permissions(module_permissions: dict[str, Any] | None) -> list[str]:
    """Converte `{modulo: {acao: bool}}` (v1) em `["modulo:acao", ...]` (v2).

    Apenas pares com valor `True` viram entradas no array (chaves com `False`
    ou ausentes sao omitidas). Entradas malformadas (valor nao-dict, ou
    dict com valores nao-bool) sao ignoradas silenciosamente e reportadas
    pelo chamador na amostra de conciliacao — este ETL nao aborta por um
    unico registro malformado.

    Ordem de saida: deterministica (modulo, depois acao, ambos ordenados)
    para facilitar diffs no relatorio de conciliacao e em testes.
    """
    if not module_permissions or not isinstance(module_permissions, dict):
        return []

    escopos: list[str] = []
    for modulo in sorted(module_permissions.keys()):
        acoes = module_permissions[modulo]
        if not isinstance(acoes, dict):
            continue
        for acao in sorted(acoes.keys()):
            if acoes[acao] is True:
                escopos.append(f"{modulo}:{acao}")
    return escopos


def transformar_flow_permissions(flow_permissions: list[Any] | None) -> list[int]:
    """Normaliza `flow_permissions` (lista de ints) sem remapear ids.

    Replica `TenantUser.allowed_flow_ids()` da v1: entradas invalidas
    (nao conversiveis para int) sao descartadas silenciosamente.

    NOTA (decisao documentada no README): os ids de FluxoAtendimento aqui
    permanecem os ids **v1** ate a migracao da entidade 3 (tenant apps)
    rodar e popular o mapa `oraculo_fluxo_atendimento` id_v1->id_v2. O step
    de usuarios remapeia esses ids usando esse mapa quando disponivel;
    quando o mapa nao tem uma entrada (fluxo nao migrado/removido), o id
    original e preservado e a linha e sinalizada na amostra de conciliacao.
    """
    if not flow_permissions:
        return []
    resultado: list[int] = []
    for raw in flow_permissions:
        try:
            resultado.append(int(raw))
        except (TypeError, ValueError):
            continue
    return resultado


class AmostraDePara(TypedDict):
    """Uma linha da tabela de-para de RBAC (ver `montar_markdown_de_para`)."""

    tenant_slug: str
    user_id: int
    role: str
    module_permissions_original: dict[str, Any] | None
    escopos_gerados: list[str]


def montar_markdown_de_para(amostras: list[AmostraDePara]) -> str:
    """Gera o relatorio de tabela de-para de RBAC (plano, item 2: "Gere um
    relatorio de tabela de-para com uma amostra de usuarios mostrando
    module_permissions original x escopos gerados, para revisao humana").

    Funcao pura (recebe os dados ja lidos, nao acessa banco) — quem monta a
    `amostra` e o step de orquestracao (`steps/orchestrator.py::migrar_rbac`).
    """
    linhas = [
        "# RBAC — tabela de-para (module_permissions original -> escopos v2)",
        "",
        f"Amostra de {len(amostras)} usuario(s).",
        "",
        "| tenant | user_id | role | module_permissions (v1, original) | escopos gerados (v2) |",
        "|---|---|---|---|---|",
    ]
    for a in amostras:
        original_json = json.dumps(
            a["module_permissions_original"] or {}, ensure_ascii=False, sort_keys=True
        )
        escopos_str = ", ".join(a["escopos_gerados"]) or "(nenhum)"
        linhas.append(
            f"| {a['tenant_slug']} | {a['user_id']} | {a['role']} | `{original_json}` | {escopos_str} |"
        )
    return "\n".join(linhas) + "\n"


def remapear_flow_permissions(
    flow_ids_v1: list[int], mapa_fluxo_v1_para_v2: dict[int, int]
) -> tuple[list[int], list[int]]:
    """Aplica o mapa id_v1->id_v2 de FluxoAtendimento aos flow_permissions.

    Retorna `(ids_remapeados, ids_nao_encontrados)`. Ids nao encontrados no
    mapa sao preservados como estavam (best-effort) e tambem devolvidos
    separadamente para o relatorio de conciliacao.
    """
    remapeados: list[int] = []
    nao_encontrados: list[int] = []
    for fid in flow_ids_v1:
        novo = mapa_fluxo_v1_para_v2.get(fid)
        if novo is None:
            nao_encontrados.append(fid)
            remapeados.append(fid)
        else:
            remapeados.append(novo)
    return remapeados, nao_encontrados
