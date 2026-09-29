"""Avaliação J0 do motor Jev em português — roda no VPS, não na CI.

Uso (dentro da rede do stack, com a chave já na configuração geral):

    python -m ia_engine_jev.avaliacao.rodar \\
        --tenant <uuid> --conjunto /dados/conjunto.jsonl \\
        --catalogo /dados/catalogo.json [--catalogo-en /dados/catalogo_en.json] \\
        --saida /dados/relatorio

A chave, o modelo, as regras e os sinais vêm de `tenant:config:<uuid>` no Redis
— o mesmo caminho do serviço. O conjunto é um JSONL com, por linha:
`mensagem`, `historico` (opcional, lista de "cliente: ..."/"atendente: ..."),
`intencao` (a principal esperada, ou ""), `intencoes` (lista), `transfere`
(true/false/null), `ato` (opcional: transferir | responder | coletar | social |
sem_info | barrada) e `rodadas_coleta` (opcional, padrão 0). O `ato` medido é
o do planejamento sem a base — `responder` pode virar `sem_info` no serviço.
O catálogo é a lista de intenções
(`[{tag, grupo, descricao, exemplo, comportamento}]`, como `list_intencoes`).

Variantes: `pt` (instruções em inglês, catálogo em português — o padrão do
serviço), `tudo_pt` (instruções também em português) e `catalogo_en`
(catálogo traduzido, se `--catalogo-en`). A mensagem do cliente fica sempre em
português. A saída tem o relatório em markdown e um CSV por variante — sem
texto de mensagem, só índices e números.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import os
import time
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from ia_engine_jev.avaliacao.metricas import Resultado, calcular, em_markdown
from ia_engine_jev.config.models import RuntimeConfig
from ia_engine_jev.conversao import (
    dados_da_coleta,
    entidades_da_config,
    politica_da_config,
)
from ia_engine_jev.decisoes.ato import planejar
from ia_engine_jev.decisoes.leitura import interpretar
from ia_engine_jev.decisoes.limiares import limiares_de, sinais_de
from ia_engine_jev.domain.jev import IntentDef
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas.leitura import PedidoDeLeitura, montar_leitura
from ia_engine_jev.typesafe import (
    ClienteJev,
    Pergunta,
    PerguntaChoice,
    PerguntaNoul,
    TypeSafeJev,
)

# Instruções em português, para a variante `tudo_pt`.
INSTRUCOES_PT = {
    pi.PRINCIPAL: (
        "Qual intenção melhor descreve o que o cliente quer em `mensagem`? Use "
        "`historico` só como contexto para respostas curtas. Escolha "
        f"'{pi.NENHUMA}' quando nenhuma se aplica."
    ),
    pt.PEDE_HUMANO: (
        "O cliente em `mensagem` pede para falar com uma pessoa — atendente, "
        "vendedor, dono, ou alguém pelo nome — em vez do assistente automático?"
    ),
    "multi": "O cliente expressa esta intenção em `mensagem`?",
    "regra": "Esta condição é verdadeira para a `mensagem` do cliente?",
}


def _em_portugues(perguntas: Mapping[str, Pergunta]) -> dict[str, Pergunta]:
    traduzidas: dict[str, Pergunta] = {}
    for chave, p in perguntas.items():
        if chave in INSTRUCOES_PT and isinstance(p, PerguntaChoice):
            traduzidas[chave] = PerguntaChoice(INSTRUCOES_PT[chave], p.criterios)
        elif chave == pt.PEDE_HUMANO and isinstance(p, PerguntaNoul):
            traduzidas[chave] = PerguntaNoul(INSTRUCOES_PT[chave], p.sim, p.nao)
        elif isinstance(p, PerguntaNoul) and isinstance(p.instrucoes, dict):
            base = "multi" if chave.startswith("intencao::") else "regra"
            instrucoes = {**p.instrucoes, "question": INSTRUCOES_PT[base]}
            traduzidas[chave] = PerguntaNoul(instrucoes, p.sim, p.nao)
        else:
            traduzidas[chave] = p
    return traduzidas


def _catalogo(caminho: str) -> tuple[IntentDef, ...]:
    dados = json.loads(Path(caminho).read_text(encoding="utf-8"))
    return tuple(
        IntentDef(
            tag=str(i.get("tag", "")),
            grupo=str(i.get("grupo", "")),
            descricao=str(i.get("descricao", "")),
            exemplo=str(i.get("exemplo", "")),
            comportamento=str(i.get("comportamento", "")),
        )
        for i in dados
        if i.get("tag")
    )


async def _config(tenant: str) -> RuntimeConfig:
    from redis.asyncio import Redis

    redis = Redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"))
    try:
        bruto = await redis.get(f"tenant:config:{tenant}")
    finally:
        await redis.aclose()
    if not bruto:
        raise SystemExit(f"config não publicada para o tenant {tenant}")
    return RuntimeConfig.model_validate_json(bruto)


async def avaliar_uma(
    jev: ClienteJev,
    indice: int,
    item: dict[str, Any],
    intents: tuple[IntentDef, ...],
    config: RuntimeConfig,
    tudo_pt: bool,
) -> Resultado:
    # A mesma leitura única do serviço (Responder): o que se mede é o que roda.
    entidades = entidades_da_config(config)
    dados = dados_da_coleta(intents, entidades)
    historico = tuple(
        ("ai" if str(h).startswith("atendente:") else "human", str(h).split(":", 1)[-1])
        for h in item.get("historico", [])
    )
    montagem = montar_leitura(
        PedidoDeLeitura(
            mensagem=item["mensagem"],
            historico=historico,
            intents=intents,
            entidades=entidades,
            dados_empresa=config.dados_empresa,
            completa=True,
            regras=tuple(config.regras_transferencia),
            dados_coleta=dados,
            politica=politica_da_config(config),
        )
    )
    perguntas: dict[str, Pergunta] = dict(montagem.perguntas)
    if tudo_pt:
        perguntas = _em_portugues(perguntas)
    inicio = time.perf_counter()
    try:
        resposta = await jev.perguntar(
            "avaliacao", montagem.estado, perguntas, prioridade="baixa"
        )
    except Exception as exc:  # noqa: BLE001 — a avaliação segue sem a linha
        return Resultado(
            indice, item.get("intencao", ""), "", 0.0, erro=type(exc).__name__
        )
    duracao = int((time.perf_counter() - inicio) * 1000)
    limiares = limiares_de(config.jev_config)
    leitura = interpretar(
        resposta, intents=intents, limiares=limiares, dados_coleta=dados
    )
    plano = planejar(
        leitura,
        regras=config.regras_transferencia,
        campos_coletados=frozenset(),
        rodadas_coleta=int(item.get("rodadas_coleta", 0)),
        dados={d.id: d for d in dados},
        politica=politica_da_config(config),
        limiares=limiares,
        sinais_cfg=sinais_de(config.transferencia_sinais),
    )
    transfere = item.get("transfere")
    return Resultado(
        indice=indice,
        intencao_esperada=item.get("intencao", ""),
        intencao_obtida=leitura.principal,
        confianca=leitura.confianca_principal,
        intencoes_esperadas=frozenset(item.get("intencoes", [])),
        intencoes_obtidas=frozenset(a.tipo for a in leitura.intents),
        transfere_esperado=None if transfere is None else bool(transfere),
        transfere_obtido=plano.transferir,
        motivo=plano.motivo,
        ato_esperado=str(item.get("ato", "")),
        ato_obtido=plano.ato,
        tokens=resposta.tokens_entrada,
        duracao_ms=duracao,
    )


async def principal(args: argparse.Namespace) -> None:
    config = await _config(args.tenant)
    if not config.typesafe_api_key:
        raise SystemExit("TYPESAFE_API_KEY vazia na configuração geral")
    jev = TypeSafeJev(config.typesafe_api_key, config.jev_modelo, orcamento_s=8.0)
    conjunto = [
        json.loads(linha)
        for linha in Path(args.conjunto).read_text(encoding="utf-8").splitlines()
        if linha.strip()
    ]
    variantes: list[tuple[str, tuple[IntentDef, ...], bool]] = [
        ("pt", _catalogo(args.catalogo), False),
        ("tudo_pt", _catalogo(args.catalogo), True),
    ]
    if args.catalogo_en:
        variantes.append(("catalogo_en", _catalogo(args.catalogo_en), False))

    saida = Path(args.saida)
    saida.mkdir(parents=True, exist_ok=True)
    relatorio = [
        f"# Avaliação J0 — tenant {args.tenant}, modelo {config.jev_modelo}",
        "",
    ]
    limite = asyncio.Semaphore(args.paralelo)

    for nome, intents, tudo_pt in variantes:

        async def uma(i: int, item: dict[str, Any]) -> Resultado:
            async with limite:
                return await avaliar_uma(jev, i, item, intents, config, tudo_pt)  # noqa: B023

        resultados = await asyncio.gather(
            *(uma(i, it) for i, it in enumerate(conjunto))
        )
        relatorio.append(em_markdown(nome, calcular(resultados)))
        with (saida / f"resultados_{nome}.csv").open(
            "w", newline="", encoding="utf-8"
        ) as f:
            w = csv.writer(f)
            w.writerow(
                [
                    "indice",
                    "esperada",
                    "obtida",
                    "confianca",
                    "transfere_esperado",
                    "transfere_obtido",
                    "motivo",
                    "ato_esperado",
                    "ato_obtido",
                    "tokens",
                    "duracao_ms",
                    "erro",
                ]
            )
            for r in resultados:
                w.writerow(
                    [
                        r.indice,
                        r.intencao_esperada,
                        r.intencao_obtida,
                        f"{r.confianca:.3f}",
                        r.transfere_esperado,
                        r.transfere_obtido,
                        r.motivo,
                        r.ato_esperado,
                        r.ato_obtido,
                        r.tokens,
                        r.duracao_ms,
                        r.erro,
                    ]
                )
    (saida / "relatorio.md").write_text("\n".join(relatorio), encoding="utf-8")
    print((saida / "relatorio.md").read_text(encoding="utf-8"))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tenant", required=True)
    p.add_argument("--conjunto", required=True)
    p.add_argument("--catalogo", required=True)
    p.add_argument("--catalogo-en", default="")
    p.add_argument("--saida", default="/tmp/avaliacao_jev")
    p.add_argument("--paralelo", type=int, default=8)
    asyncio.run(principal(p.parse_args()))


if __name__ == "__main__":
    main()
