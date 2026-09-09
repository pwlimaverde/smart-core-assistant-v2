"""Salvaguardas aplicadas antes de qualquer tool executar.

São quatro, e cada uma existe por um motivo diferente:

* **escopo** — falha rápido, com mensagem que ensina o agente. Não é segurança
  (a barreira real está no `runtime_api`); é ergonomia. Um agente que recebe
  "você não tem `atendimentos:write`" para de tentar; um que recebe "erro
  interno" tenta mais cinco vezes.
* **confirmação** — coloca uma pessoa no laço antes de um efeito irreversível.
* **`dry_run`** — deixa o agente descrever o que faria antes de fazer.
* **rate limit** — requisito normativo da spec (*"Servers MUST: […] Rate limit
  tool invocations"*) e a única defesa contra um agente em laço.

# Por que erro de execução e não erro de protocolo

A spec: clientes **SHOULD** entregar erros de execução ao modelo para
auto-correção, enquanto erros de protocolo "are less likely to result in
successful recovery". Toda recusa daqui é `ToolError` (`isError: true`), que
chega ao modelo como resultado e não como falha de transporte.

# O texto das mensagens vai para o log

O SDK loga `str(exc)` no caminho de erro de tool. Nenhuma mensagem deste arquivo
pode conter nome de contato, telefone ou conteúdo de mensagem — só nome de tool,
escopo, identificador e número.
"""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass

from mcp.server.mcpserver.exceptions import ToolError

from mcp_server.auth import scopes as catalogo
from mcp_server.tools.registry import Categoria, ToolRegistrada


def exigir_escopo(tool: ToolRegistrada, escopos_do_token: list[str]) -> None:
    """Recusa a execução se o token não satisfaz o escopo da tool."""
    if catalogo.tem_algum(escopos_do_token, tool.escopos):
        return
    exigidos = " ou ".join(tool.escopos)
    raise ToolError(
        f"A tool `{tool.nome}` exige a permissão {exigidos}, que este agente não "
        "recebeu. Isso não muda tentando outros argumentos: peça ao usuário para "
        "reconectar o aplicativo concedendo essa permissão."
    )


def exigir_confirmacao(
    tool: ToolRegistrada,
    nome_do_alvo: str,
    confirmar: str | None,
) -> None:
    """Confirmação por argumento — o nível 2 da §5.2 do plano.

    O nível 1 (elicitation, com o humano no laço) é preferível, mas é capacidade
    **opcional** do cliente: nem todo cliente MCP a negocia. Este nível é o que
    garante que a salvaguarda existe em todos.

    O truque é exigir o **nome** do alvo, não o id: o agente só consegue
    preencher se tiver buscado o objeto antes. Um id alucinado não passa, porque
    o modelo não teria de onde tirar o nome correspondente.
    """
    if confirmar is None or not confirmar.strip():
        raise ToolError(
            f"`{tool.nome}` é uma ação sem desfazer e exige confirmação. Busque o "
            "item primeiro e repita a chamada preenchendo `confirmar` com o nome "
            "exato dele, depois de conferir com a pessoa que você está ajudando."
        )
    if confirmar.strip() != nome_do_alvo.strip():
        # A mensagem NÃO repete o nome real do alvo: em tools de contato isso
        # seria PII, e o SDK loga o texto do erro.
        raise ToolError(
            f"`{tool.nome}`: a confirmação não corresponde ao nome do item "
            "indicado. Confira se o id é mesmo o do item que você quer alterar."
        )


@dataclass
class LimiteCategoria:
    por_minuto: int
    por_dia: int | None = None


class RateLimiter:
    """Contagem em memória por (grant, categoria).

    Em memória, e não no Redis, por decisão consciente: este processo não
    alcança o Redis (não está na rede `internal`), e alcançá-lo exigiria abrir a
    barreira topológica que é o ponto do desenho. O custo é que o limite passa a
    ser por réplica — com N réplicas, o teto efetivo é N vezes maior. Enquanto o
    serviço roda com uma réplica, o teto é o anunciado; ao escalar
    horizontalmente, este comentário vira uma tarefa: mover a contagem para uma
    RPC do `data_redis` exposta ao `mcp_net`.
    """

    def __init__(self, limites: dict[Categoria, LimiteCategoria]) -> None:
        self._limites = limites
        self._minuto: dict[tuple[str, Categoria], list[float]] = defaultdict(list)
        self._dia: dict[tuple[str, Categoria], list[float]] = defaultdict(list)

    def registrar(self, grant_id: str, tool: ToolRegistrada) -> None:
        """Contabiliza uma execução; levanta `ToolError` se estourar o teto."""
        limite = self._limites.get(tool.categoria)
        if limite is None:
            return

        agora = time.monotonic()
        chave = (grant_id, tool.categoria)

        janela_min = [t for t in self._minuto[chave] if agora - t < 60]
        if len(janela_min) >= limite.por_minuto:
            espera = int(60 - (agora - janela_min[0])) + 1
            raise ToolError(
                f"Limite de {limite.por_minuto} chamadas por minuto para tools de "
                f"{tool.categoria.value} atingido. Aguarde {espera} segundos antes "
                "de tentar de novo — repetir agora só vai falhar de novo."
            )

        janela_dia = [t for t in self._dia[chave] if agora - t < 86_400]
        if limite.por_dia is not None and len(janela_dia) >= limite.por_dia:
            raise ToolError(
                f"Limite diário de {limite.por_dia} chamadas para tools de "
                f"{tool.categoria.value} atingido. Este limite existe para que um "
                "agente em laço não alcance clientes reais; ele só reabre amanhã."
            )

        janela_min.append(agora)
        janela_dia.append(agora)
        self._minuto[chave] = janela_min
        self._dia[chave] = janela_dia

    def restantes(self, grant_id: str, categoria: Categoria) -> int:
        """Quantas chamadas ainda cabem no minuto corrente. Usado em teste."""
        limite = self._limites.get(categoria)
        if limite is None:
            return 10**9
        agora = time.monotonic()
        usados = len([t for t in self._minuto[(grant_id, categoria)] if agora - t < 60])
        return max(limite.por_minuto - usados, 0)


def resultado_dry_run(tool: ToolRegistrada, descricao_do_efeito: str) -> str:
    """Resposta padrão de uma execução com `dry_run=True`.

    O texto diz explicitamente que **nada foi alterado**. Sem essa frase, um
    modelo lê "fluxo desativado" na descrição do efeito e relata ao usuário que
    a ação foi feita.
    """
    return (
        f"SIMULAÇÃO — nada foi alterado. Se você chamar `{tool.nome}` com "
        f"`dry_run=false`, o efeito será: {descricao_do_efeito}"
    )
