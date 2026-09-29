"""Feature `Analyse` pelo Jev: a leitura única sem a parte da resposta.

Usada quando o bot NÃO vai responder (atendente humano na conversa, bot
desligado): intenções, entidades e tom numa requisição. A LLM pequena só entra
para entidade `livre` presente — uma chamada para todas —, e a cópia é
conferida por mais uma requisição ao Jev. Quando o bot responde, a análise
volta junto com a resposta (`Responder`), e este RPC não é chamado.
"""

from __future__ import annotations

from collections.abc import Callable
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

from ia_engine_jev.decisoes.limiares import Limiares
from ia_engine_jev.domain.jev import AnaliseJev, EntidadeDef, IntentDef
from ia_engine_jev.domain.models import LlmProviderSpec
from ia_engine_jev.features.leitura import (
    ResultadoDaLeitura,
    ler,
    livres_presentes,
    montar_analise,
)
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas import conferencia as pc
from ia_engine_jev.perguntas.leitura import PedidoDeLeitura
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.shared.valor_livre import copiar_valores
from ia_engine_jev.typesafe import ClienteJev, RespostaJev, Uso

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
    resultado: ResultadoDaLeitura
    valores: dict[str, str]
    conferencia: RespostaJev | None
    uso: Uso


class AnaliseJevDataSource(DataSource[DadosAnaliseJev, AnaliseJevParameters]):
    def __init__(self, *, chat_model_factory: ChatModelFactory) -> None:
        self._chat_model_factory = chat_model_factory

    async def __call__(self, p: AnaliseJevParameters) -> DadosAnaliseJev:
        resultado = await ler(
            PedidoDeLeitura(
                mensagem=p.mensagem,
                historico=p.historico,
                intents=p.intents,
                entidades=p.entidades,
                dados_empresa=p.dados_empresa,
                hoje=p.hoje,
            ),
            p.jev,
            p.limiares,
        )
        respostas = list(resultado.respostas)
        copiar = livres_presentes(resultado.leitura, p.entidades, (), p.limiares)
        valores: dict[str, str] = {}
        conferencia: RespostaJev | None = None
        if copiar:
            valores = await copiar_valores(
                self._chat_model_factory(p.llm), p.mensagem, copiar
            )
        if valores:
            por_chave = {c.chave: (c.nome, c.descricao) for c in copiar}
            conferencia = await p.jev.perguntar(
                "conferencia",
                pc.estado_da_resposta(p.mensagem, "", [], "", valores),
                pc.perguntas_da_resposta(
                    com_texto=False,
                    valores={k: por_chave[k] for k in valores if k in por_chave},
                ),
            )
            respostas.append(conferencia)
        return DadosAnaliseJev(resultado, valores, conferencia, Uso.de(respostas))


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
        return self.ok(
            montar_analise(
                data.resultado,
                mensagem=parameters.mensagem,
                entidades=parameters.entidades,
                valores=data.valores,
                conferencia=data.conferencia,
                limiares=parameters.limiares,
                uso=data.uso,
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
