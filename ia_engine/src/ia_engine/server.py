"""Bootstrap do servidor gRPC (`grpc.aio`) com graceful shutdown e health check.

Entrypoint: ``python -m ia_engine.server``.
"""

from __future__ import annotations

import asyncio
import signal

import grpc
from grpc_health.v1 import health, health_pb2, health_pb2_grpc
from loguru import logger

from ia_engine.contracts import ai_engine_pb2 as pb
from ia_engine.contracts import ai_engine_pb2_grpc as pbg
from ia_engine.servicer import IaEngineServicer
from ia_engine.settings import Settings, get_settings
from ia_engine.telemetry import setup_telemetry

_SERVICE_NAME = pb.DESCRIPTOR.services_by_name["IaEngineService"].full_name


async def _build_server(
    settings: Settings,
) -> tuple[grpc.aio.Server, health.aio.HealthServicer]:
    interceptors = setup_telemetry(settings)
    server = grpc.aio.server(interceptors=interceptors)

    pbg.add_IaEngineServiceServicer_to_server(IaEngineServicer(), server)

    health_servicer = health.aio.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)

    listen_addr = f"{settings.grpc_host}:{settings.grpc_port}"
    server.add_insecure_port(listen_addr)
    return server, health_servicer


async def serve() -> None:
    settings = get_settings()
    server, health_servicer = await _build_server(settings)

    await server.start()
    await health_servicer.set("", health_pb2.HealthCheckResponse.SERVING)
    await health_servicer.set(
        _SERVICE_NAME, health_pb2.HealthCheckResponse.SERVING
    )
    logger.info(
        "ia_engine ouvindo em {}:{} (env={})",
        settings.grpc_host,
        settings.grpc_port,
        settings.smartcore_env,
    )

    stop = asyncio.Event()
    _install_signal_handlers(stop)

    try:
        await stop.wait()
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    finally:
        logger.info("Encerrando ia_engine (grace={}s)...", settings.grpc_grace_seconds)
        await health_servicer.set(
            "", health_pb2.HealthCheckResponse.NOT_SERVING
        )
        await server.stop(settings.grpc_grace_seconds)


def _install_signal_handlers(stop: asyncio.Event) -> None:
    loop = asyncio.get_running_loop()

    def _request_stop() -> None:
        loop.call_soon_threadsafe(stop.set)

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            # Windows: add_signal_handler não é suportado no ProactorEventLoop.
            signal.signal(sig, lambda *_: _request_stop())


def main() -> None:
    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
