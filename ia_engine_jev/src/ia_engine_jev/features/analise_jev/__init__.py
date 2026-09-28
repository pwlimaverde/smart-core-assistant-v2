"""Feature `Analyse` pelo Jev: intenção principal, várias intenções e entidades.

FETCH (datasource): uma requisição ao Jev com todas as perguntas; um segundo
estágio quando o catálogo passa de ~240 intenções; a LLM pequena só para
entidade `livre` presente, conferida por uma requisição a mais.
PROCESS (usecase): decisão pura com os limiares do tenant.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import date

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

from ia_engine_jev.candidatos import por_data, por_lista, por_regex
from ia_engine_jev.decisoes.analise import decidir_entidades, decidir_intencoes
from ia_engine_jev.decisoes.limiares import Limiares
from ia_engine_jev.domain.jev import AnaliseJev, EntidadeDef, IntentDef
from ia_engine_jev.domain.models import LlmProviderSpec
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas import entidades as pe
from ia_engine_jev.perguntas import intencoes as pi
from ia_engine_jev.perguntas.comum import estado_da_mensagem
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.shared.valor_livre import copiar_valor
from ia_engine_jev.typesafe import ClienteJev, Escolha, Pergunta, RespostaJev, Uso

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]


@dataclass(frozen=True)
class AnaliseJevParameters(Parameters):
    mensagem: str
    historico: tuple[ChatTurnTuple, ...]
    intents: tuple[IntentDef, ...]
    entidades: tuple[EntidadeDef, ...]
    jev: ClienteJev
    llm: LlmProviderSpec
    limiares: Limiares = field(default_factory=Limiares)
    dados_empresa: str = ""
    hoje: date = field(default_factory=date.today)


@dataclass(frozen=True)
class DadosAnaliseJev:
    resposta: RespostaJev
    principal: Escolha | None
    conferencia: RespostaJev | None
    valores_livres: dict[str, str]
    datas: dict[str, str]
    uso: Uso


def _perguntas(
    p: AnaliseJevParameters, datas: dict[str, str]
) -> tuple[dict[str, Pergunta], dict[str, list[IntentDef]] | None]:
    perguntas: dict[str, Pergunta] = {}
    por_grupo: dict[str, list[IntentDef]] | None = None
    if p.intents:
        if pi.precisa_de_dois_estagios(p.intents):
            por_grupo = pi.grupos(p.intents)
            perguntas[pi.GRUPO] = pi.pergunta_grupo(por_grupo)
        else:
            perguntas[pi.PRINCIPAL] = pi.pergunta_principal(p.intents)
        perguntas.update(pi.perguntas_multi(p.intents))
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
    return perguntas, por_grupo


class AnaliseJevDataSource(DataSource[DadosAnaliseJev, AnaliseJevParameters]):
    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, p: AnaliseJevParameters) -> DadosAnaliseJev:
        datas: dict[str, str] = {}
        perguntas, por_grupo = _perguntas(p, datas)
        if not perguntas:
            return DadosAnaliseJev(RespostaJev(), None, None, {}, {}, Uso())
        estado = estado_da_mensagem(p.mensagem, p.historico, p.dados_empresa)
        resposta = await p.jev.perguntar("analise", estado, perguntas)
        respostas = [resposta]

        principal: Escolha | None = None
        if por_grupo is not None:
            grupo = resposta.escolha(pi.GRUPO)
            if grupo and grupo.escolha in por_grupo:
                segunda = await p.jev.perguntar(
                    "analise_grupo",
                    estado,
                    {pi.PRINCIPAL: pi.pergunta_principal(por_grupo[grupo.escolha])},
                )
                respostas.append(segunda)
                principal = segunda.escolha(pi.PRINCIPAL)

        # Entidade `livre`: sem candidato no código, a LLM pequena copia o
        # trecho — só quando o Jev disse que o valor está presente.
        valores: dict[str, str] = {}
        livres = [
            e
            for e in p.entidades
            if e.estrategia == "livre"
            and resposta.noul(pe.id_presenca(e.tipo)) >= p.limiares.piso_entidade
        ]
        if livres:
            llm = self._chat_model_factory(p.llm)
            for ent in livres:
                valor = await copiar_valor(llm, p.mensagem, ent.tipo, ent.descricao)
                if valor:
                    valores[ent.tipo] = valor
        conferencia: RespostaJev | None = None
        if valores:
            conferencia = await p.jev.perguntar(
                "analise_conferencia",
                {**estado, "valores": valores},
                {
                    pe.id_conferencia(e.tipo): pe.pergunta_conferencia(
                        e.tipo, e.descricao
                    )
                    for e in livres
                    if e.tipo in valores
                },
            )
            respostas.append(conferencia)
        return DadosAnaliseJev(
            resposta, principal, conferencia, valores, datas, Uso.de(respostas)
        )


class AnaliseJevRepository(
    RepositoryBase[DadosAnaliseJev, AnaliseJevParameters, AppError]
):
    def map_error(
        self, exception: Exception, parameters: AnaliseJevParameters
    ) -> AppError:
        return erro_de_dominio(exception)


class AnaliseJevUsecase(
    UsecaseBaseCallData[AnaliseJev, DadosAnaliseJev, AnaliseJevParameters, AppError]
):
    def process(
        self, data: DadosAnaliseJev, parameters: AnaliseJevParameters
    ) -> ReturnSuccessOrError[AnaliseJev, AppError]:
        aceitas, principal, conf, a_revisar = decidir_intencoes(
            data.resposta, parameters.intents, parameters.limiares, data.principal
        )
        entidades = decidir_entidades(
            data.resposta,
            parameters.mensagem,
            parameters.entidades,
            data.datas,
            data.conferencia,
            data.valores_livres,
            parameters.limiares,
        )
        return self.ok(
            AnaliseJev(
                intents=tuple(aceitas),
                entidades=tuple(entidades),
                intent_principal=principal,
                confianca_principal=conf,
                intents_a_revisar=tuple(a_revisar),
                modelo=data.uso.modelo,
                tokens_entrada=data.uso.tokens_entrada,
                requisicoes=data.uso.requisicoes,
                duracao_ms=data.uso.duracao_ms,
            )
        )

    def on_unexpected(self, exception: Exception) -> AppError:
        return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")


__all__ = [
    "AnaliseJevDataSource",
    "AnaliseJevParameters",
    "AnaliseJevRepository",
    "AnaliseJevUsecase",
    "DadosAnaliseJev",
]
