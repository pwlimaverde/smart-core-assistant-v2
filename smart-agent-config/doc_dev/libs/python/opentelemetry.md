# opentelemetry (Python)

- **Versão Recomendada:** série estável **1.x** (`opentelemetry-api`/`opentelemetry-sdk` 1.x + `opentelemetry-exporter-otlp-proto-grpc` 1.x + `opentelemetry-instrumentation-grpc` 0.x b — versões `api`/`sdk` e `instrumentation` andam em trilhas pareadas; pinar no `pyproject.toml` na implementação da N2)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-06 (context7 `/websites/opentelemetry-python_readthedocs_io_en_stable` + `/open-telemetry/opentelemetry-python-contrib`)
- **Propósito no Projeto:** tracing distribuído do `ia_engine` (fase N2) — continuar o trace W3C (`traceparent`) vindo do `worker` Rust via metadata gRPC, emitir spans por feature de IA (`ia.transcribe`, `ia.responder`, `ia.rag`…) com `tenant_id`, re-injetar o contexto nas chamadas outbound ao `data_postgres` e exportar via OTLP/gRPC para a stack LGTM (Tempo).
- **Documentação Oficial:** [opentelemetry-python.readthedocs.io](https://opentelemetry-python.readthedocs.io/en/stable/) · [opentelemetry-python-contrib (gRPC)](https://github.com/open-telemetry/opentelemetry-python-contrib/tree/main/instrumentation/opentelemetry-instrumentation-grpc)

---

## Pacotes

| Pacote | Papel |
|---|---|
| `opentelemetry-api` | API pública (tracer, propagators) |
| `opentelemetry-sdk` | `TracerProvider`, `Resource`, `BatchSpanProcessor` |
| `opentelemetry-exporter-otlp-proto-grpc` | `OTLPSpanExporter` (endpoint OTLP gRPC, ex. collector `:4317`) |
| `opentelemetry-instrumentation-grpc` | Interceptors cliente/servidor para gRPC Python (inclui variantes asyncio) |

## Guia de Uso Rápido

### 1. Setup do provider (boot do `server.py`)

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# service.name é obrigatório para o Tempo/Grafana agrupar por serviço
resource = Resource.create({"service.name": "ia_engine", "deployment.environment": env})

trace.set_tracer_provider(TracerProvider(resource=resource))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter())  # endpoint via OTEL_EXPORTER_OTLP_ENDPOINT
)
tracer = trace.get_tracer("ia_engine")
```

- Endpoint por env: `OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector>:4317` (mesmo collector da malha Rust).
- `BatchSpanProcessor` **não é fork-safe** — com `multiprocessing`/gunicorn, inicializar pós-fork. No nosso caso (servidor `grpc.aio` single-process) o setup no boot basta.

### 2. Continuar o trace inbound (extract do `traceparent` do metadata gRPC)

O propagator global default já é W3C TraceContext (`traceparent`/`tracestate`).

```python
from opentelemetry import propagate, trace

PROPAGATOR = propagate.get_global_textmap()

async def Responder(self, request, context):
    # metadata gRPC → carrier dict (chaves lowercase)
    carrier = {k: v for k, v in context.invocation_metadata()}
    ctx = PROPAGATOR.extract(carrier=carrier)
    with tracer.start_as_current_span("ia.responder", context=ctx) as span:
        span.set_attribute("tenant_id", request.tenant_id)
        ...
```

### 3. Re-injetar no cliente outbound (chamada ao `data_postgres`)

```python
from opentelemetry import propagate

carrier: dict[str, str] = {}
propagate.get_global_textmap().inject(carrier)
metadata = tuple(carrier.items())  # vira metadata da chamada gRPC
await stub.QueryCompose(req, metadata=metadata)
```

### 4. Instrumentação automática do gRPC (alternativa aos passos 2–3)

O pacote `opentelemetry-instrumentation-grpc` fornece interceptors que fazem extract/inject
automaticamente, incluindo variantes **asyncio** (`grpc.aio`) — na implementação, confirmar os
nomes exatos no README do pacote (série `GrpcInstrumentorServer`/`GrpcInstrumentorClient` e
variantes `GrpcAioInstrumentor*`):

```python
from opentelemetry.instrumentation.grpc import (
    GrpcAioInstrumentorServer, GrpcAioInstrumentorClient,
)

GrpcAioInstrumentorServer().instrument()
GrpcAioInstrumentorClient().instrument()
```

> Recomendação do projeto: usar a instrumentação automática para a propagação e criar os
> spans de negócio (`ia.*`) manualmente por cima, com `tenant_id` como atributo.

### 5. Sanitização

Nunca colocar conteúdo de mensagem, prompt completo, telefone ou api key em atributos de span —
só ids, contadores e flags (mesma política dos serviços Rust).
