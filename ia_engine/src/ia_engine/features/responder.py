"""Geração da resposta do bot (RPC Responder) — feature crítica.

Reescreve, em LCEL 1.x, a lógica de `FeaturesCompose.analise_mensage` da v1:
structured output `RespostaBot` + score triádico de confiabilidade
(pergunta/resposta/treinamento) + safety-net de transferência. O RAG textual já
chega resolvido em `dados_treinamento` (o worker resolve via
`data_postgres.QueryCompose` antes desta chamada).

As funções de score e de decisão de transferência são puras e testáveis sem LLM.
"""

from __future__ import annotations

import math
import re
from datetime import datetime

from langchain_core.embeddings import Embeddings
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

from ia_engine.domain.errors import ResponderError
from ia_engine.domain.models import RespostaBot, RespostaFinal
from ia_engine.features._history import ChatTurnTuple, to_lc_messages

# Limiar de confiança do LLM abaixo do qual (junto com score baixo) força
# transferência. Espelha o valor da v1 (`llm_confidence_threshold = 0.5`).
_LLM_CONFIDENCE_THRESHOLD = 0.5

_MSG_TRANSFERENCIA_GENERICA = (
    "Vou transferir seu atendimento para um de nossos atendentes, que poderá "
    "ajudá-lo melhor. Aguarde um momento, por favor."
)

# Safety-net: detecta menção de transferência no texto quando o LLM não
# preencheu `acao_transferencia` no structured output. Padrões idênticos à v1.
_TRANSFER_PATTERNS = [
    r"vou\s+(encaminhar|transferir|direcionar)",
    r"encaminhando\s+(voc[eê]|seu|sua)",
    r"transferindo\s+(voc[eê]|seu|sua)",
    r"direcionando\s+(voc[eê]|seu|sua)",
    r"vou\s+te\s+(encaminhar|transferir)",
    r"(encaminhar|transferir)\s+(voc[eê]|seu|sua)\s+(solicita|atendimento|chamado)",
]


# --------------------------------------------------------------------------- #
# Funções puras (score / transferência) — portadas matematicamente da v1.
# --------------------------------------------------------------------------- #
def calculate_embedding_similarity(
    embedding1: list[float], embedding2: list[float]
) -> float:
    """Similaridade de cosseno entre dois vetores.

    Raises:
        ValueError: dimensões diferentes, vetores vazios ou vetor zero.
    """
    if len(embedding1) != len(embedding2):
        raise ValueError(
            f"Embeddings devem ter a mesma dimensão. Recebido: "
            f"{len(embedding1)} e {len(embedding2)}"
        )
    if not embedding1 or not embedding2:
        raise ValueError("Embeddings não podem estar vazios")

    dot_product = sum(a * b for a, b in zip(embedding1, embedding2, strict=True))
    magnitude1 = math.sqrt(sum(a * a for a in embedding1))
    magnitude2 = math.sqrt(sum(b * b for b in embedding2))
    if magnitude1 == 0 or magnitude2 == 0:
        raise ValueError(
            "Não é possível calcular similaridade para vetores zero"
        )
    return dot_product / (magnitude1 * magnitude2)


def evaluate_triple_similarity(
    message_vec: list[float],
    response_vec: list[float],
    training_vec: list[float] | None = None,
) -> float:
    """Score de confiabilidade combinando pergunta/resposta/treinamento.

    - Sem `training_vec`: `max(0, min(1, 0.75 * sr))`.
    - Com `training_vec`: `base = 0.5*sr + 0.25*sq + 0.25*st`; se
      `min(sq, st) < 0.4`, subtrai `(0.4 - min(sq, st)) * 0.5`. Clamp em [0, 1].
    """
    sr = calculate_embedding_similarity(message_vec, response_vec)

    if training_vec is None:
        return max(0.0, min(1.0, 0.75 * sr))

    sq = calculate_embedding_similarity(message_vec, training_vec)
    st = calculate_embedding_similarity(response_vec, training_vec)
    base_score = 0.5 * sr + 0.25 * sq + 0.25 * st

    min_qt = min(sq, st)
    if min_qt < 0.4:
        base_score = max(0.0, base_score - (0.4 - min_qt) * 0.5)
    return max(0.0, min(1.0, base_score))


