"""Feature `Responder` pelo motor Jev.

Fluxo (plano §4.2):

1. **Antes de gerar**, em paralelo: uma requisição com pedido de humano, regras
   do tenant, setor, intenção principal, irritação, pedido de informação e
   presença dos campos pendentes; e uma requisição por trecho da base.
2. **Decisão 1** (código): transfere sem chamar a LLM, ou responde a
   `msg_sem_info`, ou segue.
3. **LLM**: só o texto, com os trechos aprovados (evidência e conflito) e o
   comportamento da intenção escolhida pelo Jev. Em paralelo, a LLM pequena
   copia os campos pendentes que o Jev viu na mensagem.
4. **Depois de gerar**: resposta apoiada? promete o proibido? diz que vai
   transferir? E a conferência dos campos copiados.
5. **Decisão 2** (código): envia, transfere, troca pela `msg_sem_info`, gera de
   novo uma vez, ou marca "a revisar".

O datasource orquestra o I/O chamando as decisões puras de `decisoes/`; o
usecase monta o resultado. Falha do Jev vira erro de domínio e o `servicer`
cai no caminho de reserva (o `Responder` da LLM com schema).
"""

from __future__ import annotations

import asyncio
import json
import re
import time
from collections.abc import Callable
from dataclasses import dataclass, field
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

from ia_engine_jev.candidatos import esta_no_texto
from ia_engine_jev.config.models import RegraTransferencia
from ia_engine_jev.decisoes.limiares import Limiares, SinaisTransferencia
from ia_engine_jev.decisoes.transferencia import (
    DecisaoAntes,
    DecisaoDepois,
    avaliar_trechos,
    comportamento_da_intencao,
    decidir_antes,
    decidir_depois,
    escolher_destino,
)
from ia_engine_jev.domain.jev import DecisaoResposta, Fluxo, IntentDef, Sinal, Trecho
from ia_engine_jev.domain.models import LlmProviderSpec
from ia_engine_jev.features.responder.domain.parameters import (
    CampoColetado,
    CampoPendente,
)
from ia_engine_jev.features.responder_jev.geracao import (
    AVISO_SEM_TRANSFERENCIA,
    CHAVE_REGRAS_RESPOSTA,
    gerar_texto,
    montar_prompt_sistema,
)
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas import transferencia as pt
from ia_engine_jev.perguntas import trechos as ptr
from ia_engine_jev.perguntas.comum import estado_da_mensagem
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.shared.valor_livre import copiar_valor
from ia_engine_jev.typesafe import ClienteJev, Pergunta, PerguntaNoul, RespostaJev, Uso

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


@dataclass(frozen=True)
class ResponderJevParameters(Parameters):
    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    jev: ClienteJev
    llm: LlmProviderSpec
    fluxos: tuple[Fluxo, ...] = ()
    intents: tuple[IntentDef, ...] = ()
    trechos: tuple[Trecho, ...] = ()
    comportamento_vetor: str = ""
    campos_coletados: tuple[CampoColetado, ...] = ()
    campos_pendentes: tuple[CampoPendente, ...] = ()
    regras: tuple[RegraTransferencia, ...] = ()
    sinais: SinaisTransferencia = field(default_factory=SinaisTransferencia)
    limiares: Limiares = field(default_factory=Limiares)
    fluxo_padrao_id: int | None = None
    piso_b4: float | None = None
    dados_empresa: str = ""
    persona_bot: str = ""
    bot_agent_name: str = ""
    msg_transferencia: str = ""
    msg_sem_info: str = ""
    prompts: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class DadosResposta:
    antes: RespostaJev
    decisao_antes: DecisaoAntes
    trechos: tuple  # tuple[TrechoAvaliado, ...]
    texto: str = ""
    decisao_depois: DecisaoDepois | None = None
    regerada: bool = False
    campos: tuple[tuple[str, str, float], ...] = ()
    uso: Uso = field(default_factory=Uso)
    duracao_ms: int = 0


def perguntas_antes(p: ResponderJevParameters) -> dict[str, Pergunta]:
    perguntas: dict[str, Pergunta] = {
        pt.PEDE_HUMANO: pt.pergunta_pede_humano(),
        pt.INSATISFACAO: pt.pergunta_insatisfacao(),
        pt.PEDE_INFORMACAO: pt.pergunta_pede_informacao(),
    }
    if p.fluxos:
        perguntas[pt.SETOR] = pt.pergunta_setor(p.fluxos)
    if p.intents:
        # A mesma do `Analyse`: ele roda em paralelo e não chega a tempo.
        perguntas[pi.PRINCIPAL] = pi.pergunta_principal(p.intents)
    for regra in p.regras:
        if regra.gatilho_tipo == "condicao" and regra.condicao.strip():
            perguntas[pt.id_regra(regra.id)] = pt.pergunta_regra(regra)
    for campo in p.campos_pendentes:
        perguntas[pt.id_campo(campo.slug)] = pt.pergunta_campo(
            campo.slug, campo.nome, campo.descricao
        )
    return perguntas


