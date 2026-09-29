"""A leitura única, compartilhada pelo `Analyse` e pelo `Responder` do motor Jev.

Faz a requisição da leitura (e o segundo estágio, com catálogo acima do limite
do `Choice`), interpreta, e monta a análise da mensagem (intenções, entidades,
tom) — a mesma que o worker grava na mensagem, sem chamar o `Analyse` de novo.
"""

from __future__ import annotations

import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from ia_engine_jev.candidatos import esta_no_texto
from ia_engine_jev.decisoes.analise import decidir_entidades
from ia_engine_jev.decisoes.leitura import Leitura, interpretar
from ia_engine_jev.decisoes.limiares import Limiares
from ia_engine_jev.domain.jev import AnaliseJev, EntidadeDef
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas.leitura import (
    MontagemDaLeitura,
    PedidoDeLeitura,
    montar_leitura,
)
from ia_engine_jev.shared.valor_livre import CampoACopiar
from ia_engine_jev.typesafe import ClienteJev, RespostaJev, Uso

PREFIXO_CAMPO = "campo_"


@dataclass(frozen=True)
class ResultadoDaLeitura:
    leitura: Leitura
    montagem: MontagemDaLeitura
    respostas: tuple[RespostaJev, ...]
    duracao_ms: int


async def ler(
    pedido: PedidoDeLeitura,
    jev: ClienteJev,
    limiares: Limiares,
    *,
    prioridade: str = "alta",
) -> ResultadoDaLeitura:
    inicio = time.perf_counter()
    montagem = montar_leitura(pedido)
    resposta = await jev.perguntar(
        "leitura", montagem.estado, montagem.perguntas, prioridade=prioridade
    )
    respostas = [resposta]
    principal = None
    if montagem.por_grupo is not None:
        grupo = resposta.escolha(pi.GRUPO)
        if grupo and grupo.escolha in montagem.por_grupo:
            segunda = await jev.perguntar(
                "leitura_grupo",
                montagem.estado,
                {
                    pi.PRINCIPAL: pi.pergunta_principal(
                        montagem.por_grupo[grupo.escolha]
                    )
                },
                prioridade=prioridade,
            )
            respostas.append(segunda)
            principal = segunda.escolha(pi.PRINCIPAL)
    leitura = interpretar(
        resposta,
        intents=pedido.intents,
        limiares=limiares,
        principal=principal,
        dados_coleta=pedido.dados_coleta,
        ja_coletados=pedido.ja_coletados,
    )
    return ResultadoDaLeitura(
        leitura,
        montagem,
        tuple(respostas),
        int((time.perf_counter() - inicio) * 1000),
    )


def livres_presentes(
    leitura: Leitura,
    entidades: Sequence[EntidadeDef],
    campos_pendentes: Sequence[tuple[str, str, str, str]],
    limiares: Limiares,
) -> list[CampoACopiar]:
    """O que a LLM pequena copia da mensagem: entidades `livre` que o Jev viu
    e campos do cartão presentes. `campos_pendentes`: (slug, nome, descrição,
    dica)."""
    copiar = [
        CampoACopiar(e.tipo, e.tipo, e.descricao)
        for e in entidades
        if e.estrategia == "livre"
        and leitura.resposta.noul(pe.id_presenca(e.tipo)) >= limiares.piso_entidade
    ]
    presentes = set(leitura.campos_presentes)
    copiar.extend(
        CampoACopiar(
            f"{PREFIXO_CAMPO}{slug}", nome or slug, f"{descricao} {dica}".strip()
        )
        for slug, nome, descricao, dica in campos_pendentes
        if slug in presentes
    )
    return copiar


def montar_analise(
    resultado: ResultadoDaLeitura,
    *,
    mensagem: str,
    entidades: Sequence[EntidadeDef],
    valores: Mapping[str, str],
    conferencia: RespostaJev | None,
    limiares: Limiares,
    uso: Uso,
) -> AnaliseJev:
    """A análise da mensagem a partir da leitura (e da cópia conferida)."""
    leitura = resultado.leitura
    livres = {k: v for k, v in valores.items() if not k.startswith(PREFIXO_CAMPO)}
    achadas = decidir_entidades(
        leitura.resposta,
        mensagem,
        entidades,
        resultado.montagem.datas,
        conferencia,
        livres,
        limiares,
    )
    return AnaliseJev(
        intents=leitura.intents,
        entidades=tuple(achadas),
        intent_principal=leitura.principal,
        confianca_principal=leitura.confianca_principal,
        intents_a_revisar=leitura.a_revisar,
        sentimento_nota=leitura.tom_nota,
        sentimento_label=leitura.tom_rotulo,
        modelo=uso.modelo,
        tokens_entrada=uso.tokens_entrada,
        requisicoes=uso.requisicoes,
        duracao_ms=uso.duracao_ms,
    )


def campos_conferidos(
    valores: Mapping[str, str],
    conferencia: RespostaJev | None,
    mensagem: str,
    piso: float,
) -> list[tuple[str, str, float]]:
    """(slug, valor, confiança) dos campos do cartão que o Jev conferiu.

    Datas e números normalizados não aparecem assim no texto: o código confere
    só o que é texto de verdade; esses ficam com a conferência do Jev.
    """
    if conferencia is None:
        return []
    aceitos: list[tuple[str, str, float]] = []
    for chave, valor in valores.items():
        if not chave.startswith(PREFIXO_CAMPO):
            continue
        p = conferencia.noul(pe.id_conferencia(chave))
        if p < piso:
            continue
        tem_numero = any(ch.isdigit() for ch in valor)
        if not tem_numero and not esta_no_texto(valor, mensagem):
            continue
        aceitos.append((chave.removeprefix(PREFIXO_CAMPO), valor, p))
    return aceitos
