"""Decisões da resposta: antes de gerar (transfere? base responde?) e depois
(a resposta se apoia? promete demais?). Funções puras.

Regras que vêm do plano (decisões de 2026-09-28):

- transferem por padrão: pedido de humano, regras do cadastro (condição ou
  intenção) e cliente irritado; faixa de dúvida transfere por precaução;
- base sem resposta e resposta sem apoio **não** transferem por padrão: o
  cliente recebe a `msg_sem_info` do tenant no lugar de um texto sem base;
- a LLM nunca transfere sozinha: se a resposta promete transferir sem regra
  disparada, ela é gerada de novo; persistindo, sai "a revisar".
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.domain.jev import Fluxo, IntentDef, Sinal, Trecho, TrechoAvaliado
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.typesafe.tipos import RespostaJev

# Acima disto a mensagem pede informação do negócio (precisa da base).
PISO_PEDE_INFORMACAO = 0.6

MOTIVO_PEDE_HUMANO = "pede_humano"
MOTIVO_IRRITACAO = "irritacao"
MOTIVO_BASE = "base_sem_resposta"
MOTIVO_PROMETE = "promete_o_que_nao_pode"
MOTIVO_SEM_APOIO = "resposta_sem_apoio"


def motivo_de_regra(regra: RegraTransferencia) -> str:
    return f"regra:{regra.nome}"


# ----------------------------------------------------------------- trechos
def avaliar_trechos(
    julgados: Sequence[tuple[Trecho, RespostaJev]], limiares: Limiares
) -> list[TrechoAvaliado]:
    """Aprovado = relevante, responde e não instrui; conflito = relevante e
    contradiz o que o cliente supõe (vai à LLM num bloco à parte)."""
    avaliados: list[TrechoAvaliado] = []
    for trecho, r in julgados:
        instrui = r.noul(ptr.INSTRUI) >= limiares.trecho_instrui
        relevante = r.noul(ptr.RELEVANTE) >= limiares.trecho_relevante
        responde = r.noul(ptr.RESPONDE) >= limiares.trecho_responde
        contradiz = r.noul(ptr.CONTRADIZ) >= limiares.trecho_contradiz
        aprovado = relevante and responde and not instrui
        conflito = relevante and contradiz and not instrui and not aprovado
        avaliados.append(TrechoAvaliado(trecho.id, aprovado, conflito))
    return avaliados


# ------------------------------------------------------------------ antes
@dataclass(frozen=True)
class DecisaoAntes:
    transferir: bool = False
    motivo: str = ""
    regra: RegraTransferencia | None = None
    sem_info: bool = False
    sinais: tuple[Sinal, ...] = ()
    intencao: str = ""
    confianca_intencao: float = 0.0
    campos_presentes: tuple[str, ...] = field(default=())


def _regra_disparada(
    regra: RegraTransferencia,
    resposta: RespostaJev,
    intencao: str,
    confianca_intencao: float,
    limiares: Limiares,
    duvida_transfere: bool,
) -> tuple[bool, bool, Sinal]:
    """(disparou, foi pela faixa de dúvida, sinal medido)."""
    if regra.gatilho_tipo == "intencao":
        valor = confianca_intencao if intencao == regra.intencao_tag else 0.0
        return (
            valor >= limiares.piso_assunto,
            False,
            Sinal(motivo_de_regra(regra), valor, limiares.piso_assunto),
        )
    limiar = limiares.limiar_noul(regra.sensibilidade)
    p = resposta.noul(pt.id_regra(regra.id))
    sinal = Sinal(motivo_de_regra(regra), p, limiar)
    if p >= limiar:
        return True, False, sinal
    if duvida_transfere and p >= limiares.duvida_minima:
        return True, True, sinal
    return False, False, sinal


def decidir_antes(
    resposta: RespostaJev,
    *,
    regras: Sequence[RegraTransferencia],
    campos_coletados: set[str],
    trechos: Sequence[TrechoAvaliado],
    limiares: Limiares,
    sinais_cfg: SinaisTransferencia,
) -> DecisaoAntes:
    sinais: list[Sinal] = []
    escolha = resposta.escolha(pi.PRINCIPAL)
    intencao = ""
    conf_intencao = 0.0
    if escolha and escolha.escolha != pi.NENHUMA:
        intencao, conf_intencao = escolha.escolha, escolha.confianca
        sinais.append(
            Sinal(f"intencao:{intencao}", conf_intencao, limiares.piso_assunto)
        )

    candidatos: list[tuple[int, str, RegraTransferencia | None]] = []
    duvida = sinais_cfg.duvida_transfere.ativo

    # 1. Regras do cadastro — vencem os sinais automáticos: são decisão do
    #    tenant e trazem destino próprio.
    for regra in regras:
        disparou, por_duvida, sinal = _regra_disparada(
            regra, resposta, intencao, conf_intencao, limiares, duvida
        )
        sinais.append(sinal)
        if not disparou:
            continue
        if (
            regra.momento == "apos_coleta"
            and not set(regra.campos_coleta) <= campos_coletados
        ):
            # Ainda coletando: a LLM segue perguntando os campos pendentes.
            continue
        motivo = motivo_de_regra(regra)
        candidatos.append(
            (
                2 if por_duvida else 0,
                f"duvida:{motivo}" if por_duvida else motivo,
                regra,
            )
        )

    # 2. Pedido de humano.
    if sinais_cfg.pede_humano.ativo:
        limiar = limiares.limiar_noul(sinais_cfg.pede_humano.sensibilidade)
        p = resposta.noul(pt.PEDE_HUMANO)
        sinais.append(Sinal(MOTIVO_PEDE_HUMANO, p, limiar))
        if p >= limiar:
            candidatos.append((1, MOTIVO_PEDE_HUMANO, None))
        elif duvida and p >= limiares.duvida_minima:
            candidatos.append((3, f"duvida:{MOTIVO_PEDE_HUMANO}", None))

    # 3. Cliente irritado.
    if sinais_cfg.irritacao.ativo:
        nivel = resposta.nivel(pt.INSATISFACAO)
        limiar = limiares.limiar_irritacao(sinais_cfg.irritacao.sensibilidade)
        valor = nivel.valor if nivel else 0.0
        sinais.append(Sinal(MOTIVO_IRRITACAO, valor, limiar))
        if valor >= limiar:
            candidatos.append((1, MOTIVO_IRRITACAO, None))

    # 4. Base sem resposta: pede informação e nenhum trecho aprovado.
    p_info = resposta.noul(pt.PEDE_INFORMACAO)
    sinais.append(Sinal(pt.PEDE_INFORMACAO, p_info, PISO_PEDE_INFORMACAO))
    sem_info = p_info >= PISO_PEDE_INFORMACAO and not any(t.aprovado for t in trechos)
    if sem_info and sinais_cfg.base_sem_resposta.ativo:
        candidatos.append((4, MOTIVO_BASE, None))

    presentes = tuple(
        k.removeprefix("campo_presente::")
        for k, v in resposta.nouls.items()
        if k.startswith("campo_presente::") and v >= limiares.piso_entidade
    )
    if candidatos:
        _, motivo, escolhida = sorted(candidatos, key=lambda c: c[0])[0]
        return DecisaoAntes(
            True,
            motivo,
            escolhida,
            sem_info,
            tuple(sinais),
            intencao,
            conf_intencao,
            presentes,
        )
    return DecisaoAntes(
        False, "", None, sem_info, tuple(sinais), intencao, conf_intencao, presentes
    )


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


def comportamento_da_intencao(
    intencao: str, confianca: float, intents: Sequence[IntentDef], limiares: Limiares
) -> str:
    """O comportamento da intenção que o Jev escolheu (acima do piso)."""
    if not intencao or confianca < limiares.piso_assunto:
        return ""
    for i in intents:
        if i.tag == intencao:
            return i.comportamento
    return ""


# ------------------------------------------------------------------ depois
@dataclass(frozen=True)
class DecisaoDepois:
    transferir: bool = False
    motivo: str = ""
    sem_info: bool = False
    a_revisar: bool = False
    regerar: bool = False
    apoiada: float = 0.0
    sinais: tuple[Sinal, ...] = ()


def decidir_depois(
    resposta: RespostaJev,
    *,
    limiares: Limiares,
    sinais_cfg: SinaisTransferencia,
    piso_b4: float | None,
    ja_regerada: bool,
) -> DecisaoDepois:
    apoiada = resposta.noul(pc.RESPOSTA_APOIADA, 1.0)
    promete = resposta.noul(pc.PROMETE)
    transfere = resposta.noul(pc.RESPOSTA_TRANSFERE)
    piso_apoio = (
        piso_b4 if piso_b4 and piso_b4 > 0 else limiares.piso_resposta_automatica
    )
    sinais = (
        Sinal(pc.RESPOSTA_APOIADA, apoiada, piso_apoio),
        Sinal(pc.PROMETE, promete, limiares.promete_proibido),
        Sinal(pc.RESPOSTA_TRANSFERE, transfere, limiares.resposta_transfere),
    )
    if promete >= limiares.promete_proibido:
        return DecisaoDepois(True, MOTIVO_PROMETE, apoiada=apoiada, sinais=sinais)
    if apoiada < piso_apoio and sinais_cfg.resposta_sem_apoio.ativo:
        return DecisaoDepois(True, MOTIVO_SEM_APOIO, apoiada=apoiada, sinais=sinais)
    if transfere >= limiares.resposta_transfere:
        if not ja_regerada:
            return DecisaoDepois(regerar=True, apoiada=apoiada, sinais=sinais)
        return DecisaoDepois(a_revisar=True, apoiada=apoiada, sinais=sinais)
    if apoiada < limiares.duvida_minima:
        # Texto sem base nenhuma: no lugar dele, a mensagem do tenant.
        return DecisaoDepois(sem_info=True, apoiada=apoiada, sinais=sinais)
    if apoiada < piso_apoio:
        return DecisaoDepois(a_revisar=True, apoiada=apoiada, sinais=sinais)
    return DecisaoDepois(apoiada=apoiada, sinais=sinais)
