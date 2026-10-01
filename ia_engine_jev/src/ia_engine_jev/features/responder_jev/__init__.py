"""Feature `Responder` pelo motor Jev: o Jev lê, o código decide o ato, a LLM
só redige, o Jev confere.

Etapas (cada uma cronometrada e devolvida em `etapas`):

1. **leitura** — uma requisição ao Jev com todas as perguntas sobre a
   mensagem: intenções, entidades, tom, transferência, coleta, guarda de
   entrada e política (`perguntas/leitura.py`).
2. **ato** — código puro (`decisoes/ato.py`): barrada, transferir, responder,
   coletar, social ou sem_info. A regra "uma rodada de coleta" é contada com
   `rodadas_coleta`, que vem do atendimento.
3. **trechos** — só quando o ato depende da base: o Jev julga cada trecho
   (base, dados da empresa, comportamento da intenção) em paralelo, e a
   evidência é reordenada pelo `responde` dele.
4. **redacao** — a LLM pequena escreve só o ato decidido; em paralelo, copia
   os valores livres (uma chamada para todos).
5. **conferencia** — uma requisição: apoio, promessas, estilo e a cópia.
6. **escalada** — se a conferência reprovou: o modelo maior reescreve com as
   correções, e o Jev confere de novo. Reprovou outra vez: texto do tenant
   (fatos) ou "a revisar" (estilo).

`somente_decisao` (a sombra) para depois da etapa 3: sem LLM e com prioridade
baixa no limitador. Falha do Jev vira erro de domínio e o `servicer` cai na
reserva (o `Responder` da LLM com schema).
"""

from __future__ import annotations

import asyncio
import json
import re
import time
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import UTC, date, datetime
from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from py_return_success_or_error import (
    AppError,
    DataSource,
    ErrorGeneric,
    Parameters,
    RepositoryBase,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.ato import (
    CONFIAVEIS,
    TRECHO_COMPORTAMENTO,
    TRECHO_EMPRESA,
    Plano,
    aplicar_evidencia,
    fora_do_horario,
    planejar,
    texto_da_transferencia,
)
from ia_engine_jev.decisoes.conferencia import (
    CORRECOES,
    PROBLEMA_TRANSFERE,
    Conferencia,
    conferir,
    desfecho,
)
from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.decisoes.transferencia import (
    MOTIVO_COLETA,
    MOTIVO_SEM_APOIO,
    avaliar_trechos,
    escolher_destino,
    evidencia_ordenada,
)
from ia_engine_jev.domain.jev import (
    Dado,
    DecisaoResposta,
    EntidadeDef,
    Fluxo,
    IntentDef,
    Politica,
    Sinal,
    Trecho,
    TrechoAvaliado,
)
from ia_engine_jev.domain.models import LlmProviderSpec
from ia_engine_jev.features.leitura import (
    ResultadoDaLeitura,
    campos_conferidos,
    ler,
    livres_presentes,
    montar_analise,
)
from ia_engine_jev.features.responder.domain.parameters import (
    CampoColetado,
    CampoPendente,
)
from ia_engine_jev.features.responder_jev.geracao import (
    CHAVE_REGRAS_RESPOSTA,
    PedidoDeRedacao,
    gerar_texto,
    montar_prompt_sistema,
)
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.perguntas.leitura import PedidoDeLeitura
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.shared.valor_livre import CampoACopiar, copiar_valores
from ia_engine_jev.typesafe import ClienteJev, RespostaJev, Uso

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]

MSG_TRANSFERENCIA_GENERICA = (
    "Vou transferir seu atendimento para um de nossos atendentes, que poderá "
    "ajudá-lo melhor. Aguarde um momento, por favor."
)
MSG_SEM_INFO_GENERICA = (
    "Não encontrei essa informação por aqui. Pode me dar mais detalhes, ou "
    "prefere falar com um atendente?"
)
_NORMALIZAR_CAMPO = (
    "Normalize: datas em AAAA-MM-DD, números sem unidade, sim/não como true/false."
)
_LIMITE_TRECHO_EMPRESA = 4000


