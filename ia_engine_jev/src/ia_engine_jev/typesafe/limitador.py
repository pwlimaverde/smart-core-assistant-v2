"""Limitador de vazão das requisições ao Jev, por processo.

A conta TypeSafe tem um teto de requisições por minuto para **todos** os
tenants juntos (1.200/min no jev-1.13), e o 429 chega antes do custo. Um balde
de fichas local evita bater no teto em vez de só contar os 429 depois.

Duas prioridades:

- `alta` — a conversa com o cliente. Espera uma ficha até `espera_max_s`; se
  não vier, segue mesmo assim (o SDK trata um 429 com retry) e a espera fica
  na métrica. O cliente nunca é barrado por aqui.
- `baixa` — sombra e avaliação. Só passa se o balde tiver mais que a
  `reserva` para a conversa; senão é descartada na hora (`JevLimite`).

O teto vem de `JEV_REQ_POR_MINUTO` (padrão 1000: margem sob os 1.200 da conta).
"""

from __future__ import annotations

import asyncio
import os
import time
from dataclasses import dataclass

from loguru import logger
from opentelemetry import metrics

_SERVICE_NAME = "ia_engine_jev"
PRIORIDADES = ("alta", "baixa")


class Descartada(Exception):
    """Requisição de prioridade baixa sem folga no balde."""


@dataclass
class _Metricas:
    fila_ms: metrics.Histogram
    descartes: metrics.Counter


_metricas: _Metricas | None = None


def _obter_metricas() -> _Metricas:
    global _metricas
    if _metricas is None:
        medidor = metrics.get_meter(_SERVICE_NAME)
        _metricas = _Metricas(
            fila_ms=medidor.create_histogram(
                "smartcore_jev_fila_ms",
                unit="ms",
                description="Espera por vazão antes de uma requisição ao Jev",
            ),
            descartes=medidor.create_counter(
                "smartcore_jev_descartes_total",
                description="Requisições de prioridade baixa descartadas por vazão",
            ),
        )
    return _metricas


class Limitador:
    """Balde de fichas: `por_minuto` fichas, repostas continuamente."""

    def __init__(
        self,
        por_minuto: int,
        *,
        espera_max_s: float = 2.0,
        reserva: float = 0.2,
    ) -> None:
        self._capacidade = float(max(1, por_minuto))
        self._por_segundo = self._capacidade / 60.0
        self._fichas = self._capacidade
        self._ultimo = time.monotonic()
        self._espera_max_s = espera_max_s
        self._reserva = reserva * self._capacidade
        self._trava = asyncio.Lock()

    @property
    def capacidade(self) -> float:
        return self._capacidade

    def _repor(self) -> None:
        agora = time.monotonic()
        self._fichas = min(
            self._capacidade,
            self._fichas + (agora - self._ultimo) * self._por_segundo,
        )
        self._ultimo = agora

    async def adquirir(self, etapa: str, prioridade: str = "alta") -> float:
        """Tira uma ficha; devolve a espera em ms. `Descartada` na baixa sem folga."""
        m = _obter_metricas()
        inicio = time.perf_counter()
        async with self._trava:
            self._repor()
            if prioridade == "baixa":
                if self._fichas - 1 < self._reserva:
                    m.descartes.add(1, {"etapa": etapa})
                    raise Descartada(f"sem folga de vazão para '{etapa}'")
                self._fichas -= 1
                return 0.0
            limite = inicio + self._espera_max_s
            while self._fichas < 1 and time.perf_counter() < limite:
                falta = (1 - self._fichas) / self._por_segundo
                await asyncio.sleep(min(falta, max(0.0, limite - time.perf_counter())))
                self._repor()
            if self._fichas < 1:
                logger.warning(
                    "vazão do Jev esgotada; seguindo sem ficha",
                    etapa=etapa,
                    error_code="jev_vazao_esgotada",
                )
            self._fichas = max(0.0, self._fichas - 1)
        espera_ms = (time.perf_counter() - inicio) * 1000
        m.fila_ms.record(espera_ms, {"etapa": etapa, "prioridade": prioridade})
        return espera_ms


_limitador: Limitador | None = None


def limitador_do_processo() -> Limitador:
    """O limitador único do processo (todas as chaves e modelos dividem a conta)."""
    global _limitador
    if _limitador is None:
        try:
            por_minuto = int(os.getenv("JEV_REQ_POR_MINUTO", "1000"))
        except ValueError:
            por_minuto = 1000
        _limitador = Limitador(por_minuto)
    return _limitador