class ResponderJevDataSource(DataSource[DadosResposta, ResponderJevParameters]):
    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, p: ResponderJevParameters) -> DadosResposta:
        inicio = time.perf_counter()
        estado = estado_da_mensagem(p.mensagem, p.historico, p.dados_empresa)
        pedidos = [p.jev.perguntar("antes", estado, perguntas_antes(p))]
        pedidos.extend(
            p.jev.perguntar(
                "trecho",
                ptr.estado_do_trecho(p.mensagem, p.historico, t.conteudo),
                ptr.perguntas_do_trecho(),
            )
            for t in p.trechos
        )
        respostas = list(await asyncio.gather(*pedidos))
        antes, julgamentos = respostas[0], respostas[1:]
        avaliados = tuple(
            avaliar_trechos(list(zip(p.trechos, julgamentos, strict=True)), p.limiares)
        )
        coletados = {c.slug for c in p.campos_coletados}
        d1 = decidir_antes(
            antes,
            regras=p.regras,
            campos_coletados=coletados,
            trechos=avaliados,
            limiares=p.limiares,
            sinais_cfg=p.sinais,
        )
        if d1.transferir or d1.sem_info:
            return DadosResposta(
                antes, d1, avaliados, uso=Uso.de(respostas), duracao_ms=_ms(inicio)
            )

        llm = self._chat_model_factory(p.llm)
        aprovados = {t.id for t in avaliados if t.aprovado}
        conflitos = {t.id for t in avaliados if t.conflito}
        evidencia = [t.conteudo for t in p.trechos if t.id in aprovados]
        conflito = [t.conteudo for t in p.trechos if t.id in conflitos]
        comportamento = (
            comportamento_da_intencao(
                d1.intencao, d1.confianca_intencao, p.intents, p.limiares
            )
            or p.comportamento_vetor
        )
        prompt = montar_prompt_sistema(
            nome=p.bot_agent_name,
            persona=p.persona_bot,
            regras=p.prompts.get(CHAVE_REGRAS_RESPOSTA, ""),
            comportamento=comportamento,
            dados_empresa=p.dados_empresa,
            evidencia=evidencia,
            conflito=conflito,
            coletados=[(c.nome or c.slug, c.valor) for c in p.campos_coletados],
            pendentes=[(c.nome or c.slug, c.descricao) for c in p.campos_pendentes],
        )
        pendentes = [c for c in p.campos_pendentes if c.slug in d1.campos_presentes]
        texto, valores = await asyncio.gather(
            gerar_texto(llm, prompt, p.mensagem, p.historico),
            _copiar_campos(llm, p.mensagem, pendentes),
        )
        restricoes = p.persona_bot
        depois, conferencia = await asyncio.gather(
            p.jev.perguntar(
                "depois",
                pc.estado_da_resposta(p.mensagem, texto, evidencia, restricoes),
                pc.perguntas_da_resposta(),
            ),
            _conferir_campos(p.jev, estado, pendentes, valores),
        )
        respostas.append(depois)
        if conferencia is not None:
            respostas.append(conferencia)
        d2 = decidir_depois(
            depois,
            limiares=p.limiares,
            sinais_cfg=p.sinais,
            piso_b4=p.piso_b4,
            ja_regerada=False,
        )
        regerada = False
        if d2.regerar:
            # A LLM prometeu transferir sem regra disparada: ela não decide
            # isso. Gera de novo uma vez; persistindo, "a revisar".
            regerada = True
            texto = await gerar_texto(
                llm, prompt + AVISO_SEM_TRANSFERENCIA, p.mensagem, p.historico
            )
            depois = await p.jev.perguntar(
                "depois",
                pc.estado_da_resposta(p.mensagem, texto, evidencia, restricoes),
                pc.perguntas_da_resposta(),
            )
            respostas.append(depois)
            d2 = decidir_depois(
                depois,
                limiares=p.limiares,
                sinais_cfg=p.sinais,
                piso_b4=p.piso_b4,
                ja_regerada=True,
            )
        campos = tuple(
            (slug, valor, conferencia.noul(_id_confere_campo(slug)))
            for slug, valor in valores.items()
            if conferencia is not None
            and conferencia.noul(_id_confere_campo(slug)) >= p.limiares.piso_entidade
            and esta_no_texto(_valor_visivel(valor), p.mensagem)
        )
        return DadosResposta(
            antes,
            d1,
            avaliados,
            texto=texto,
            decisao_depois=d2,
            regerada=regerada,
            campos=campos,
            uso=Uso.de(respostas),
            duracao_ms=_ms(inicio),
        )


def _ms(inicio: float) -> int:
    return int((time.perf_counter() - inicio) * 1000)


def _id_confere_campo(slug: str) -> str:
    return f"confere_campo::{slug}"


