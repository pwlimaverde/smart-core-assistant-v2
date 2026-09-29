"""Decisão da análise: respostas do Jev + limiares → intenções e entidades.

Função pura. A regra final é nossa: o Jev dá probabilidades, o código decide
com os limiares do tenant, cada um na sua escala.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence

from ia_engine_jev.candidatos import esta_no_texto
from ia_engine_jev.decisoes.limiares import Limiares
from ia_engine_jev.domain.jev import (
    EntidadeDef,
    EntidadeDetectada,
    IntencaoDetectada,
    IntentDef,
)
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.typesafe.tipos import Escolha, RespostaJev


def decidir_intencoes(
    resposta: RespostaJev,
    intents: Sequence[IntentDef],
    limiares: Limiares,
    principal: Escolha | None = None,
) -> tuple[list[IntencaoDetectada], str, float, list[str]]:
    """(intenções aceitas, principal, confiança da principal, a revisar).

    A principal entra se o `Choice` passou do `piso_assunto`; as demais pelo
    `Noul` de cada uma, contra o `piso_etiqueta`. Entre `duvida_minima` e o
    piso: "a revisar", nunca aplicada sozinha.
    """
    escolha = principal or resposta.escolha(pi.PRINCIPAL)
    aceitas: list[IntencaoDetectada] = []
    nome_principal = ""
    conf_principal = 0.0
    if escolha and escolha.escolha != pi.NENHUMA:
        conf_principal = escolha.confianca
        if conf_principal >= limiares.piso_assunto:
            nome_principal = escolha.escolha
            aceitas.append(IntencaoDetectada(nome_principal, conf_principal))

    a_revisar: list[str] = []
    for intent in intents:
        if not intent.tag or intent.tag == nome_principal:
            continue
        p = resposta.noul(pi.id_multi(intent.tag))
        if p >= limiares.piso_etiqueta:
            aceitas.append(IntencaoDetectada(intent.tag, p))
        elif p >= limiares.duvida_minima:
            a_revisar.append(intent.tag)
    return aceitas, nome_principal, conf_principal, a_revisar


def decidir_entidades(
    resposta: RespostaJev,
    mensagem: str,
    entidades: Sequence[EntidadeDef],
    datas: Mapping[str, str],
    conferencia: RespostaJev | None,
    valores_livres: Mapping[str, str],
    limiares: Limiares,
) -> list[EntidadeDetectada]:
    """Valores aceitos, sempre copiados do texto ou da lista do tipo.

    `datas`: trecho citado → ISO (montado em código). `valores_livres`: o que a
    LLM pequena copiou, aceito só se o Jev conferir E o texto contiver o valor.
    """
    achadas: list[EntidadeDetectada] = []
    for ent in entidades:
        presente = resposta.noul(pe.id_presenca(ent.tipo))
        if presente < limiares.piso_entidade:
            continue
        match ent.estrategia:
            case "varios":
                for n, opcao in enumerate(ent.opcoes):
                    p = resposta.noul(pe.id_opcao(ent.tipo, n))
                    if p >= limiares.piso_entidade:
                        achadas.append(EntidadeDetectada(ent.tipo, opcao, p))
            case "livre":
                valor = valores_livres.get(ent.tipo, "").strip()
                if not valor or conferencia is None:
                    continue
                p = conferencia.noul(pe.id_conferencia(ent.tipo))
                if p >= limiares.piso_entidade and esta_no_texto(valor, mensagem):
                    achadas.append(EntidadeDetectada(ent.tipo, valor, p))
            case _:
                escolha = resposta.escolha(pe.id_escolha(ent.tipo))
                if escolha is None or escolha.escolha == pe.NENHUM:
                    continue
                if escolha.confianca < limiares.piso_assunto:
                    continue
                valor = escolha.escolha
                if ent.estrategia == "data":
                    valor = datas.get(valor, valor)
                achadas.append(EntidadeDetectada(ent.tipo, valor, escolha.confianca))
    return achadas
