"""Sonda de liveness/readiness para o `healthcheck` do compose.

Entrypoint: ``python -m ia_engine.healthcheck`` — sai com 0 quando o servidor
responde ``SERVING`` no protocolo padrão ``grpc.health.v1``, e com 1 em
qualquer outro caso (canal recusado, timeout, ``NOT_SERVING``).

Por que existe: o smoke test do deploy só conseguia olhar o estado do
container (rodando / sem restart-loop). Um processo que subiu mas cujo
servidor gRPC não está aceitando RPC aparece como `running` e passaria no
gate. Usa cliente **síncrono** de propósito: é um processo de vida curta
disparado pelo Docker, sem event loop a montar.
"""

from __future__ import annotations

import sys

import grpc
from grpc_health.v1 import health_pb2, health_pb2_grpc

_DEFAULT_TIMEOUT_SECONDS = 3.0


def check(address: str, *, timeout: float = _DEFAULT_TIMEOUT_SECONDS) -> bool:
    """Consulta o serviço de health no endereço informado.

    Args:
        address: `host:porta` do servidor gRPC.
        timeout: Prazo total da consulta, em segundos.

    Returns:
        `True` somente se o status for `SERVING`.
    """
    try:
        with grpc.insecure_channel(address) as channel:
            stub = health_pb2_grpc.HealthStub(channel)
            response = stub.Check(
                health_pb2.HealthCheckRequest(), timeout=timeout
            )
    except grpc.RpcError:
        return False
    return response.status == health_pb2.HealthCheckResponse.SERVING


def main(argv: list[str] | None = None) -> int:
    """Uso: `python -m ia_engine.healthcheck [host:porta]`.

    Sem argumento, resolve o endereço do ambiente via `Settings` — o mesmo
    par host/porta em que o `server.py` escuta.
    """
    args = sys.argv[1:] if argv is None else argv
    if args:
        address = args[0]
    else:
        from ia_engine.settings import get_settings

        settings = get_settings()
        # O container escuta em 0.0.0.0; a sonda roda dentro dele e conecta
        # no loopback (0.0.0.0 não é endereço de destino válido).
        host = settings.grpc_host
        if host in ("0.0.0.0", "::", ""):  # noqa: S104 — bind, não destino
            host = "127.0.0.1"
        address = f"{host}:{settings.grpc_port}"
    return 0 if check(address) else 1


if __name__ == "__main__":
    raise SystemExit(main())
