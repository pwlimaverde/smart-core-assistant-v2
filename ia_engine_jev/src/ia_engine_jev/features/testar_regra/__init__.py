"""Feature `TestarRegraTransferencia`: uma frase contra uma regra, antes de
ela valer. Nada é gravado — nem a frase, nem o resultado."""

from __future__ import annotations

from dataclasses import dataclass, field

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
from ia_engine_jev.jev import erro_de_dominio
from ia_engine_jev.perguntas.transferencia import pergunta_de_condicao
from ia_engine_jev.typesafe import ClienteJev, RespostaJev

_PERGUNTA = "regra"


@dataclass(frozen=True)
class ProvaDeRegraParameters(Parameters):
    frase: str
    condicao: str
    exemplos_sim: tuple[str, ...]
    exemplos_nao: tuple[str, ...]
    sensibilidade: str
    jev: ClienteJev
    limiares: Limiares = field(default_factory=Limiares)


@dataclass(frozen=True)
class ResultadoDaProva:
    probabilidade: float
    limiar: float
    dispararia: bool
    modelo: str


class ProvaDeRegraDataSource(DataSource[RespostaJev, ProvaDeRegraParameters]):
    async def __call__(self, p: ProvaDeRegraParameters) -> RespostaJev:
        return await p.jev.perguntar(
            "teste_regra",
            {"mensagem": p.frase},
            {
                _PERGUNTA: pergunta_de_condicao(
                    p.condicao, p.exemplos_sim, p.exemplos_nao
                )
            },
        )


class ProvaDeRegraRepository(
    RepositoryBase[RespostaJev, ProvaDeRegraParameters, AppError]
):
    def map_error(
        self, exception: Exception, parameters: ProvaDeRegraParameters
    ) -> AppError:
        return erro_de_dominio(exception)


class ProvaDeRegraUsecase(
    UsecaseBaseCallData[ResultadoDaProva, RespostaJev, ProvaDeRegraParameters, AppError]
):
    def process(
        self, data: RespostaJev, parameters: ProvaDeRegraParameters
    ) -> ReturnSuccessOrError[ResultadoDaProva, AppError]:
        p = data.noul(_PERGUNTA)
        limiar = parameters.limiares.limiar_noul(parameters.sensibilidade)
        return self.ok(ResultadoDaProva(p, limiar, p >= limiar, data.modelo))

    def on_unexpected(self, exception: Exception) -> AppError:
        return ErrorGeneric(message=f"{type(exception).__name__}: {exception}")


__all__ = [
    "ResultadoDaProva",
    "ProvaDeRegraDataSource",
    "ProvaDeRegraParameters",
    "ProvaDeRegraRepository",
    "ProvaDeRegraUsecase",
]
