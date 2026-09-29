"""Transferência e evidência: quem transfere, para onde, e quais trechos da
base entram na resposta. Funções puras.

Regras que vêm do plano (decisões de 2026-09-28):

- transferem por padrão: pedido de humano, regras do cadastro (condição ou
  intenção) e cliente irritado; faixa de dúvida transfere por precaução;
- base sem resposta **não** transfere por padrão: o cliente recebe a
  `msg_sem_info` do tenant no lugar de um texto sem base;
- a LLM nunca transfere sozinha (ver `decisoes/conferencia.py`).
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.leitura import Leitura
from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.domain.jev import Fluxo, Sinal, Trecho, TrechoAvaliado
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.typesafe.tipos import RespostaJev

MOTIVO_PEDE_HUMANO = "pede_humano"
MOTIVO_IRRITACAO = "irritacao"
MOTIVO_BASE = "base_sem_resposta"
MOTIVO_SEM_APOIO = "resposta_sem_apoio"
MOTIVO_NAO_FORNECIDO = "nao_fornecido"
MOTIVO_COLETA = "coleta_concluida"


def motivo_de_regra(regra: RegraTransferencia) -> str:
    return f"regra:{regra.nome}"


# ----------------------------------------------------------------- trechos
def avaliar_trechos(
    julgados: Sequence[tuple[Trecho, RespostaJev]],
    limiares: Limiares,
    confiaveis: frozenset[str] = frozenset(),
) -> list[TrechoAvaliado]:
    """Aprovado = relevante, responde e não instrui; conflito = relevante e
    contradiz o que o cliente supõe (vai à LLM num bloco à parte).

    Ordem fixa do cookbook de passagens de RAG: instrução exclui primeiro (é
    decisão de segurança), contradição antes de evidência (um trecho que nega
    a premissa do cliente também "responde", e iria para o bloco errado).

    `confiaveis`: ids de texto escrito pelo próprio tenant (dados da empresa,
    comportamento da intenção) — esses falam com o assistente de propósito, e
    a pergunta de instrução não os exclui.
    """
    avaliados: list[TrechoAvaliado] = []
    for trecho, r in julgados:
        responde_p = r.noul(ptr.RESPONDE)
        instrui = (
            trecho.id not in confiaveis
            and r.noul(ptr.INSTRUI) >= limiares.trecho_instrui
        )
        relevante = r.noul(ptr.RELEVANTE) >= limiares.trecho_relevante
        contradiz = r.noul(ptr.CONTRADIZ) >= limiares.trecho_contradiz
        responde = responde_p >= limiares.trecho_responde
        conflito = relevante and contradiz and not instrui
        aprovado = relevante and responde and not instrui and not conflito
        avaliados.append(TrechoAvaliado(trecho.id, aprovado, conflito, responde_p))
    return avaliados


def evidencia_ordenada(
    trechos: Sequence[Trecho],
    avaliados: Sequence[TrechoAvaliado],
    maximo: int,
    excluir: frozenset[str] = frozenset(),
) -> tuple[list[str], list[str]]:
    """(evidência, conflito): os aprovados reordenados pelo `responde` do Jev
    — não pela distância do vetor — até `maximo`; conflitos até 2.

    `excluir`: ids que já estão no prompt por outro caminho (os dados da
    empresa).
    """
    por_id = {t.id: t.conteudo for t in trechos}
    aprovados = sorted(
        (a for a in avaliados if a.aprovado and a.id not in excluir),
        key=lambda a: a.responde,
        reverse=True,
    )
    conflitos = [a for a in avaliados if a.conflito and a.id not in excluir]
    return (
        [por_id[a.id] for a in aprovados[:maximo] if a.id in por_id],
        [por_id[a.id] for a in conflitos[:2] if a.id in por_id],
    )


# ------------------------------------------------------------ transferir?
@dataclass(frozen=True)
class DecisaoTransferencia:
    transferir: bool = False
    motivo: str = ""
    regra: RegraTransferencia | None = None
    sinais: tuple[Sinal, ...] = ()


def _regra_disparada(
    regra: RegraTransferencia,
    leitura: Leitura,
    limiares: Limiares,
    duvida_transfere: bool,
) -> tuple[bool, bool, Sinal]:
    """(disparou, foi pela faixa de dúvida, sinal medido)."""
    if regra.gatilho_tipo == "intencao":
        valor = (
            leitura.confianca_principal
            if leitura.principal == regra.intencao_tag
            else 0.0
        )
        return (
            valor >= limiares.piso_assunto,
            False,
            Sinal(motivo_de_regra(regra), valor, limiares.piso_assunto),
        )
    limiar = limiares.limiar_noul(regra.sensibilidade)
    p = leitura.resposta.noul(pt.id_regra(regra.id))
    sinal = Sinal(motivo_de_regra(regra), p, limiar)
    if p >= limiar:
        return True, False, sinal
    if duvida_transfere and p >= limiares.duvida_minima:
        return True, True, sinal
    return False, False, sinal


def decidir_transferencia(
    leitura: Leitura,
    *,
    regras: Sequence[RegraTransferencia],
    campos_coletados: frozenset[str],
    limiares: Limiares,
    sinais_cfg: SinaisTransferencia,
) -> DecisaoTransferencia:
    """Transferência pedida pela mensagem: regras, pedido de humano, irritação.

    Precedência: regra do cadastro (é decisão do tenant e traz destino) →
    pedido de humano → irritação → faixa de dúvida.
    """
    sinais: list[Sinal] = []
    if leitura.principal:
        sinais.append(
            Sinal(
                f"intencao:{leitura.principal}",
                leitura.confianca_principal,
                limiares.piso_assunto,
            )
        )
    candidatos: list[tuple[int, str, RegraTransferencia | None]] = []
    duvida = sinais_cfg.duvida_transfere.ativo

    for regra in regras:
        disparou, por_duvida, sinal = _regra_disparada(regra, leitura, limiares, duvida)
        sinais.append(sinal)
        if not disparou:
            continue
        if (
            regra.momento == "apos_coleta"
            and not set(regra.campos_coleta) <= campos_coletados
        ):
            # Ainda coletando: a coleta do ato segue perguntando.
            continue
        motivo = motivo_de_regra(regra)
        candidatos.append(
            (
                2 if por_duvida else 0,
                f"duvida:{motivo}" if por_duvida else motivo,
                regra,
            )
        )

    if sinais_cfg.pede_humano.ativo:
        limiar = limiares.limiar_noul(sinais_cfg.pede_humano.sensibilidade)
        p = leitura.pede_humano
        sinais.append(Sinal(MOTIVO_PEDE_HUMANO, p, limiar))
        if p >= limiar:
            candidatos.append((1, MOTIVO_PEDE_HUMANO, None))
        elif duvida and p >= limiares.duvida_minima:
            candidatos.append((3, f"duvida:{MOTIVO_PEDE_HUMANO}", None))

    if sinais_cfg.irritacao.ativo:
        limiar = limiares.limiar_irritacao(sinais_cfg.irritacao.sensibilidade)
        sinais.append(Sinal(MOTIVO_IRRITACAO, leitura.irritacao, limiar))
        if leitura.irritacao >= limiar:
            candidatos.append((1, MOTIVO_IRRITACAO, None))

    if candidatos:
        _, motivo, escolhida = sorted(candidatos, key=lambda c: c[0])[0]
        return DecisaoTransferencia(True, motivo, escolhida, tuple(sinais))
    return DecisaoTransferencia(False, "", None, tuple(sinais))


def escolher_destino(
    regra: RegraTransferencia | None,
    resposta: RespostaJev,
    fluxos: Sequence[Fluxo],
    fluxo_padrao_id: int | None,
    limiares: Limiares,
) -> str:
    """Chave do fluxo de destino: regra → setor do Jev → padrão do tenant.

    Sem nenhum desses, o setor mais provável mesmo abaixo do piso, e por fim o
    primeiro fluxo: uma transferência sem destino deixaria a conversa parada
    com o cliente ouvindo que foi transferido.
    """
    if not fluxos:
        return ""
    por_id = {f.fluxo_id: f.chave for f in fluxos}
    if regra and regra.destino_tipo == "fluxo" and regra.destino_fluxo_id is not None:
        chave = por_id.get(str(regra.destino_fluxo_id))
        if chave:
            return chave
    setor = resposta.escolha(pt.SETOR)
    setor_valido = setor is not None and setor.escolha in por_id.values()
    if setor_valido and setor is not None and setor.confianca >= limiares.piso_setor:
        return setor.escolha
    if fluxo_padrao_id is not None and str(fluxo_padrao_id) in por_id:
        return por_id[str(fluxo_padrao_id)]
    if setor_valido and setor is not None:
        return setor.escolha
    return fluxos[0].chave