def detect_transfer_in_text(response_text: str) -> bool:
    """Safety-net: True se o texto indica transferência ativa."""
    text_lower = response_text.lower()
    return any(re.search(p, text_lower) for p in _TRANSFER_PATTERNS)


def mapear_acao_para_fluxo(
    acao_transferencia: str, fluxos_disponiveis: dict[str, str]
) -> str:
    """Casa a ação (nome de setor) contra as chaves 'Setor - descrição'.

    Match exato ou substring em qualquer direção (case-insensitive). Fallback:
    primeira chave disponível. Retorna "" se não houver fluxos.
    """
    acao_lower = acao_transferencia.lower().strip()
    for fluxo_key in fluxos_disponiveis:
        nome_setor = fluxo_key.split(" - ")[0].strip().lower()
        if (
            acao_lower == nome_setor
            or acao_lower in nome_setor
            or nome_setor in acao_lower
        ):
            return fluxo_key
    if fluxos_disponiveis:
        return next(iter(fluxos_disponiveis))
    return ""


def resolve_resposta(
    *,
    resposta: RespostaBot,
    fluxos_disponiveis: dict[str, str],
    final_score: float,
    similarity_threshold: float,
) -> RespostaFinal:
    """Decide transferência a partir do structured output + score triádico.

    Regras (idênticas à v1):
    - Transfere se o LLM indicou `acao_transferencia`, ou se o safety-net de
      regex detectou transferência no texto — independentemente do score.
    - Força transferência quando `final_score < threshold` E
      `confianca_llm < 0.5` E o LLM não indicou transferência.
    - Score baixo mas confiança alta NÃO transfere (respeita o LLM).
    """
    response_text = str(resposta.resposta_texto).strip()
    acao = resposta.acao_transferencia
    confianca_llm = resposta.confianca

    transfer_attendance = acao is not None
    fluxo_transferencia = ""

    if not transfer_attendance and response_text:
        if detect_transfer_in_text(response_text):
            transfer_attendance = True

    if transfer_attendance and acao:
        fluxo_transferencia = mapear_acao_para_fluxo(acao, fluxos_disponiveis)

    should_force_transfer = (
        final_score < similarity_threshold
        and confianca_llm < _LLM_CONFIDENCE_THRESHOLD
        and not transfer_attendance
    )
    if should_force_transfer:
        transfer_attendance = True
        response_text = f"{response_text}\n\n{_MSG_TRANSFERENCIA_GENERICA}"

    if transfer_attendance and not fluxo_transferencia and fluxos_disponiveis:
        fluxo_transferencia = next(iter(fluxos_disponiveis))

    return RespostaFinal(
        resposta_texto=response_text,
        transferir_atendimento=transfer_attendance,
        fluxo_transferencia=fluxo_transferencia,
        confiabilidade=final_score,
    )


# --------------------------------------------------------------------------- #
# Orquestração (LLM + embeddings)
# --------------------------------------------------------------------------- #
async def responder(
    *,
    mensagem: str,
    historico: list[ChatTurnTuple],
    fluxos_disponiveis: dict[str, str],
    dados_empresa: str,
    dados_treinamento: str,
    campos_coletados: list[dict[str, str]],
    campos_pendentes: list[dict[str, str]],
    similarity_threshold: float,
    llm: BaseChatModel,
    embeddings: Embeddings,
) -> RespostaFinal:
    """Gera a resposta do bot e decide transferência.

    Raises:
        ResponderError: LLM retornou tipo inesperado.
    """
    system_prompt = _build_system_prompt(
        fluxos_disponiveis=fluxos_disponiveis,
        dados_empresa=dados_empresa,
        dados_treinamento=dados_treinamento,
        campos_coletados=campos_coletados,
        campos_pendentes=campos_pendentes,
    )
    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", system_prompt),
            MessagesPlaceholder(variable_name="chat_history"),
            ("user", "{input}"),
        ]
    )
    chain = prompt | llm.with_structured_output(RespostaBot)
    result = await chain.ainvoke(
        {"chat_history": to_lc_messages(historico), "input": mensagem}
    )

    if isinstance(result, RespostaBot):
        resposta = result
    elif isinstance(result, dict):
        resposta = RespostaBot.model_validate(result)
    else:
        raise ResponderError("LLM retornou tipo inesperado na geração de resposta")

    response_text = str(resposta.resposta_texto).strip()
    message_vec = await embeddings.aembed_query(mensagem)
    response_vec = await embeddings.aembed_query(response_text)
    training_vec: list[float] | None = None
    if dados_treinamento and dados_treinamento.strip():
        training_vec = await embeddings.aembed_query(dados_treinamento)

    final_score = evaluate_triple_similarity(
        message_vec=list(message_vec),
        response_vec=list(response_vec),
        training_vec=list(training_vec) if training_vec is not None else None,
    )

    return resolve_resposta(
        resposta=resposta,
        fluxos_disponiveis=fluxos_disponiveis,
        final_score=final_score,
        similarity_threshold=similarity_threshold,
    )


