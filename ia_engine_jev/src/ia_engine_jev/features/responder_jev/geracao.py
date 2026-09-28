"""Prompt da LLM no motor Jev: ela só escreve o texto.

Sem schema, sem setor, sem confiança e sem regras de transferência — quem
decide é o código com os sinais do Jev. A LLM recebe só os trechos aprovados,
em dois blocos: evidência (responde à pergunta) e conflito (contradiz o que o
cliente supõe, para corrigir com educação).
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

from ia_engine_jev.shared.history import ChatTurnTuple, to_lc_messages

CHAVE_REGRAS_RESPOSTA = "PROMPT_REGRAS_RESPOSTA_JEV"

_REGRAS_PADRAO = (
    "### Regras de resposta (siga rigorosamente):\n"
    "1. Dê continuidade natural à conversa, usando o histórico.\n"
    "2. Use SÓ as informações da EVIDÊNCIA e dos DADOS DA EMPRESA. Não invente "
    "preço, prazo, desconto nem condição.\n"
    "3. Se a evidência não cobre a pergunta, diga com honestidade que não tem "
    "essa informação.\n"
    "4. Responda em português, de forma sóbria, organizada e educada.\n"
    "5. Se faltar um dado essencial do cliente, peça-o em UMA pergunta.\n"
    "6. Nunca diga que vai transferir, encaminhar ou chamar alguém: isso não é "
    "decisão sua.\n"
)

AVISO_SEM_TRANSFERENCIA = (
    "\n\nATENÇÃO: a resposta anterior dizia que o atendimento seria transferido. "
    "Isso não vai acontecer. Responda sem mencionar transferência, "
    "encaminhamento ou outra pessoa."
)


def _identidade(nome: str, persona: str) -> str:
    linha = (
        f"Você é {nome.strip()}, assistente de atendimento ao cliente."
        if nome.strip()
        else "Você é um assistente de atendimento ao cliente."
    )
    if persona.strip():
        linha = f"{linha}\n\n### PERSONA (siga o tom e o estilo):\n{persona.strip()}"
    return linha


def _bloco(titulo: str, textos: Sequence[str]) -> str:
    if not textos:
        return ""
    corpo = "\n\n---\n\n".join(t.strip() for t in textos if t.strip())
    return f"\n\n### {titulo}:\n{corpo}"


def _campos(
    coletados: Sequence[tuple[str, str]], pendentes: Sequence[tuple[str, str]]
) -> str:
    partes: list[str] = []
    if coletados:
        partes.append("\n\n### DADOS JÁ COLETADOS DO CLIENTE:")
        partes.extend(f"- {nome}: {valor}" for nome, valor in coletados)
    if pendentes:
        partes.append("\n\n### DADOS AINDA NÃO COLETADOS:")
        partes.extend(f"- {nome}: {descricao}" for nome, descricao in pendentes)
        partes.append(
            "\nSe surgir a oportunidade, pergunte de forma natural, um de cada vez."
        )
    return "\n".join(partes)


def montar_prompt_sistema(
    *,
    nome: str,
    persona: str,
    regras: str,
    comportamento: str,
    dados_empresa: str,
    evidencia: Sequence[str],
    conflito: Sequence[str],
    coletados: Sequence[tuple[str, str]],
    pendentes: Sequence[tuple[str, str]],
    agora: datetime | None = None,
) -> str:
    data = (agora or datetime.now()).strftime("%d/%m/%Y %H:%M")
    texto = (
        f"Data e hora atual: {data}\n\n"
        f"{_identidade(nome, persona)}\n\n"
        f"{regras.strip() or _REGRAS_PADRAO}"
    )
    if comportamento.strip():
        texto += f"\n\n### COMO CONDUZIR ESTE ASSUNTO:\n{comportamento.strip()}"
    texto += _campos(coletados, pendentes)
    if dados_empresa.strip():
        texto += f"\n\n### DADOS DA EMPRESA:\n{dados_empresa.strip()}"
    texto += _bloco("EVIDÊNCIA (base de conhecimento)", evidencia)
    texto += _bloco("CONFLITO (corrija o cliente com educação, usando isto)", conflito)
    if not evidencia:
        texto += "\n\n### EVIDÊNCIA:\nNenhuma informação da base cobre esta mensagem."
    return texto


async def gerar_texto(
    llm: BaseChatModel,
    prompt_sistema: str,
    mensagem: str,
    historico: Sequence[ChatTurnTuple],
) -> str:
    """Texto puro da LLM — sem `with_structured_output`."""
    # Chaves no texto do tenant quebrariam o template: escapadas aqui.
    sistema = prompt_sistema.replace("{", "{{").replace("}", "}}")
    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", sistema),
            MessagesPlaceholder(variable_name="chat_history"),
            ("user", "{input}"),
        ]
    )
    saida = await (prompt | llm).ainvoke(
        {"chat_history": to_lc_messages(historico), "input": mensagem}
    )
    conteudo = getattr(saida, "content", saida)
    return (conteudo if isinstance(conteudo, str) else str(conteudo)).strip()
