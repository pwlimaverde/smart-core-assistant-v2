"""Prompt da LLM no motor Jev: ela só redige o ato que o código decidiu.

Sem schema, sem setor, sem confiança e sem decidir transferência — quem decide
é o código com a leitura do Jev. O prompt tem duas partes:

1. **Fixa por tenant** (identidade, persona, regras, dados da empresa): vem
   primeiro, igual a cada mensagem — é o que o cache de prefixo dos
   provedores reaproveita.
2. **Variável** (comportamento, dados coletados, evidência, a tarefa do ato,
   a correção da escalada e, por último, data e hora). Data e hora no topo
   invalidavam o cache a cada minuto.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

from ia_engine_jev.domain.jev import Dado
from ia_engine_jev.shared.history import ChatTurnTuple, to_lc_messages

CHAVE_REGRAS_RESPOSTA = "PROMPT_REGRAS_RESPOSTA_JEV"

_REGRAS_PADRAO = (
    "### Regras de resposta (siga rigorosamente):\n"
    "1. Dê continuidade natural à conversa, usando o histórico.\n"
    "2. Use SÓ as informações da EVIDÊNCIA e dos DADOS DA EMPRESA. Não invente "
    "preço, prazo, desconto nem condição.\n"
    "3. Responda em português, de forma curta, sóbria e educada.\n"
    "4. Não repita os dados que o cliente acabou de informar.\n"
    "5. Nunca diga que vai transferir, encaminhar ou chamar alguém, mesmo que "
    "a persona fale disso: quem decide a transferência é o sistema, não você.\n"
    "6. Faça só as perguntas que a TAREFA pedir.\n"
)


@dataclass(frozen=True)
class PedidoDeRedacao:
    ato: str
    nome: str = ""
    persona: str = ""
    regras: str = ""
    dados_empresa: str = ""
    comportamento: str = ""
    evidencia: Sequence[str] = ()
    conflito: Sequence[str] = ()
    coletados: Sequence[tuple[str, str]] = ()
    perguntar: Sequence[Dado] = ()
    nota_politica: str = ""
    correcoes: Sequence[str] = ()


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
    corpo = "\n\n---\n\n".join(t.strip() for t in textos if t.strip())
    return f"\n\n### {titulo}:\n{corpo}" if corpo else ""


def _lista_de_dados(dados: Sequence[Dado]) -> str:
    return "\n".join(
        f"- {d.nome}" + (f" ({d.descricao})" if d.descricao else "") for d in dados
    )


def _tarefa(p: PedidoDeRedacao) -> str:
    partes: list[str] = []
    match p.ato:
        case "responder":
            partes.append(
                "Responda à mensagem do cliente usando só a EVIDÊNCIA e os DADOS "
                "DA EMPRESA."
            )
            if p.conflito:
                partes.append(
                    "Se o cliente supõe algo que o bloco CONFLITO contradiz, "
                    "corrija com educação usando esse bloco."
                )
        case "coletar":
            partes.append(
                "Reconheça a mensagem em poucas palavras, sem repetir o que o "
                "cliente disse."
            )
        case _:
            partes.append(
                "Responda de forma curta e cordial (cumprimento, agradecimento ou "
                "conversa). Não peça dados do pedido."
            )
    if p.nota_politica.strip():
        partes.append(
            "O cliente pediu algo que a empresa NÃO fornece. Diga isso com "
            f"cordialidade e ofereça o que há no lugar: {p.nota_politica.strip()}"
        )
    if p.perguntar:
        partes.append(
            "Peça ao cliente, numa única mensagem, só estes dados — nenhuma "
            f"outra pergunta:\n{_lista_de_dados(p.perguntar)}"
        )
    return "\n".join(partes)


def montar_prompt_sistema(p: PedidoDeRedacao, agora: datetime | None = None) -> str:
    # 1. Parte fixa por tenant (prefixo cacheável).
    texto = f"{_identidade(p.nome, p.persona)}\n\n{p.regras.strip() or _REGRAS_PADRAO}"
    if p.dados_empresa.strip():
        texto += f"\n\n### DADOS DA EMPRESA:\n{p.dados_empresa.strip()}"
    # 2. Parte variável.
    if p.comportamento.strip():
        texto += f"\n\n### COMO CONDUZIR ESTE ASSUNTO:\n{p.comportamento.strip()}"
    if p.coletados:
        texto += "\n\n### DADOS JÁ INFORMADOS PELO CLIENTE:\n" + "\n".join(
            f"- {nome}: {valor}" for nome, valor in p.coletados
        )
    if p.ato == "responder":
        texto += _bloco("EVIDÊNCIA (base de conhecimento)", p.evidencia)
        texto += _bloco("CONFLITO (corrija o cliente com educação)", p.conflito)
        if not p.evidencia:
            texto += (
                "\n\n### EVIDÊNCIA:\nNenhum trecho da base cobre esta mensagem; "
                "use só os DADOS DA EMPRESA."
            )
    texto += f"\n\n### SUA TAREFA NESTA MENSAGEM:\n{_tarefa(p)}"
    if p.correcoes:
        texto += "\n\n### ATENÇÃO — a versão anterior foi recusada. Corrija:\n" + (
            "\n".join(f"- {c}" for c in p.correcoes)
        )
    data = (agora or datetime.now()).strftime("%d/%m/%Y %H:%M")
    texto += f"\n\nData e hora atual: {data}"
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
