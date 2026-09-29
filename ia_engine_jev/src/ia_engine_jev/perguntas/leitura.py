"""A leitura única: todas as perguntas sobre a mensagem numa requisição.

Padrão *speculative fan-out* da doc: perguntas sobre o mesmo `state` vão
juntas — a resposta de cada uma não muda por estarem juntas, o `state` é cobrado
uma vez e a latência é a de uma requisição. Antes eram três (sentimento,
análise e o "antes" da resposta), com o mesmo `state`, e a intenção saía duas
vezes. As perguntas de coleta são especulativas: vão todas as de todas as
intenções, e o código usa só as da intenção escolhida.

`completa=False` é a leitura do `Analyse` (intenções, entidades e tom);
`completa=True` é a do `Responder` (mais transferência, coleta, guarda e
política).
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date
from typing import Any

from ia_engine_jev.candidatos import por_data, por_lista, por_regex
from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.domain.jev import Dado, EntidadeDef, Fluxo, IntentDef, Politica
from ia_engine_jev.perguntas import conversa as pv
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas.comum import estado_da_mensagem
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.typesafe.tipos import Pergunta


@dataclass(frozen=True)
class PedidoDeLeitura:
    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    intents: tuple[IntentDef, ...] = ()
    entidades: tuple[EntidadeDef, ...] = ()
    dados_empresa: str = ""
    hoje: date = field(default_factory=date.today)
    completa: bool = False
    regras: tuple[RegraTransferencia, ...] = ()
    fluxos: tuple[Fluxo, ...] = ()
    # Dados que alguma intenção coleta, e os já gravados no cartão (esses não
    # precisam de pergunta: o código já sabe).
    dados_coleta: tuple[Dado, ...] = ()
    ja_coletados: frozenset[str] = frozenset()
    # Campos do cartão ainda vazios: (slug, nome, descrição).
    campos_pendentes: tuple[tuple[str, str, str], ...] = ()
    politica: Politica = field(default_factory=Politica)


@dataclass(frozen=True)
class MontagemDaLeitura:
    estado: dict[str, Any]
    perguntas: dict[str, Pergunta]
    # Catálogo acima do limite do `Choice`: grupos para o segundo estágio.
    por_grupo: dict[str, list[IntentDef]] | None
    # Trecho citado → data ISO (montada em código, nunca pelo Jev).
    datas: dict[str, str]


def _entidades(
    p: PedidoDeLeitura, perguntas: dict[str, Pergunta], datas: dict[str, str]
) -> None:
    for ent in p.entidades:
        perguntas[pe.id_presenca(ent.tipo)] = pe.pergunta_presenca(ent)
        candidatos: Sequence[str] = ()
        match ent.estrategia:
            case "regex":
                candidatos = por_regex(p.mensagem, ent.opcoes)
            case "lista":
                candidatos = por_lista(p.mensagem, ent.opcoes)
            case "data":
                achadas = por_data(p.mensagem, p.hoje)
                datas.update(achadas)
                candidatos = list(achadas)
            case "varios":
                perguntas.update(pe.perguntas_varios(ent))
        if candidatos:
            perguntas[pe.id_escolha(ent.tipo)] = pe.pergunta_escolha(ent, candidatos)


def montar_leitura(p: PedidoDeLeitura) -> MontagemDaLeitura:
    perguntas: dict[str, Pergunta] = {pv.TOM: pv.pergunta_tom()}
    datas: dict[str, str] = {}
    por_grupo: dict[str, list[IntentDef]] | None = None
    if p.intents:
        if pi.precisa_de_dois_estagios(p.intents):
            por_grupo = pi.grupos(p.intents)
            perguntas[pi.GRUPO] = pi.pergunta_grupo(por_grupo)
        else:
            perguntas[pi.PRINCIPAL] = pi.pergunta_principal(p.intents)
        perguntas.update(pi.perguntas_multi(p.intents))
    _entidades(p, perguntas, datas)

    if p.completa:
        perguntas[pt.PEDE_HUMANO] = pt.pergunta_pede_humano()
        perguntas[pt.PEDE_INFORMACAO] = pt.pergunta_pede_informacao()
        perguntas[pv.INSTRUI] = pv.pergunta_instrui_bot()
        if p.fluxos:
            perguntas[pt.SETOR] = pt.pergunta_setor(p.fluxos)
        for regra in p.regras:
            if regra.gatilho_tipo == "condicao" and regra.condicao.strip():
                perguntas[pt.id_regra(regra.id)] = pt.pergunta_regra(regra)
        for slug, nome, descricao in p.campos_pendentes:
            perguntas[pt.id_campo(slug)] = pt.pergunta_campo(slug, nome, descricao)
        for dado in p.dados_coleta:
            if dado.id not in p.ja_coletados:
                perguntas[pv.id_conhecido(dado.id)] = pv.pergunta_conhecido(dado)
        if p.politica.nao_fornecemos:
            perguntas[pv.NAO_FORNECIDO] = pv.pergunta_nao_fornecido(
                p.politica.nao_fornecemos
            )

    estado = estado_da_mensagem(p.mensagem, p.historico, p.dados_empresa)
    return MontagemDaLeitura(estado, perguntas, por_grupo, datas)