@dataclass(frozen=True)
class ResponderJevParameters(Parameters):
    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    jev: ClienteJev
    llm: LlmProviderSpec
    fluxos: tuple[Fluxo, ...] = ()
    intents: tuple[IntentDef, ...] = ()
    entidades: tuple[EntidadeDef, ...] = ()
    trechos: tuple[Trecho, ...] = ()
    campos_coletados: tuple[CampoColetado, ...] = ()
    campos_pendentes: tuple[CampoPendente, ...] = ()
    dados_coleta: tuple[Dado, ...] = ()
    rodadas_coleta: int = 0
    regras: tuple[RegraTransferencia, ...] = ()
    sinais: SinaisTransferencia = field(default_factory=SinaisTransferencia)
    limiares: Limiares = field(default_factory=Limiares)
    politica: Politica = field(default_factory=Politica)
    fluxo_padrao_id: int | None = None
    piso_b4: float | None = None
    dados_empresa: str = ""
    persona_bot: str = ""
    bot_agent_name: str = ""
    msg_transferencia: str = ""
    msg_sem_info: str = ""
    prompts: dict[str, str] = field(default_factory=dict)
    somente_decisao: bool = False
    hoje: date = field(default_factory=date.today)
    agora: datetime = field(default_factory=lambda: datetime.now(UTC))


@dataclass(frozen=True)
class DadosResposta:
    leitura: ResultadoDaLeitura
    plano: Plano
    trechos: tuple[TrechoAvaliado, ...] = ()
    texto: str = ""
    conferencia: Conferencia | None = None
    # enviar | a_revisar | sem_info | transferir ("" = sem LLM)
    desfecho: str = ""
    escalada: bool = False
    problemas: tuple[str, ...] = ()
    modelo_llm: str = ""
    valores: dict[str, str] = field(default_factory=dict)
    conferencia_valores: RespostaJev | None = None
    uso: Uso = field(default_factory=Uso)
    duracao_ms: int = 0
    etapas: tuple[tuple[str, int], ...] = ()


def _ms(inicio: float) -> int:
    return int((time.perf_counter() - inicio) * 1000)


def _spec(base: LlmProviderSpec, modelo: str) -> LlmProviderSpec:
    return replace(base, model=modelo) if modelo.strip() else base


def _trechos_avaliaveis(p: ResponderJevParameters, plano: Plano) -> list[Trecho]:
    """Base + dados da empresa + comportamento da intenção: os três podem
    responder, e o `sem_info` só vale se nenhum responder."""
    trechos = list(p.trechos)
    if p.dados_empresa.strip():
        trechos.append(Trecho(TRECHO_EMPRESA, p.dados_empresa[:_LIMITE_TRECHO_EMPRESA]))
    if plano.comportamento.strip():
        trechos.append(Trecho(TRECHO_COMPORTAMENTO, plano.comportamento))
    return trechos


def _pedido_de_leitura(p: ResponderJevParameters) -> PedidoDeLeitura:
    return PedidoDeLeitura(
        mensagem=p.mensagem,
        historico=p.historico,
        intents=p.intents,
        entidades=p.entidades,
        dados_empresa=p.dados_empresa,
        hoje=p.hoje,
        completa=True,
        regras=p.regras,
        fluxos=p.fluxos,
        dados_coleta=p.dados_coleta,
        ja_coletados=frozenset(c.slug for c in p.campos_coletados),
        campos_pendentes=tuple(
            (c.slug, c.nome, c.descricao) for c in p.campos_pendentes
        ),
        politica=p.politica,
    )


