"""Valores de domínio do motor Jev (sem pydantic: `dataclass(frozen=True)`).

O `servicer` converte o proto nestes tipos; perguntas e decisões só os
conhecem — nunca o proto nem o SDK.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# O que o bot faz quando a rodada de coleta acaba.
APOS_COLETA = ("transferir", "continuar")


@dataclass(frozen=True)
class IntentDef:
    tag: str
    grupo: str = ""
    descricao: str = ""
    exemplo: str = ""
    comportamento: str = ""
    # Coleta estruturada: dados essenciais (tipo de entidade ou slug de campo
    # do cartão), quantos por mensagem, e o que fazer depois da rodada.
    campos_coleta: tuple[str, ...] = ()
    max_perguntas: int = 2
    apos_coleta: str = "transferir"


@dataclass(frozen=True)
class EntidadeDef:
    """`estrategia`: regex | lista | varios | data | livre."""

    tipo: str
    descricao: str = ""
    estrategia: str = "livre"
    opcoes: tuple[str, ...] = ()


@dataclass(frozen=True)
class Dado:
    """Um dado que o bot pode pedir ao cliente: `id` é o tipo de entidade ou o
    slug do campo do cartão; `nome` e `descricao` vão para a pergunta do Jev e
    para o prompt da LLM."""

    id: str
    nome: str
    descricao: str = ""


@dataclass(frozen=True)
class Horario:
    """Horário de atendimento humano do tenant (`jev_config.horario`).

    `dias`: 0 = segunda … 6 = domingo. Fora dele, a transferência avisa o
    cliente com `aviso`.
    """

    fuso: str = "America/Sao_Paulo"
    dias: tuple[int, ...] = (0, 1, 2, 3, 4)
    inicio_min: int = 8 * 60
    fim_min: int = 18 * 60
    aviso: str = ""


@dataclass(frozen=True)
class Politica:
    """Regras de negócio que eram texto na persona e viram decisão em código
    (`jev_config`). Vazia = nada disso é perguntado nem aplicado."""

    # O que a empresa declara NÃO fornecer, e o que oferecer no lugar.
    nao_fornecemos: tuple[str, ...] = ()
    alternativa: str = ""
    transferir_nao_fornecido: bool = True
    # Dados que o bot nunca deve pedir ao cliente (conferido na resposta).
    nunca_pedir: tuple[str, ...] = ()
    horario: Horario | None = None
    # Modelos da LLM: redação (pequeno) e escalada (maior). Vazio = o do tenant.
    modelo_redacao: str = ""
    modelo_escalada: str = ""
    # Quantos trechos da base, no máximo, entram como evidência.
    trechos_max: int = 3


@dataclass(frozen=True)
class Trecho:
    id: str
    conteudo: str
    distancia: float = 0.0


@dataclass(frozen=True)
class Sinal:
    """Um sinal que pesou na decisão: valor medido e limiar comparado."""

    nome: str
    valor: float
    limiar: float


@dataclass(frozen=True)
class TrechoAvaliado:
    id: str
    aprovado: bool
    conflito: bool
    # Probabilidade de o trecho responder à pergunta: ordena a evidência.
    responde: float = 0.0


@dataclass(frozen=True)
class Fluxo:
    """Fluxo de destino: `chave` é o "Setor - descrição" do worker."""

    chave: str
    fluxo_id: str


@dataclass(frozen=True)
class IntencaoDetectada:
    tipo: str
    confianca: float


@dataclass(frozen=True)
class EntidadeDetectada:
    tipo: str
    valor: str
    confianca: float


@dataclass(frozen=True)
class AnaliseJev:
    """Intenções, entidades e tom de uma mensagem, pela leitura do Jev."""

    intents: tuple[IntencaoDetectada, ...] = ()
    entidades: tuple[EntidadeDetectada, ...] = ()
    intent_principal: str = ""
    confianca_principal: float = 0.0
    intents_a_revisar: tuple[str, ...] = ()
    sentimento_nota: int = 0
    sentimento_label: str = ""
    modelo: str = ""
    tokens_entrada: int = 0
    requisicoes: int = 0
    duracao_ms: int = 0


@dataclass(frozen=True)
class DecisaoResposta:
    """Resultado do `Responder` pelo motor Jev."""

    resposta_texto: str
    transferir: bool
    fluxo_transferencia: str
    confiabilidade: float
    ato: str = ""
    motivo: str = ""
    decisao: str = "automatica"
    sinais: tuple[Sinal, ...] = ()
    trechos: tuple[TrechoAvaliado, ...] = ()
    intencao_principal: str = ""
    confianca_intencao: float = 0.0
    regra_id: int = 0
    campos_perguntados: tuple[str, ...] = ()
    escalada: bool = False
    problemas: tuple[str, ...] = ()
    modelo: str = ""
    modelo_llm: str = ""
    tokens_entrada: int = 0
    requisicoes: int = 0
    duracao_ms: int = 0
    etapas: tuple[tuple[str, int], ...] = ()
    campos_extraidos: tuple[tuple[str, str, float], ...] = field(default=())
    analise: AnaliseJev | None = None
