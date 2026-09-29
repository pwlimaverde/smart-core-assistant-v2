"""Limiares do motor Jev, por escala, e os sinais de transferência do tenant.

Cada escala tem o seu número (a doc do jev-1.13 avisa: o limiar de um `Noul`
não vale para a confiança de um `Choice`). Os padrões abaixo são o ponto de
partida até a J0 calibrar; o tenant só vê sensibilidade (baixa · média · alta),
nunca número cru. Os valores calibrados chegam em `jev_config.pisos` e
`jev_config.sensibilidade`, publicados pelo Rust.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Any

# Sensibilidade → limiar de um `Noul` (alta = dispara mais fácil).
SENSIBILIDADE_NOUL: dict[str, float] = {"baixa": 0.9, "media": 0.8, "alta": 0.65}
# Sensibilidade → limiar de irritação (`Score` 0..2: calmo, incomodado, irritado).
SENSIBILIDADE_IRRITACAO: dict[str, float] = {"baixa": 1.8, "media": 1.5, "alta": 1.2}


@dataclass(frozen=True)
class Limiares:
    # Confiança de `Choice`.
    piso_assunto: float = 0.6
    piso_setor: float = 0.6
    # Probabilidade somada do grupo quando a intenção não passa do piso: usa
    # o comportamento e a coleta da intenção mais provável dentro dele.
    piso_grupo: float = 0.7
    # Probabilidade de `Noul`.
    piso_etiqueta: float = 0.8
    piso_entidade: float = 0.7
    # Sobre a `resposta_apoiada` (`Noul`).
    piso_resposta_automatica: float = 0.7
    # Abaixo do limiar e acima disto é a faixa de dúvida.
    duvida_minima: float = 0.4
    promete_proibido: float = 0.8
    resposta_transfere: float = 0.8
    trecho_relevante: float = 0.5
    trecho_responde: float = 0.5
    trecho_contradiz: float = 0.6
    trecho_instrui: float = 0.6
    # A mensagem pede informação do negócio (precisa da base).
    piso_pede_informacao: float = 0.6
    # Guarda de entrada: a mensagem tenta mandar no assistente.
    guarda_instrui: float = 0.85
    # O cliente pede algo que a empresa declara não fornecer.
    piso_nao_fornecido: float = 0.75
    # Conferência de estilo da resposta.
    resposta_ecoa: float = 0.8
    resposta_pede_proibido: float = 0.8
    sensibilidade_noul: dict[str, float] = field(
        default_factory=lambda: dict(SENSIBILIDADE_NOUL)
    )
    sensibilidade_irritacao: dict[str, float] = field(
        default_factory=lambda: dict(SENSIBILIDADE_IRRITACAO)
    )

    def limiar_noul(self, sensibilidade: str) -> float:
        return self.sensibilidade_noul.get(
            (sensibilidade or "media").lower(), self.sensibilidade_noul["media"]
        )

    def limiar_irritacao(self, sensibilidade: str) -> float:
        return self.sensibilidade_irritacao.get(
            (sensibilidade or "media").lower(), self.sensibilidade_irritacao["media"]
        )


@dataclass(frozen=True)
class SinalAutomatico:
    ativo: bool
    sensibilidade: str = "media"


@dataclass(frozen=True)
class SinaisTransferencia:
    """Sinais automáticos: padrões da decisão de 2026-09-28."""

    pede_humano: SinalAutomatico = SinalAutomatico(True)
    irritacao: SinalAutomatico = SinalAutomatico(True)
    duvida_transfere: SinalAutomatico = SinalAutomatico(True)
    base_sem_resposta: SinalAutomatico = SinalAutomatico(False)
    resposta_sem_apoio: SinalAutomatico = SinalAutomatico(False)


def _numero(valor: Any) -> float | None:
    try:
        n = float(valor)
    except (TypeError, ValueError):
        return None
    return n if 0.0 <= n <= 3.0 else None


def limiares_de(jev_config: dict[str, Any] | None) -> Limiares:
    """Limiares com os pisos calibrados do tenant sobre os padrões.

    Chave desconhecida ou número fora de faixa é ignorado: um valor torto na
    config não pode desligar a decisão (0 aceitaria tudo).
    """
    base = Limiares()
    if not isinstance(jev_config, dict):
        return base
    pisos = jev_config.get("pisos")
    mudancas: dict[str, Any] = {}
    if isinstance(pisos, dict):
        for nome, valor in pisos.items():
            n = _numero(valor)
            conhecido = nome in Limiares.__dataclass_fields__
            if n is not None and conhecido and not nome.startswith("sensib"):
                mudancas[nome] = n
    sens = jev_config.get("sensibilidade")
    if isinstance(sens, dict):
        noul = dict(base.sensibilidade_noul)
        for nivel, valor in sens.items():
            n = _numero(valor)
            if nivel in noul and n is not None and n <= 1.0:
                noul[nivel] = n
        mudancas["sensibilidade_noul"] = noul
    return replace(base, **mudancas) if mudancas else base


def sinais_de(config: dict[str, Any] | None) -> SinaisTransferencia:
    """Sinais do tenant (`transferencia_sinais`), com os padrões onde faltar."""
    padrao = SinaisTransferencia()
    if not isinstance(config, dict):
        return padrao

    def ler(nome: str, atual: SinalAutomatico) -> SinalAutomatico:
        bruto = config.get(nome)
        if isinstance(bruto, bool):
            return SinalAutomatico(bruto, atual.sensibilidade)
        if not isinstance(bruto, dict):
            return atual
        ativo = bruto.get("ativo", atual.ativo)
        sens = str(bruto.get("sensibilidade", atual.sensibilidade) or "media")
        return SinalAutomatico(
            bool(ativo), sens if sens in SENSIBILIDADE_NOUL else "media"
        )

    return SinaisTransferencia(
        pede_humano=ler("pede_humano", padrao.pede_humano),
        irritacao=ler("irritacao", padrao.irritacao),
        duvida_transfere=ler("duvida_transfere", padrao.duvida_transfere),
        base_sem_resposta=ler("base_sem_resposta", padrao.base_sem_resposta),
        resposta_sem_apoio=ler("resposta_sem_apoio", padrao.resposta_sem_apoio),
    )
