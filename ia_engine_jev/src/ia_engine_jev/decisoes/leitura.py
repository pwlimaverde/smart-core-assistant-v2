"""A leitura interpretada: respostas do Jev + limiares → fatos da mensagem.

Função pura. Junta o que antes saía de três lugares (análise, sentimento e o
"antes" da resposta) num valor só, que o `Analyse` devolve e o planejamento
do ato (`decisoes/ato.py`) consome.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from ia_engine_jev.decisoes.analise import decidir_intencoes
from ia_engine_jev.decisoes.limiares import Limiares
from ia_engine_jev.domain.jev import Dado, IntencaoDetectada, IntentDef
from ia_engine_jev.perguntas import conversa as pv
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.typesafe.tipos import Escolha, RespostaJev


@dataclass(frozen=True)
class Leitura:
    resposta: RespostaJev
    intents: tuple[IntencaoDetectada, ...] = ()
    principal: str = ""
    confianca_principal: float = 0.0
    a_revisar: tuple[str, ...] = ()
    # A intenção que conduz a resposta (comportamento e coleta). É a
    # principal, ou — com ela abaixo do piso — a mais provável do grupo que
    # passou do `piso_grupo` (sem pergunta nova: soma das probabilidades).
    efetiva: IntentDef | None = None
    efetiva_pelo_grupo: bool = False
    tom_nota: int = 0
    tom_rotulo: str = ""
    irritacao: float = 0.0
    pede_humano: float = 0.0
    pede_informacao: float = 0.0
    instrui: float = 0.0
    nao_fornecido: float = 0.0
    # Dados de coleta já conhecidos (pelo Jev ou gravados no cartão).
    conhecidos: frozenset[str] = frozenset()
    # Campos do cartão cujo valor está nesta mensagem.
    campos_presentes: tuple[str, ...] = ()


def _pelo_grupo(
    escolha: Escolha | None, intents: Sequence[IntentDef], piso_grupo: float
) -> IntentDef | None:
    """A intenção mais provável do grupo mais provável, se o grupo passou do piso.

    Receita da doc (classificação com confiança): quando a folha é incerta, o
    nível de cima costuma estar certo — e sai das mesmas probabilidades.
    """
    if escolha is None or not escolha.probabilidades:
        return None
    por_tag = {i.tag: i for i in intents}
    soma: dict[str, float] = {}
    for tag, prob in escolha.probabilidades.items():
        intent = por_tag.get(tag)
        if intent is not None and intent.grupo.strip():
            soma[intent.grupo] = soma.get(intent.grupo, 0.0) + prob
    if not soma:
        return None
    grupo, prob_grupo = max(soma.items(), key=lambda kv: kv[1])
    if prob_grupo < piso_grupo:
        return None
    candidatas = [
        (escolha.probabilidades.get(i.tag, 0.0), i) for i in intents if i.grupo == grupo
    ]
    return max(candidatas, key=lambda c: c[0])[1] if candidatas else None


def interpretar(
    resposta: RespostaJev,
    *,
    intents: Sequence[IntentDef],
    limiares: Limiares,
    principal: Escolha | None = None,
    dados_coleta: Sequence[Dado] = (),
    ja_coletados: frozenset[str] = frozenset(),
) -> Leitura:
    """`principal`: a escolha do segundo estágio (catálogo acima do limite)."""
    aceitas, nome, conf, a_revisar = decidir_intencoes(
        resposta, intents, limiares, principal
    )
    por_tag = {i.tag: i for i in intents}
    efetiva = por_tag.get(nome)
    pelo_grupo = False
    if efetiva is None:
        escolha = principal or resposta.escolha(pi.PRINCIPAL)
        efetiva = _pelo_grupo(escolha, intents, limiares.piso_grupo)
        pelo_grupo = efetiva is not None

    tom = resposta.nivel(pv.TOM)
    nota, rotulo = pv.nota_do_tom(tom)
    conhecidos = set(ja_coletados)
    for dado in dados_coleta:
        if resposta.noul(pv.id_conhecido(dado.id)) >= limiares.piso_entidade:
            conhecidos.add(dado.id)
    presentes = tuple(
        k.removeprefix("campo_presente::")
        for k, v in resposta.nouls.items()
        if k.startswith("campo_presente::") and v >= limiares.piso_entidade
    )
    return Leitura(
        resposta=resposta,
        intents=tuple(aceitas),
        principal=nome,
        confianca_principal=conf,
        a_revisar=tuple(a_revisar),
        efetiva=efetiva,
        efetiva_pelo_grupo=pelo_grupo,
        tom_nota=nota,
        tom_rotulo=rotulo,
        irritacao=pv.irritacao_do_tom(tom),
        pede_humano=resposta.noul(pt.PEDE_HUMANO),
        pede_informacao=resposta.noul(pt.PEDE_INFORMACAO),
        instrui=resposta.noul(pv.INSTRUI),
        nao_fornecido=resposta.noul(pv.NAO_FORNECIDO),
        conhecidos=frozenset(conhecidos),
        campos_presentes=presentes,
    )