def _build_system_prompt(
    *,
    fluxos_disponiveis: dict[str, str],
    dados_empresa: str,
    dados_treinamento: str,
    campos_coletados: list[dict[str, str]],
    campos_pendentes: list[dict[str, str]],
) -> str:
    data_atual = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    fluxos_txt = _formatar_fluxos(fluxos_disponiveis)
    campos_txt = _formatar_campos(campos_coletados, campos_pendentes)
    regras = (
        "### Regras de Resposta (siga rigorosamente):\n"
        "1. Analise o histórico para dar continuidade natural à conversa.\n"
        "2. Baseie a resposta nos DADOS DO TREINAMENTO (RAG) e no fluxo da "
        "conversa.\n"
        "3. Se não houver informações relevantes, seja honesto e não invente.\n"
        "4. Responda em português, de forma sóbria, organizada e educada.\n"
        "5. Se faltarem informações essenciais, peça-as em UMA ÚNICA pergunta; "
        "se o usuário não responder, transfira o atendimento.\n"
        "6. Se for necessário transferir para um setor específico, preencha "
        "'acao_transferencia' com o NOME EXATO do setor.\n"
    )
    return (
        f"Data e Hora Atual: {data_atual}\n\n"
        "Você é um assistente de atendimento ao cliente.\n\n"
        f"{regras}"
        f"{fluxos_txt}"
        f"{campos_txt}\n\n"
        f"### DADOS DA EMPRESA:\n{dados_empresa}\n\n"
        f"### DADOS DO TREINAMENTO (RAG):\n{dados_treinamento}"
    )


def _formatar_fluxos(fluxos_disponiveis: dict[str, str]) -> str:
    if not fluxos_disponiveis:
        return (
            "\n\n### SETORES DISPONÍVEIS PARA TRANSFERÊNCIA:\n"
            "Nenhum setor disponível no momento.\n"
        )
    linhas = "\n\n### SETORES DISPONÍVEIS PARA TRANSFERÊNCIA:\n"
    for key, desc in fluxos_disponiveis.items():
        linhas += f"- **{key}**: {desc}\n"
    return linhas


def _formatar_campos(
    campos_coletados: list[dict[str, str]],
    campos_pendentes: list[dict[str, str]],
) -> str:
    partes: list[str] = []
    if campos_coletados:
        partes.append("\n\n### CAMPOS COLETADOS DO ATENDIMENTO:")
        for c in campos_coletados:
            nome = c.get("nome") or c.get("slug") or "?"
            partes.append(f"- **{nome}**: {c.get('valor', '')}")
    if campos_pendentes:
        partes.append("\n\n### CAMPOS PENDENTES (ainda não coletados):")
        for c in campos_pendentes:
            nome = c.get("nome") or c.get("slug") or "?"
            linha = f"- **{nome}**: {c.get('descricao', '')}"
            if c.get("hint"):
                linha += f" [{c['hint']}]"
            partes.append(linha)
        partes.append(
            "\nSe a oportunidade surgir naturalmente, colete esses dados de "
            "forma sutil e não intrusiva."
        )
    return "".join(partes)
