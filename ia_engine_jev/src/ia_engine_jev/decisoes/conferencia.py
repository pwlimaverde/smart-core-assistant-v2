"""Decisão depois de redigir: a conferência do Jev → enviar, escalar ou trocar.

Padrão *cascade* da doc (extração com verificador): o modelo pequeno redige,
o Jev confere com perguntas estreitas, e só o que falhou sobe para o modelo
maior — uma vez. Falhou de novo: o que é fato (promessa, texto sem apoio) vira
a mensagem do tenant; o que é estilo sai marcado "a revisar".

Contar perguntas é código (a doc: o Jev não conta).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.domain.jev import Sinal
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.typesafe.tipos import RespostaJev

PROBLEMA_PROMETE = "promete"
PROBLEMA_TRANSFERE = "promete_transferir"
PROBLEMA_SEM_APOIO = "sem_apoio"
PROBLEMA_ECOA = "ecoa"
PROBLEMA_PROIBIDO = "pede_dado_proibido"
PROBLEMA_PERGUNTAS = "perguntas_demais"

# O que a correção diz à LLM de escalada, por problema.
CORRECOES: dict[str, str] = {
    PROBLEMA_PROMETE: (
        "Não cite preço, desconto, prazo ou entrega que não esteja na evidência."
    ),
    PROBLEMA_TRANSFERE: (
        "Não diga que vai transferir, encaminhar ou chamar alguém: isso não "
        "vai acontecer nesta mensagem."
    ),
    PROBLEMA_SEM_APOIO: (
        "Use somente o que está na evidência e nos dados da empresa; se não "
        "estiver lá, diga que não tem essa informação."
    ),
    PROBLEMA_ECOA: (
        "Não repita os dados que o cliente acabou de informar; reconheça em "
        "poucas palavras e siga."
    ),
    PROBLEMA_PROIBIDO: "Não peça ao cliente nenhum dado da lista proibida.",
    PROBLEMA_PERGUNTAS: "Faça no máximo as perguntas indicadas, nenhuma a mais.",
}

_PERGUNTA = re.compile(r"\?+")


def contar_perguntas(texto: str) -> int:
    return len(_PERGUNTA.findall(texto or ""))


@dataclass(frozen=True)
class Conferencia:
    problemas: tuple[str, ...] = ()
    apoiada: float = 1.0
    sinais: tuple[Sinal, ...] = ()


def conferir(
    resposta: RespostaJev,
    *,
    texto: str,
    exige_apoio: bool,
    limite_perguntas: int,
    limiares: Limiares,
    piso_b4: float | None = None,
) -> Conferencia:
    apoiada = resposta.noul(pc.RESPOSTA_APOIADA, 1.0)
    piso_apoio = (
        piso_b4 if piso_b4 and piso_b4 > 0 else limiares.piso_resposta_automatica
    )
    medidas = (
        (
            pc.PROMETE,
            resposta.noul(pc.PROMETE),
            limiares.promete_proibido,
            PROBLEMA_PROMETE,
        ),
        (
            pc.RESPOSTA_TRANSFERE,
            resposta.noul(pc.RESPOSTA_TRANSFERE),
            limiares.resposta_transfere,
            PROBLEMA_TRANSFERE,
        ),
        (pc.ECOA, resposta.noul(pc.ECOA), limiares.resposta_ecoa, PROBLEMA_ECOA),
        (
            pc.PEDE_PROIBIDO,
            resposta.noul(pc.PEDE_PROIBIDO),
            limiares.resposta_pede_proibido,
            PROBLEMA_PROIBIDO,
        ),
    )
    sinais = [Sinal(pc.RESPOSTA_APOIADA, apoiada, piso_apoio)]
    problemas: list[str] = []
    for nome, valor, limiar, problema in medidas:
        sinais.append(Sinal(nome, valor, limiar))
        if valor >= limiar:
            problemas.append(problema)
    if exige_apoio and apoiada < piso_apoio:
        problemas.append(PROBLEMA_SEM_APOIO)
    perguntas = contar_perguntas(texto)
    sinais.append(Sinal("perguntas", float(perguntas), float(limite_perguntas)))
    if perguntas > limite_perguntas:
        problemas.append(PROBLEMA_PERGUNTAS)
    return Conferencia(tuple(problemas), apoiada, tuple(sinais))


def desfecho(
    c: Conferencia,
    *,
    ja_escalada: bool,
    limiares: Limiares,
    sinais_cfg: SinaisTransferencia,
) -> str:
    """enviar | escalar | transferir | sem_info | a_revisar."""
    if not c.problemas:
        return "enviar"
    if not ja_escalada:
        return "escalar"
    if PROBLEMA_SEM_APOIO in c.problemas and sinais_cfg.resposta_sem_apoio.ativo:
        return "transferir"
    if PROBLEMA_PROMETE in c.problemas or (
        PROBLEMA_SEM_APOIO in c.problemas and c.apoiada < limiares.duvida_minima
    ):
        return "sem_info"
    return "a_revisar"
