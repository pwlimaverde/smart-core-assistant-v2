"""Bootstrap do servidor MCP.

Sobe o `MCPServer` em Streamable HTTP, registra as tools e liga a telemetria.

# Stateless

`stateless_http=True` porque a revisão `2026-07-28` da spec é explícita: *"MCP
has no protocol-level session"*. O token é resolvido **a cada requisição**, e
nenhum estado entre chamadas mora na conexão. A consequência prática é que o
Caddy não precisa de sticky sessions e escalar horizontalmente é só subir mais
uma réplica — com a ressalva sobre o rate limit registrada em `guards.py`.

# Descoberta

O `/.well-known/oauth-protected-resource` (RFC 9728) e o header
`WWW-Authenticate` com `resource_metadata` vêm do próprio SDK, quando
`AuthSettings.resource_server_url` está preenchido. Não escrevemos os nossos: a
implementação do SDK é conformante, e uma cópia nossa divergiria dela na primeira
atualização.
"""

from __future__ import annotations

import sys
from importlib import resources

from loguru import logger
from mcp.server.auth.settings import AuthSettings
from mcp_types import Icon
from starlette.requests import Request
from starlette.responses import Response

from mcp_server import settings as config
from mcp_server import telemetry
from mcp_server.auth.token_verifier import TrocadorDeToken, VerificadorDeToken
from mcp_server.grpc.runtime_client import RuntimeApiClient
from mcp_server.tools import (
    atendimento,
    cadastros,
    configuracao,
    configuracao_tenant,
    destrutivas,
    envio,
    equipe_whatsapp,
    leitura,
    treinamento_ia,
)
from mcp_server.tools.base import Executor
from mcp_server.tools.guards import LimiteCategoria, RateLimiter
from mcp_server.tools.registry import Categoria, Registro, ServidorMcpFiltrado

INSTRUCOES = """\
Este servidor dá acesso ao Smart Core Assistant de um negócio: atendimentos por \
WhatsApp, contatos, fluxos de trabalho (Kanban), equipe e a base de conhecimento \
do assistente automático.

Como trabalhar aqui:

1. Comece por `get_painel` ou pelas tools `list_*` — elas dão os ids que todas as \
   demais exigem. Nunca invente um id.
2. Antes de qualquer escrita, chame a mesma tool com `dry_run=true` e mostre o \
   resultado à pessoa que está pedindo.
3. `send_message` envia uma mensagem real ao WhatsApp de um cliente e **não tem \
   desfazer**. Mostre o texto antes de enviar, sempre.
4. Se uma tool responder que falta permissão, não tente de novo com outros \
   argumentos: a pessoa precisa reconectar o aplicativo concedendo aquele acesso.

5. Configuração do assistente: `get_tenant_config` mostra tudo (inclusive os \
   prompts do negócio). `update_tenant_config`, `update_config_avancada` e \
   `set_prompts` mudam só o que for informado.

As tools que você enxerga são as que a autorização permite. Se algo que você \
esperava não aparece, é permissão — não é falha do servidor.\
"""


