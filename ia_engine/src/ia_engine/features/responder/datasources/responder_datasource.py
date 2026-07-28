"""Datasource da feature Responder: LLM (structured output) + embeddings.

Gera a resposta via `ChatPromptTemplate` em LCEL 1.x (prompts em português) e
calcula os vetores da pergunta/resposta/treinamento para o score do usecase.
Um output fora do contrato lança `LlmOutputInesperadoException` — traduzida
pelo repositório.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime

from langchain_core.embeddings import Embeddings
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from py_return_success_or_error import DataSource

from ia_engine.domain.models import LlmProviderSpec, RespostaBot
from ia_engine.features.responder.domain.models import ResponderData
from ia_engine.features.responder.domain.parameters import (
    CampoColetado,
    CampoPendente,
    ResponderParameters,
)
from ia_engine.llm.errors import LlmOutputInesperadoException
from ia_engine.shared.history import to_lc_messages

ChatModelFactory = Callable[[LlmProviderSpec], BaseChatModel]
EmbeddingsFactory = Callable[[LlmProviderSpec], Embeddings]


class ResponderDataSource(DataSource[ResponderData, ResponderParameters]):
    """Chamada ao LLM + geração dos vetores de similaridade."""

    def __init__(
        self,
        *,
        chat_model_factory: ChatModelFactory,
        embeddings_factory: EmbeddingsFactory,
    ) -> None:
        self._chat_model_factory = chat_model_factory
        self._embeddings_factory = embeddings_factory

    async def __call__(
        self, parameters: ResponderParameters
    ) -> ResponderData:
        llm = self._chat_model_factory(parameters.llm)
        embeddings = self._embeddings_factory(parameters.embeddings_provider)

        system_prompt = _build_system_prompt(parameters)
        prompt = ChatPromptTemplate.from_messages(
            [
                ("system", system_prompt),
                MessagesPlaceholder(variable_name="chat_history"),
                ("user", "{input}"),
            ]
        )
        chain = prompt | llm.with_structured_output(RespostaBot)
        result = await chain.ainvoke(
            {
                "chat_history": to_lc_messages(parameters.historico),
                "input": parameters.mensagem,
            }
        )

        if isinstance(result, RespostaBot):
            resposta = result
        elif isinstance(result, dict):
            resposta = RespostaBot.model_validate(result)
        else:
            raise LlmOutputInesperadoException(
                "LLM retornou tipo inesperado na geração de resposta"
            )

        response_text = str(resposta.resposta_texto).strip()
        message_vec = await embeddings.aembed_query(parameters.mensagem)
        response_vec = await embeddings.aembed_query(response_text)
        training_vec: list[float] | None = None
        if parameters.dados_treinamento and parameters.dados_treinamento.strip():
            training_vec = await embeddings.aembed_query(
                parameters.dados_treinamento
            )

        return ResponderData(
            resposta=resposta,
            message_vec=tuple(message_vec),
            response_vec=tuple(response_vec),
            training_vec=(
                tuple(training_vec) if training_vec is not None else None
            ),
        )


# Chaves de override (migration 0026); o texto no código é o default.
CHAVE_REGRAS_RESPOSTA = "PROMPT_REGRAS_RESPOSTA"
CHAVE_REGRAS_TRANSFERENCIA = "PROMPT_REGRAS_TRANSFERENCIA"

_REGRAS_PADRAO = (
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


def _build_system_prompt(parameters: ResponderParameters) -> str:
    data_atual = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    fluxos_txt = _formatar_fluxos(dict(parameters.fluxos_disponiveis))
    campos_txt = _formatar_campos(
        parameters.campos_coletados, parameters.campos_pendentes
    )
    regras = (
        parameters.prompts.get(CHAVE_REGRAS_RESPOSTA, "").strip() or _REGRAS_PADRAO
    )
    # Bloco separado na v1; sem override, as regras acima já cobrem transferência.
    transferencia = parameters.prompts.get(CHAVE_REGRAS_TRANSFERENCIA, "").strip()
    if transferencia:
        regras = f"{regras}\n{transferencia}\n"

    return (
        f"Data e Hora Atual: {data_atual}\n\n"
        f"{_identidade(parameters)}\n\n"
        f"{regras}"
        f"{fluxos_txt}"
        f"{campos_txt}\n\n"
        f"### DADOS DA EMPRESA:\n{parameters.dados_empresa}\n\n"
        f"### DADOS DO TREINAMENTO (RAG):\n{parameters.dados_treinamento}"
    )


def _identidade(parameters: ResponderParameters) -> str:
    """Quem o bot diz ser — nome e persona configurados pelo tenant.

    Até a config passar a vir do Redis, `persona_bot` e `bot_agent_name`
    existiam no banco e no painel mas não chegavam aqui: o bot se apresentava
    sempre com o texto genérico abaixo, qualquer que fosse a configuração.
    """
    nome = (parameters.bot_agent_name or "").strip()
    persona = (parameters.persona_bot or "").strip()
    linha = (
        f"Você é {nome}, assistente de atendimento ao cliente."
        if nome
        else "Você é um assistente de atendimento ao cliente."
    )
    if persona:
        linha = f"{linha}\n\n### PERSONA (siga o tom e o estilo):\n{persona}"
    return linha


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
    campos_coletados: tuple[CampoColetado, ...],
    campos_pendentes: tuple[CampoPendente, ...],
) -> str:
    partes: list[str] = []
    if campos_coletados:
        partes.append("\n\n### CAMPOS COLETADOS DO ATENDIMENTO:")
        for coletado in campos_coletados:
            nome = coletado.nome or coletado.slug or "?"
            partes.append(f"- **{nome}**: {coletado.valor}")
    if campos_pendentes:
        partes.append("\n\n### CAMPOS PENDENTES (ainda não coletados):")
        for pendente in campos_pendentes:
            nome = pendente.nome or pendente.slug or "?"
            linha = f"- **{nome}**: {pendente.descricao}"
            if pendente.hint:
                linha += f" [{pendente.hint}]"
            partes.append(linha)
        partes.append(
            "\nSe a oportunidade surgir naturalmente, colete esses dados de "
            "forma sutil e não intrusiva."
        )
    return "".join(partes)