class ResponderJevDataSource(DataSource[DadosResposta, ResponderJevParameters]):
    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, p: ResponderJevParameters) -> DadosResposta:
        inicio = time.perf_counter()
        prioridade = "baixa" if p.somente_decisao else "alta"
        etapas: list[tuple[str, int]] = []

        # 1. Leitura.
        resultado = await ler(
            _pedido_de_leitura(p), p.jev, p.limiares, prioridade=prioridade
        )
        etapas.append(("leitura", resultado.duracao_ms))
        respostas = list(resultado.respostas)

        # 2. Ato.
        t = time.perf_counter()
        plano = planejar(
            resultado.leitura,
            regras=p.regras,
            campos_coletados=frozenset(c.slug for c in p.campos_coletados),
            rodadas_coleta=p.rodadas_coleta,
            dados={d.id: d for d in p.dados_coleta},
            politica=p.politica,
            limiares=p.limiares,
            sinais_cfg=p.sinais,
        )
        etapas.append(("ato", _ms(t)))

        # 3. Trechos (só quando o ato depende da base).
        trechos = _trechos_avaliaveis(p, plano) if plano.precisa_evidencia else []
        avaliados: tuple[TrechoAvaliado, ...] = ()
        if trechos:
            t = time.perf_counter()
            julgamentos = await asyncio.gather(
                *(
                    p.jev.perguntar(
                        "trecho",
                        ptr.estado_do_trecho(p.mensagem, p.historico, tr.conteudo),
                        ptr.perguntas_do_trecho(),
                        prioridade=prioridade,
                    )
                    for tr in trechos
                )
            )
            respostas.extend(julgamentos)
            avaliados = tuple(
                avaliar_trechos(
                    list(zip(trechos, julgamentos, strict=True)),
                    p.limiares,
                    CONFIAVEIS,
                )
            )
            plano = aplicar_evidencia(plano, avaliados, sinais_cfg=p.sinais)
            etapas.append(("trechos", _ms(t)))

        base = DadosResposta(leitura=resultado, plano=plano, trechos=avaliados)
        if p.somente_decisao:
            return replace(
                base,
                uso=Uso.de(respostas),
                duracao_ms=_ms(inicio),
                etapas=tuple(etapas),
            )

        copiar = livres_presentes(
            resultado.leitura,
            p.entidades,
            [(c.slug, c.nome, c.descricao, c.hint) for c in p.campos_pendentes],
            p.limiares,
        )
        spec_redacao = _spec(p.llm, p.politica.modelo_redacao)
        llm = self._chat_model_factory(spec_redacao)

        if not plano.usa_llm:
            # Sem texto a redigir; a cópia dos valores (para a análise e o
            # cartão) ainda acontece, com uma conferência só dela.
            valores, conf_valores = await self._copiar_e_conferir(
                p, llm, copiar, respostas, etapas
            )
            return replace(
                base,
                valores=valores,
                conferencia_valores=conf_valores,
                uso=Uso.de(respostas),
                duracao_ms=_ms(inicio),
                etapas=tuple(etapas),
            )

        # 4. Redação (+ cópia dos valores, em paralelo).
        evidencia, conflito = evidencia_ordenada(
            trechos, avaliados, p.politica.trechos_max, excluir=CONFIAVEIS
        )
        pedido = PedidoDeRedacao(
            ato=plano.ato,
            nome=p.bot_agent_name,
            persona=p.persona_bot,
            regras=p.prompts.get(CHAVE_REGRAS_RESPOSTA, ""),
            dados_empresa=p.dados_empresa,
            comportamento=plano.comportamento,
            evidencia=evidencia,
            conflito=conflito,
            coletados=[(c.nome or c.slug, c.valor) for c in p.campos_coletados],
            perguntar=plano.perguntar,
            nota_politica=plano.nota_politica,
        )
        t = time.perf_counter()
        texto, valores = await asyncio.gather(
            gerar_texto(
                llm, montar_prompt_sistema(pedido, p.agora), p.mensagem, p.historico
            ),
            copiar_valores(llm, p.mensagem, copiar, _NORMALIZAR_CAMPO),
        )
        etapas.append(("redacao", _ms(t)))

        # 5. Conferência (texto + valores copiados, numa requisição).
        evid_conferencia = [
            *evidencia,
            *([p.dados_empresa[:_LIMITE_TRECHO_EMPRESA]] if p.dados_empresa else []),
            *([plano.comportamento] if plano.comportamento else []),
        ]
        por_chave = {c.chave: (c.nome, c.descricao) for c in copiar}
        limite = max(1, len(plano.perguntar))
        t = time.perf_counter()
        conf_resp = await p.jev.perguntar(
            "conferencia",
            pc.estado_da_resposta(
                p.mensagem, texto, evid_conferencia, p.persona_bot, valores
            ),
            pc.perguntas_da_resposta(
                nunca_pedir=p.politica.nunca_pedir,
                valores={k: por_chave[k] for k in valores if k in por_chave},
            ),
            prioridade=prioridade,
        )
        respostas.append(conf_resp)
        exige_apoio = plano.ato == "responder"
        conf = conferir(
            conf_resp,
            texto=texto,
            exige_apoio=exige_apoio,
            limite_perguntas=limite,
            limiares=p.limiares,
            piso_b4=p.piso_b4,
        )
        etapas.append(("conferencia", _ms(t)))
        problemas = conf.problemas
        fim = desfecho(
            conf, ja_escalada=False, limiares=p.limiares, sinais_cfg=p.sinais
        )
        modelo_llm = spec_redacao.model
        escalada = False

        # 6. Escalada: o modelo maior reescreve com as correções.
        if fim == "escalar":
            escalada = True
            spec_escalada = _spec(p.llm, p.politica.modelo_escalada)
            modelo_llm = spec_escalada.model
            t = time.perf_counter()
            corrigido = replace(
                pedido,
                correcoes=[CORRECOES[x] for x in conf.problemas if x in CORRECOES],
            )
            texto = await gerar_texto(
                self._chat_model_factory(spec_escalada),
                montar_prompt_sistema(corrigido, p.agora),
                p.mensagem,
                p.historico,
            )
            conf_resp2 = await p.jev.perguntar(
                "conferencia_escalada",
                pc.estado_da_resposta(
                    p.mensagem, texto, evid_conferencia, p.persona_bot
                ),
                pc.perguntas_da_resposta(nunca_pedir=p.politica.nunca_pedir),
                prioridade=prioridade,
            )
            respostas.append(conf_resp2)
            conf = conferir(
                conf_resp2,
                texto=texto,
                exige_apoio=exige_apoio,
                limite_perguntas=limite,
                limiares=p.limiares,
                piso_b4=p.piso_b4,
            )
            fim = desfecho(
                conf, ja_escalada=True, limiares=p.limiares, sinais_cfg=p.sinais
            )
            etapas.append(("escalada", _ms(t)))

        return replace(
            base,
            texto=texto,
            conferencia=conf,
            desfecho=fim,
            escalada=escalada,
            problemas=problemas,
            modelo_llm=modelo_llm,
            valores=valores,
            conferencia_valores=conf_resp,
            uso=Uso.de(respostas),
            duracao_ms=_ms(inicio),
            etapas=tuple(etapas),
        )

    async def _copiar_e_conferir(
        self,
        p: ResponderJevParameters,
        llm: BaseChatModel,
        copiar: list[CampoACopiar],
        respostas: list[RespostaJev],
        etapas: list[tuple[str, int]],
    ) -> tuple[dict[str, str], RespostaJev | None]:
        if not copiar:
            return {}, None
        t = time.perf_counter()
        valores = await copiar_valores(llm, p.mensagem, copiar, _NORMALIZAR_CAMPO)
        conf: RespostaJev | None = None
        if valores:
            por_chave = {c.chave: (c.nome, c.descricao) for c in copiar}
            conf = await p.jev.perguntar(
                "conferencia",
                pc.estado_da_resposta(p.mensagem, "", [], "", valores),
                pc.perguntas_da_resposta(
                    com_texto=False,
                    valores={k: por_chave[k] for k in valores if k in por_chave},
                ),
            )
            respostas.append(conf)
        etapas.append(("copia", _ms(t)))
        return valores, conf