def montar() -> ServidorMcpFiltrado:
    """Constrói o servidor com tudo ligado, sem subir o transporte."""
    cfg = config.carregar()
    telemetry.inicializar()
    logger.info("configuração carregada: {}", cfg.resumo_seguro())

    verificador = VerificadorDeToken(
        # `chave_publica`, não `oauth_public_key_pem`: o valor cru pode vir com
        # `\n` escapado do env_file (ver a nota em settings.py).
        chave_publica_pem=cfg.chave_publica,
        issuer=cfg.oauth_issuer,
        resource=cfg.oauth_resource,
    )

    registro = Registro()
    mcp = ServidorMcpFiltrado(
        name="smart-core-assistant",
        title="Smart Core Assistant",
        instructions=INSTRUCOES,
        version="0.1.0",
        website_url="https://smartcoreassistant.com.br",
        # Sem `icons` o cliente desenha um avatar com a inicial do nome — o
        # "S" que aparecia no lugar da marca. O ícone é servido por este mesmo
        # servidor (rota pública logo abaixo) em vez de ir embutido como
        # `data:`: são ~7 KB que iriam em todo `initialize`, e por URL o
        # cliente busca uma vez e guarda.
        icons=[
            Icon(
                src=f"{cfg.oauth_resource}/icon.png",
                mime_type="image/png",
                sizes=["128x128"],
            )
        ],
        token_verifier=verificador,
        auth=AuthSettings(
            # `cfg.issuer_url`/`cfg.resource_url`, e não `AnyHttpUrl(...)`:
            # construir a URL aqui fora acrescenta a barra do path vazio, e
            # o documento RFC 9728 passa a anunciar um identificador
            # diferente do `issuer` do AS. Ver a nota em settings.py.
            issuer_url=cfg.issuer_url,
            resource_server_url=cfg.resource_url,
            # `required_scopes` fica vazio de propósito: exigir um escopo no
            # nível HTTP recusaria a conexão inteira de um token que ainda pode
            # usar parte das tools. O escopo é checado por tool, onde a recusa
            # vira erro de execução que o agente entende e corrige.
            required_scopes=None,
        ),
        registro=registro,
    )

    executor = Executor(
        registro=registro,
        cliente=RuntimeApiClient(cfg.runtime_endpoint, cfg.runtime_timeout_s),
        trocador=TrocadorDeToken(cfg.token_exchange_url, cfg.service_secret),
        limitador=RateLimiter(
            {
                Categoria.LEITURA: LimiteCategoria(cfg.rate_leitura_min),
                Categoria.CONFIGURACAO: LimiteCategoria(cfg.rate_config_min),
                Categoria.ENVIO: LimiteCategoria(
                    cfg.rate_envio_min, cfg.rate_envio_dia
                ),
                Categoria.DESTRUTIVA: LimiteCategoria(
                    cfg.rate_destrutiva_min, cfg.rate_destrutiva_dia
                ),
            }
        ),
        metricas=telemetry.Metricas(),
    )

    # A ordem de registro é a ordem de `tools/list`. Leitura primeiro: é o que o
    # agente precisa chamar antes de qualquer outra coisa, e modelos dão peso à
    # ordem em que as ferramentas aparecem.
    teto = cfg.max_itens_por_pagina
    leitura.registrar(mcp, registro, executor, teto=teto)
    configuracao.registrar(mcp, registro, executor)
    configuracao_tenant.registrar(mcp, registro, executor)
    cadastros.registrar(mcp, registro, executor, teto=teto)
    treinamento_ia.registrar(mcp, registro, executor, teto=teto)
    atendimento.registrar(mcp, registro, executor, teto=teto)
    equipe_whatsapp.registrar(mcp, registro, executor, teto=teto)
    envio.registrar(mcp, registro, executor)
    destrutivas.registrar(mcp, registro, executor)

    _registrar_icone(mcp)

    logger.info("{} tools registradas", len(registro.todos()))
    return mcp


def _registrar_icone(mcp: ServidorMcpFiltrado) -> None:
    """Serve a marca do produto em `/icon.png`.

    Pública de propósito: é o que o cliente busca **antes** de haver token, para
    desenhar a lista de conexões. Exigir autenticação aqui devolveria 401 e o
    cliente cairia de volta na inicial do nome.

    O arquivo é lido uma vez, na subida, e servido de memória — são 7 KB, e um
    `open()` por request seria trabalho à toa.
    """
    dados = resources.files("mcp_server.static").joinpath("icon-128.png").read_bytes()

    @mcp.custom_route("/icon.png", methods=["GET"], include_in_schema=False)
    async def icone(_: Request) -> Response:
        return Response(
            dados,
            media_type="image/png",
            # Um dia: a marca muda com o produto, não com o deploy.
            headers={"Cache-Control": "public, max-age=86400"},
        )


def main() -> int:
    cfg = config.carregar()
    if not cfg.oauth_public_key_pem:
        # Sem a chave pública nenhum token pode ser validado, e todo request
        # responderia 401. Recusar a subir é mais honesto que um healthcheck
        # verde num servidor que não atende ninguém.
        logger.error(
            "MCP_OAUTH_PUBLIC_KEY_PEM ausente: sem ela nenhum token pode ser validado"
        )
        return 1
    if not cfg.service_secret:
        logger.error(
            "MCP_SERVICE_SECRET ausente: a troca pelo token interno seria recusada "
            "pelo control_plane em toda chamada"
        )
        return 1

    mcp = montar()
    # Parâmetros de transporte vão no `run()`, não no construtor: mudou na v2 do
    # SDK, e código escrito no padrão v1 não sobe.
    mcp.run(
        transport="streamable-http",
        host=cfg.host,
        port=cfg.port,
        streamable_http_path=cfg.http_path,
        stateless_http=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
