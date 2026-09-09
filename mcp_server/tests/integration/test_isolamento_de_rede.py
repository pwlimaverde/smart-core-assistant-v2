"""O invariante que só se prova dentro do container.

O `mcp_server` **não** pode alcançar o banco. A barreira é a rede `mcp_net` do
compose — o container fica em `[mcp_net, observability]` e nunca em `internal` —,
e este teste é o que impede que ela seja desfeita por descuido: se alguém
acrescentar `internal` ao serviço no compose "para facilitar", o nome
`data_postgres` passa a resolver e o teste falha.

Roda só dentro do container (`MCP_TESTE_EM_CONTAINER=1`), porque na máquina de
desenvolvimento esses nomes também não resolvem — o que faria o teste passar por
motivo errado, que é pior do que não rodar.
"""

from __future__ import annotations

import os
import socket

import pytest

pytestmark = pytest.mark.skipif(
    os.getenv("MCP_TESTE_EM_CONTAINER") != "1",
    reason="só faz sentido dentro do container do mcp_server",
)

# Os nomes de serviço da rede `internal`. Nenhum deles pode resolver aqui.
SERVICOS_PROIBIDOS = (
    "postgres",
    "data_postgres",
    "data_redis",
    "data_storage",
    "redis",
)


@pytest.mark.parametrize("nome", SERVICOS_PROIBIDOS)
def test_servico_de_dados_nao_resolve(nome: str):
    with pytest.raises(socket.gaierror):
        socket.getaddrinfo(nome, None)


def test_o_runtime_api_resolve():
    """A contraprova: a única porta de dados permitida precisa estar de pé.

    Sem este teste, o anterior passaria também num container sem rede nenhuma —
    e um servidor isolado de tudo passa em "não alcança o banco" sem servir para
    nada.
    """
    endpoint = os.getenv("MCP_RUNTIME_ENDPOINT", "runtime_api:50051")
    host = endpoint.split(":")[0]
    assert socket.getaddrinfo(host, None)


def test_nao_existe_database_url_no_ambiente():
    """Nem por engano de configuração.

    Um `DATABASE_URL` presente aqui não daria acesso (a rede não deixa), mas
    seria o primeiro passo de alguém tentando o atalho.
    """
    for variavel in ("DATABASE_URL", "DATABASE_ADMIN_URL"):
        assert variavel not in os.environ, (
            f"{variavel} não deve existir no ambiente do mcp_server"
        )
