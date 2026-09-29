"""Métricas da avaliação (J0) — funções puras sobre os resultados por mensagem.

Nada aqui tem texto de mensagem: cada resultado é um índice e os rótulos.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field

FAIXAS = ((0.0, 0.5), (0.5, 0.7), (0.7, 0.85), (0.85, 1.01))


@dataclass(frozen=True)
class Resultado:
    """O que o Jev decidiu para uma mensagem do conjunto, ao lado do rótulo."""

    indice: int
    intencao_esperada: str
    intencao_obtida: str
    confianca: float
    intencoes_esperadas: frozenset[str] = frozenset()
    intencoes_obtidas: frozenset[str] = frozenset()
    transfere_esperado: bool | None = None
    transfere_obtido: bool = False
    motivo: str = ""
    ato_esperado: str = ""
    ato_obtido: str = ""
    tokens: int = 0
    duracao_ms: int = 0
    erro: str = ""


@dataclass(frozen=True)
class Relatorio:
    total: int
    erros: int
    acuracia_intencao: float
    precisao_multi: float
    recall_multi: float
    precisao_transferencia: float
    recall_transferencia: float
    calibracao: tuple[tuple[str, int, float], ...]
    p95_ms: float
    tokens_por_mensagem: float
    acuracia_ato: float = 0.0
    falsos_positivos: tuple[int, ...] = field(default=())
    falsos_negativos: tuple[int, ...] = field(default=())


def _div(a: float, b: float) -> float:
    return a / b if b else 0.0


def percentil(valores: Sequence[float], p: float) -> float:
    if not valores:
        return 0.0
    ordenados = sorted(valores)
    k = max(0, min(len(ordenados) - 1, round(p * (len(ordenados) - 1))))
    return float(ordenados[k])


def calcular(resultados: Sequence[Resultado]) -> Relatorio:
    validos = [r for r in resultados if not r.erro]
    com_intencao = [r for r in validos if r.intencao_esperada]
    acertos = sum(r.intencao_obtida == r.intencao_esperada for r in com_intencao)

    vp = fp = fn = 0
    for r in validos:
        vp += len(r.intencoes_obtidas & r.intencoes_esperadas)
        fp += len(r.intencoes_obtidas - r.intencoes_esperadas)
        fn += len(r.intencoes_esperadas - r.intencoes_obtidas)

    rotulados = [r for r in validos if r.transfere_esperado is not None]
    tvp = sum(r.transfere_obtido and bool(r.transfere_esperado) for r in rotulados)
    tfp = [
        r.indice for r in rotulados if r.transfere_obtido and not r.transfere_esperado
    ]
    tfn = [
        r.indice for r in rotulados if not r.transfere_obtido and r.transfere_esperado
    ]

    com_ato = [r for r in validos if r.ato_esperado]
    acertos_ato = sum(r.ato_obtido == r.ato_esperado for r in com_ato)

    calibracao = []
    for baixo, alto in FAIXAS:
        na_faixa = [r for r in com_intencao if baixo <= r.confianca < alto]
        certos = sum(r.intencao_obtida == r.intencao_esperada for r in na_faixa)
        rotulo = f"{baixo:.2f}–{min(alto, 1.0):.2f}"
        calibracao.append((rotulo, len(na_faixa), _div(certos, len(na_faixa))))

    return Relatorio(
        total=len(resultados),
        erros=len(resultados) - len(validos),
        acuracia_intencao=_div(acertos, len(com_intencao)),
        precisao_multi=_div(vp, vp + fp),
        recall_multi=_div(vp, vp + fn),
        precisao_transferencia=_div(tvp, tvp + len(tfp)),
        recall_transferencia=_div(tvp, tvp + len(tfn)),
        calibracao=tuple(calibracao),
        p95_ms=percentil([r.duracao_ms for r in validos], 0.95),
        tokens_por_mensagem=_div(sum(r.tokens for r in validos), len(validos)),
        acuracia_ato=_div(acertos_ato, len(com_ato)),
        falsos_positivos=tuple(tfp),
        falsos_negativos=tuple(tfn),
    )


def em_markdown(variante: str, rel: Relatorio) -> str:
    linhas = [
        f"## Variante: {variante}",
        "",
        f"- Mensagens: {rel.total} (erros: {rel.erros})",
        f"- Acurácia da intenção principal: {rel.acuracia_intencao:.1%}",
        f"- Várias intenções — precisão {rel.precisao_multi:.1%}, "
        f"recall {rel.recall_multi:.1%}",
        f"- Transferência — precisão {rel.precisao_transferencia:.1%}, "
        f"recall {rel.recall_transferencia:.1%}",
        f"- Acurácia do ato (onde rotulado): {rel.acuracia_ato:.1%}",
        f"- Latência p95: {rel.p95_ms:.0f} ms",
        f"- Tokens de entrada por mensagem: {rel.tokens_por_mensagem:.0f} "
        f"(~US$ {rel.tokens_por_mensagem * 0.042 / 1_000_000:.6f})",
        "",
        "| Faixa de confiança | Mensagens | Acurácia |",
        "|---|---|---|",
        *[f"| {f} | {n} | {a:.1%} |" for f, n, a in rel.calibracao],
        "",
        f"Transferências indevidas (índices): {list(rel.falsos_positivos)}",
        f"Transferências perdidas (índices): {list(rel.falsos_negativos)}",
        "",
    ]
    return "\n".join(linhas)
