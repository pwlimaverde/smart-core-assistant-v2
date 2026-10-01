"""O ato da resposta, decidido em código a partir da leitura.

"O Jev lê, o código decide o ato, a LLM só redige, o Jev confere." A LLM não
decide mais se transfere, se já perguntou o bastante nem se a base responde:

- `barrada`    — a mensagem tenta mandar no assistente (guarda de entrada);
- `transferir` — regra, pedido de humano, irritação, item não fornecido ou
  coleta concluída; texto do tenant, sem LLM;
- `responder`  — pede informação e há evidência (base, empresa ou
  comportamento); pode pedir os dados da coleta junto;
- `coletar`    — só pedir os dados essenciais que faltam, uma rodada;
- `social`     — saudação, agradecimento, conversa: resposta curta;
- `sem_info`   — pede informação e nada responde; texto do tenant.

A regra "no máximo N perguntas, uma única rodada" é contada aqui
(`rodadas_coleta` vem do atendimento), e não pela LLM lendo o histórico.
Funções puras.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.leitura import Leitura
from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.decisoes.transferencia import (
    MOTIVO_BASE,
    MOTIVO_COLETA,
    MOTIVO_NAO_FORNECIDO,
    decidir_transferencia,
)
from ia_engine_jev.domain.jev import Dado, Horario, Politica, Sinal, TrechoAvaliado

ATOS = ("transferir", "responder", "coletar", "social", "sem_info", "barrada")
MOTIVO_INSTRUI = "instrui_bot"
# Ids de trecho que não vêm da base: o texto é do próprio tenant.
TRECHO_EMPRESA = "empresa"
TRECHO_COMPORTAMENTO = "comportamento"
CONFIAVEIS = frozenset({TRECHO_EMPRESA, TRECHO_COMPORTAMENTO})


@dataclass(frozen=True)
class Plano:
    ato: str
    motivo: str = ""
    regra: RegraTransferencia | None = None
    # Dados que a resposta pede ao cliente (conta uma rodada de coleta).
    perguntar: tuple[Dado, ...] = ()
    comportamento: str = ""
    # A resposta depende da base: avaliar os trechos antes de redigir.
    precisa_evidencia: bool = False
    # Item não fornecido sem transferência: a LLM diz isso e oferece o que há.
    nota_politica: str = ""
    # Item não fornecido com transferência: texto antes da mensagem de
    # transferência (a alternativa escrita pelo tenant).
    prefixo: str = ""
    sinais: tuple[Sinal, ...] = ()

    @property
    def transferir(self) -> bool:
        return self.ato == "transferir"

    @property
    def usa_llm(self) -> bool:
        return self.ato in ("responder", "coletar", "social")


def planejar(
    leitura: Leitura,
    *,
    regras: Sequence[RegraTransferencia],
    campos_coletados: frozenset[str],
    rodadas_coleta: int,
    dados: Mapping[str, Dado],
    politica: Politica,
    limiares: Limiares,
    sinais_cfg: SinaisTransferencia,
) -> Plano:
    """O ato antes de olhar a base. `aplicar_evidencia` fecha o `responder`."""
    sinais: list[Sinal] = [
        Sinal(MOTIVO_INSTRUI, leitura.instrui, limiares.guarda_instrui)
    ]
    if leitura.instrui >= limiares.guarda_instrui:
        return Plano("barrada", MOTIVO_INSTRUI, sinais=tuple(sinais))

    transf = decidir_transferencia(
        leitura,
        regras=regras,
        campos_coletados=campos_coletados,
        limiares=limiares,
        sinais_cfg=sinais_cfg,
    )
    sinais.extend(transf.sinais)
    if transf.transferir:
        return Plano("transferir", transf.motivo, transf.regra, sinais=tuple(sinais))

    nota = ""
    if politica.nao_fornecemos:
        sinais.append(
            Sinal(
                MOTIVO_NAO_FORNECIDO,
                leitura.nao_fornecido,
                limiares.piso_nao_fornecido,
            )
        )
        if leitura.nao_fornecido >= limiares.piso_nao_fornecido:
            if politica.transferir_nao_fornecido:
                return Plano(
                    "transferir",
                    MOTIVO_NAO_FORNECIDO,
                    prefixo=politica.alternativa,
                    sinais=tuple(sinais),
                )
            nota = politica.alternativa or "Diga que a empresa não trabalha com isso."

    efetiva = leitura.efetiva
    comportamento = efetiva.comportamento if efetiva else ""
    perguntar: tuple[Dado, ...] = ()
    if efetiva is not None and efetiva.campos_coleta:
        faltando = [
            dados[i]
            for i in efetiva.campos_coleta
            if i in dados and i not in leitura.conhecidos
        ]
        sinais.append(Sinal("coleta_faltando", float(len(faltando)), 0.0))
        sinais.append(Sinal("coleta_rodadas", float(rodadas_coleta), 1.0))
        if rodadas_coleta >= 1 or not faltando:
            # Rodada feita (ou nada falta): a coleta acabou.
            if efetiva.apos_coleta == "transferir":
                return Plano(
                    "transferir",
                    MOTIVO_COLETA,
                    comportamento=comportamento,
                    sinais=tuple(sinais),
                )
        else:
            perguntar = tuple(faltando[: max(1, efetiva.max_perguntas)])

    sinais.append(
        Sinal("pede_informacao", leitura.pede_informacao, limiares.piso_pede_informacao)
    )
    if leitura.pede_informacao >= limiares.piso_pede_informacao or nota:
        return Plano(
            "responder",
            perguntar=perguntar,
            comportamento=comportamento,
            precisa_evidencia=True,
            nota_politica=nota,
            sinais=tuple(sinais),
        )
    if perguntar:
        return Plano(
            "coletar",
            perguntar=perguntar,
            comportamento=comportamento,
            sinais=tuple(sinais),
        )
    return Plano("social", comportamento=comportamento, sinais=tuple(sinais))


def aplicar_evidencia(
    plano: Plano,
    avaliados: Sequence[TrechoAvaliado],
    *,
    sinais_cfg: SinaisTransferencia,
) -> Plano:
    """Fecha o `responder`: sem trecho aprovado nem em conflito, a base não
    responde — coleta (se havia o que pedir), transferência (se o tenant ligou
    o sinal) ou `sem_info`."""
    if not plano.precisa_evidencia:
        return plano
    aprovados = sum(a.aprovado for a in avaliados)
    sinais = (*plano.sinais, Sinal("trechos_aprovados", float(aprovados), 1.0))
    if aprovados or any(a.conflito for a in avaliados) or plano.nota_politica:
        return replace(plano, sinais=sinais)
    if plano.perguntar:
        return replace(plano, ato="coletar", precisa_evidencia=False, sinais=sinais)
    if sinais_cfg.base_sem_resposta.ativo:
        return replace(
            plano,
            ato="transferir",
            motivo=MOTIVO_BASE,
            precisa_evidencia=False,
            sinais=sinais,
        )
    return replace(
        plano,
        ato="sem_info",
        motivo=MOTIVO_BASE,
        precisa_evidencia=False,
        sinais=sinais,
    )


def fora_do_horario(agora: datetime, horario: Horario | None) -> bool:
    """`agora` com fuso (UTC). Sem horário configurado: nunca fora."""
    if horario is None:
        return False
    try:
        local = agora.astimezone(ZoneInfo(horario.fuso))
    except ZoneInfoNotFoundError:
        return False
    minutos = local.hour * 60 + local.minute
    return local.weekday() not in horario.dias or not (
        horario.inicio_min <= minutos < horario.fim_min
    )


def texto_da_transferencia(
    plano: Plano,
    *,
    msg_transferencia: str,
    msg_sem_info: str,
    aviso_fora_do_horario: str = "",
    sem_info_ja_encaminha: bool = False,
) -> str:
    """Mensagem do tenant para a transferência, montada em código.

    `sem_info_ja_encaminha`: a mensagem de "não encontrei" do tenant já diz
    que vai repassar a alguém — na transferência por base sem resposta, somar
    a de transferência repetiria o encaminhamento.
    """
    base = (plano.regra.mensagem.strip() if plano.regra else "") or msg_transferencia
    partes: list[str] = []
    if plano.prefixo.strip():
        partes.append(plano.prefixo.strip())
    elif plano.motivo == MOTIVO_BASE:
        partes.append(msg_sem_info)
        if sem_info_ja_encaminha and not plano.regra:
            base = ""
    partes.append(base)
    if aviso_fora_do_horario.strip():
        partes.append(aviso_fora_do_horario.strip())
    return "\n\n".join(p for p in partes if p.strip())
