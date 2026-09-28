"""Feature `Sentimento` pelo Jev: nota (nível mais provável) e sentimento.

`feedback` é o próprio texto do cliente — o Jev não gera texto, e não há o que
resumir numa resposta de pesquisa.
"""

from __future__ import annotations

from dataclasses import dataclass

from py_return_success_or_error import (
    AppError,
    DataSource,
    ErrorGeneric,
    Parameters,
    RepositoryBase,
    ReturnSuccessOrError,
    UsecaseBaseCallData,
)

from ia_engine_jev.decisoes.analise import nota_e_sentimento
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas import sentimento as ps
from ia_engine_jev.shared.history import ChatTurnTuple
from ia_engine_jev.typesafe import ClienteJev, RespostaJev


@dataclass(frozen=True)
class SentimentoJevParameters(Parameters):
    historico: tuple[ChatTurnTuple, ...]
    jev: ClienteJev


@dataclass(frozen=True)
class AvaliacaoJev:
    nota: int
    sentimento: str
    feedback: str
    modelo: str


class SentimentoJevDataSource(DataSource[RespostaJev, SentimentoJevParameters]):
    async def __call__(self, p: SentimentoJevParameters) -> RespostaJev:
        return await p.jev.perguntar(
            "sentimento",
            ps.estado_da_avaliacao(p.historico),
            ps.perguntas_da_avaliacao(),
        )


class SentimentoJevRepository(
    RepositoryBase[RespostaJev, SentimentoJevParameters, AppError]
):
    def map_error(
        self, exception: Exception, parameters: SentimentoJevParameters
    ) -> AppError:
        return erro_de_dominio(exception)


class SentimentoJevUsecase(
    UsecaseBaseCallData[AvaliacaoJev, RespostaJev, SentimentoJevParameters, AppError]
):
    def process(
        self, data: RespostaJev, parameters: SentimentoJevParameters
    ) -> ReturnSuccessOrError[AvaliacaoJev, AppError]:
        texto = ps.ultima_do_cliente(parameters.historico)
        nota, sentimento = nota_e_sentimento(data, texto)
        return self.ok(AvaliacaoJev(nota, sentimento, texto, data.modelo))

    def on_unexpected(self, exception: Exception) -> AppError:
        return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")


__all__ = [
    "AvaliacaoJev",
    "SentimentoJevDataSource",
    "SentimentoJevParameters",
    "SentimentoJevRepository",
    "SentimentoJevUsecase",
]
