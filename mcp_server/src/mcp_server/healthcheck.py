"""Sonda do container.

Bate no próprio endpoint MCP sem token e espera **401**. Parece contraintuitivo
usar um erro como sinal de saúde, mas é o teste mais forte disponível: um 401 com
o header `WWW-Authenticate` prova que o processo está de pé, que o roteamento
funciona e que a camada de autenticação está montada. Um 200 aqui significaria
que o servidor está aceitando requisição sem autorização — que é falha, não
saúde.

Uso: `python -m mcp_server.healthcheck`
"""

from __future__ import annotations

import sys

import httpx2 as httpx

from mcp_server import settings as config


def main() -> int:
    cfg = config.carregar()
    url = f"http://127.0.0.1:{cfg.port}{cfg.http_path}"
    try:
        resposta = httpx.post(
            url,
            json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
            headers={"Accept": "application/json, text/event-stream"},
            timeout=5.0,
        )
    except Exception as exc:  # noqa: BLE001 — a sonda não distingue causas
        print(f"mcp_server inacessível: {type(exc).__name__}")
        return 1

    if resposta.status_code == 401:
        return 0

    print(
        f"mcp_server respondeu {resposta.status_code} onde se esperava 401 "
        "(requisição sem token não pode ser aceita)"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