# --------------------------------------------------------------- usecase
class ResponderJevRepository(
    RepositoryBase[DadosResposta, ResponderJevParameters, AppError]
):
    def map_error(
        self, exception: Exception, parameters: ResponderJevParameters
    ) -> AppError:
        return erro_de_dominio(exception)


def _coleta_ja_concluida(
    plano: Plano, data: DadosResposta, efetiva: IntentDef | None
) -> bool:
    """A resposta devia pedir dados, mas insistiu em encerrar e transferir."""
    return (
        bool(plano.perguntar)
        and data.desfecho == "a_revisar"
        and data.conferencia is not None
        and PROBLEMA_TRANSFERE in data.conferencia.problemas
        and efetiva is not None
        and efetiva.apos_coleta == "transferir"
    )


def _valor_json(valor: str) -> str:
    """O valor tipado como JSON; o servidor revalida contra o catálogo."""
    v = valor.strip()
    if v.lower() in ("true", "false"):
        return v.lower()
    if re.fullmatch(r"-?\d+(?:,\d+)?", v):
        return v.replace(",", ".")
    if re.fullmatch(r"-?\d+(?:\.\d+)?", v):
        return v
    return json.dumps(v, ensure_ascii=False)


class ResponderJevUsecase(
    UsecaseBaseCallData[
        DecisaoResposta, DadosResposta, ResponderJevParameters, AppError
    ]
):
    def process(
        self, data: DadosResposta, parameters: ResponderJevParameters
    ) -> ReturnSuccessOrError[DecisaoResposta, AppError]:
        p = parameters
        plano = data.plano
        leitura = data.leitura.leitura
        msg_transf = p.msg_transferencia.strip() or MSG_TRANSFERENCIA_GENERICA
        msg_sem_info = p.msg_sem_info.strip() or MSG_SEM_INFO_GENERICA
        sinais: list[Sinal] = list(plano.sinais)
        if data.conferencia is not None:
            sinais.extend(data.conferencia.sinais)
        analise = montar_analise(
            data.leitura,
            mensagem=p.mensagem,
            entidades=p.entidades,
            valores=data.valores,
            conferencia=data.conferencia_valores,
            limiares=p.limiares,
            uso=data.uso,
        )
        campos = tuple(
            (slug, _valor_json(v), c)
            for slug, v, c in campos_conferidos(
                data.valores,
                data.conferencia_valores,
                p.mensagem,
                p.limiares.piso_entidade,
            )
        )
        comum: dict[str, Any] = {
            "ato": plano.ato,
            "trechos": data.trechos,
            "intencao_principal": leitura.principal,
            "confianca_intencao": leitura.confianca_principal,
            "modelo": data.uso.modelo,
            "modelo_llm": data.modelo_llm,
            "tokens_entrada": data.uso.tokens_entrada,
            "requisicoes": data.uso.requisicoes,
            "duracao_ms": data.duracao_ms,
            "etapas": data.etapas,
            "escalada": data.escalada,
            "problemas": data.problemas,
            "campos_extraidos": campos,
            "analise": analise,
        }

        def transferir(plano_t: Plano, confiabilidade: float = 0.0) -> DecisaoResposta:
            fora = fora_do_horario(p.agora, p.politica.horario)
            aviso = p.politica.horario.aviso if fora and p.politica.horario else ""
            if fora:
                sinais.append(Sinal("fora_do_horario", 1.0, 1.0))
            return DecisaoResposta(
                resposta_texto=texto_da_transferencia(
                    plano_t,
                    msg_transferencia=msg_transf,
                    msg_sem_info=msg_sem_info,
                    aviso_fora_do_horario=aviso,
                ),
                transferir=True,
                fluxo_transferencia=escolher_destino(
                    plano_t.regra,
                    leitura.resposta,
                    p.fluxos,
                    p.fluxo_padrao_id,
                    p.limiares,
                ),
                confiabilidade=confiabilidade,
                motivo=plano_t.motivo,
                decisao="transferida",
                sinais=tuple(sinais),
                regra_id=plano_t.regra.id if plano_t.regra else 0,
                **{**comum, "ato": "transferir"},
            )

        def simples(
            texto: str, decisao: str, ato: str, motivo: str = ""
        ) -> DecisaoResposta:
            return DecisaoResposta(
                resposta_texto=texto,
                transferir=False,
                fluxo_transferencia="",
                confiabilidade=0.0,
                motivo=motivo,
                decisao=decisao,
                sinais=tuple(sinais),
                **{**comum, "ato": ato},
            )

        match plano.ato:
            case "barrada":
                return self.ok(
                    simples(msg_sem_info, "barrada", "barrada", plano.motivo)
                )
            case "transferir":
                return self.ok(transferir(plano))
            case "sem_info":
                return self.ok(
                    simples(msg_sem_info, "sem_info", "sem_info", plano.motivo)
                )
        if p.somente_decisao:
            # Sombra: o ato é o que interessa; não houve texto nem conferência.
            return self.ok(simples("", "automatica", plano.ato))

        apoiada = data.conferencia.apoiada if data.conferencia else 1.0
        match data.desfecho:
            case "transferir":
                return self.ok(
                    transferir(replace(plano, motivo=MOTIVO_SEM_APOIO), apoiada)
                )
            case "sem_info":
                return self.ok(
                    simples(msg_sem_info, "sem_info", "sem_info", "conferencia")
                )
        if _coleta_ja_concluida(plano, data, leitura.efetiva):
            # Pedimos dados, mas a redação — duas vezes — preferiu encerrar:
            # o cliente já tinha dito o que faltava e o Jev não reconheceu.
            # A coleta acabou; vale o "depois da coleta" da intenção.
            sinais.append(Sinal("coleta_concluida_pela_redacao", 1.0, 1.0))
            return self.ok(transferir(replace(plano, motivo=MOTIVO_COLETA), apoiada))
        perguntados = tuple(d.id for d in plano.perguntar)
        return self.ok(
            DecisaoResposta(
                resposta_texto=data.texto,
                transferir=False,
                fluxo_transferencia="",
                confiabilidade=apoiada,
                decisao="a_revisar" if data.desfecho == "a_revisar" else "automatica",
                sinais=tuple(sinais),
                campos_perguntados=perguntados,
                **comum,
            )
        )

    def on_unexpected(self, exception: Exception) -> AppError:
        return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")


__all__ = [
    "MSG_SEM_INFO_GENERICA",
    "MSG_TRANSFERENCIA_GENERICA",
    "DadosResposta",
    "ResponderJevDataSource",
    "ResponderJevParameters",
    "ResponderJevRepository",
    "ResponderJevUsecase",
]