def _valor_visivel(valor: str) -> str:
    """Datas normalizadas (AAAA-MM-DD) não aparecem assim no texto: confere só
    o que é texto de verdade; números e datas ficam com a conferência do Jev."""
    return "" if any(ch.isdigit() for ch in valor) else valor


async def _copiar_campos(
    llm: BaseChatModel, mensagem: str, pendentes: list[CampoPendente]
) -> dict[str, str]:
    valores: dict[str, str] = {}
    for campo in pendentes:
        valor = await copiar_valor(
            llm,
            mensagem,
            campo.nome or campo.slug,
            f"{campo.descricao} {campo.hint}".strip(),
            _NORMALIZAR_CAMPO,
        )
        if valor:
            valores[campo.slug] = valor
    return valores


async def _conferir_campos(
    jev: ClienteJev,
    estado: dict,
    pendentes: list[CampoPendente],
    valores: dict[str, str],
) -> RespostaJev | None:
    if not valores:
        return None
    perguntas: dict[str, Pergunta] = {
        _id_confere_campo(c.slug): PerguntaNoul(
            instrucoes={
                "question": (
                    f"Is `valores.{c.slug}` what the customer states for this field "
                    "in `mensagem` (allowing only format normalization)?"
                ),
                "field": c.nome or c.slug,
                "definition": c.descricao or c.nome or c.slug,
            }
        )
        for c in pendentes
        if c.slug in valores
    }
    return await jev.perguntar("campos", {**estado, "valores": valores}, perguntas)


# --------------------------------------------------------------- usecase
class ResponderJevRepository(
    RepositoryBase[DadosResposta, ResponderJevParameters, AppError]
):
    def map_error(
        self, exception: Exception, parameters: ResponderJevParameters
    ) -> AppError:
        return erro_de_dominio(exception)


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
        d1 = data.decisao_antes
        sinais: list[Sinal] = list(d1.sinais)
        msg_transf = p.msg_transferencia.strip() or MSG_TRANSFERENCIA_GENERICA
        msg_sem_info = p.msg_sem_info.strip() or MSG_SEM_INFO_GENERICA
        comum: dict[str, Any] = {
            "trechos": data.trechos,
            "intencao_principal": d1.intencao,
            "confianca_intencao": d1.confianca_intencao,
            "modelo": data.uso.modelo,
            "tokens_entrada": data.uso.tokens_entrada,
            "requisicoes": data.uso.requisicoes,
            "duracao_ms": data.duracao_ms,
        }

        if d1.transferir:
            regra = d1.regra
            texto = (regra.mensagem.strip() if regra else "") or msg_transf
            if d1.sem_info and d1.motivo.endswith("base_sem_resposta"):
                texto = f"{msg_sem_info}\n\n{msg_transf}"
            return self.ok(
                DecisaoResposta(
                    resposta_texto=texto,
                    transferir=True,
                    fluxo_transferencia=escolher_destino(
                        regra, data.antes, p.fluxos, p.fluxo_padrao_id, p.limiares
                    ),
                    confiabilidade=0.0,
                    motivo=d1.motivo,
                    decisao="transferida",
                    sinais=tuple(sinais),
                    regra_id=regra.id if regra else 0,
                    **comum,
                )
            )
        if d1.sem_info:
            return self.ok(
                DecisaoResposta(
                    resposta_texto=msg_sem_info,
                    transferir=False,
                    fluxo_transferencia="",
                    confiabilidade=0.0,
                    motivo="",
                    decisao="sem_info",
                    sinais=tuple(sinais),
                    **comum,
                )
            )

        d2 = data.decisao_depois or DecisaoDepois(apoiada=1.0)
        sinais.extend(d2.sinais)
        campos = tuple((slug, _valor_json(v), c) for slug, v, c in data.campos)
        if d2.transferir:
            return self.ok(
                DecisaoResposta(
                    resposta_texto=msg_transf,
                    transferir=True,
                    fluxo_transferencia=escolher_destino(
                        None, data.antes, p.fluxos, p.fluxo_padrao_id, p.limiares
                    ),
                    confiabilidade=d2.apoiada,
                    motivo=d2.motivo,
                    decisao="transferida",
                    sinais=tuple(sinais),
                    regerada=data.regerada,
                    campos_extraidos=campos,
                    **comum,
                )
            )
        texto = msg_sem_info if d2.sem_info else data.texto
        decisao = (
            "sem_info"
            if d2.sem_info
            else ("a_revisar" if d2.a_revisar else "automatica")
        )
        return self.ok(
            DecisaoResposta(
                resposta_texto=texto,
                transferir=False,
                fluxo_transferencia="",
                confiabilidade=d2.apoiada,
                motivo="",
                decisao=decisao,
                sinais=tuple(sinais),
                regerada=data.regerada,
                campos_extraidos=campos,
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
    "perguntas_antes",
]
