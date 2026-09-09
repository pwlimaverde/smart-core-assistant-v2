# gRPC (grpcio e grpcio-tools)

- **Versão Recomendada:** 1.83.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-06 (WebSearch/WebFetch — context7 indisponível na sessão)
- **Propósito no Projeto:** Comunicação interna de alto desempenho e baixa latência (gRPC/Protobuf) entre o `worker` (Rust) e o `ia_engine` (Python).
- **Documentação Oficial:** [https://grpc.io/docs/languages/python/](https://grpc.io/docs/languages/python/)

---

## 1. Contexto e Uso no Projeto

Embora exista uma FFI local no Windows (onde a FFI local do Flutter carrega a lib Rust de cache), a comunicação no lado servidor entre o **`worker` em Rust** e o **`ia_engine` em Python** é realizada via **gRPC**.

Os contratos de interface são definidos como arquivos `.proto` (Protobuf) compartilhados na raiz do repositório ou compilados a partir de `server/crates/contracts/`.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Compilação Automatizada de Arquivos Protobuf
Não edite os arquivos `.py` gerados pelo compilador gRPC (`_pb2.py` e `_pb2_grpc.py`). Sempre que o arquivo `.proto` sofrer alteração, rode o gerador do `grpc_tools`:

```bash
uv run python -m grpc_tools.protoc -I../server/crates/contracts/proto --python_out=./src/ai_engine/contracts --grpc_python_out=./src/ai_engine/contracts ../server/crates/contracts/proto/ai_service.proto
```

### 2.2 Inicialização Assíncrona do Servidor gRPC
O servidor gRPC em Python deve rodar de forma assíncrona sobre o loop de eventos do `asyncio` para suportar concorrência eficiente e timeouts controlados pelo cliente em Rust.

```python
import asyncio
import grpc
from ai_engine.contracts import ai_service_pb2_grpc
from ai_engine.services.ai_servicer import AiServicer

async def serve() -> None:
    # Cria o servidor assíncrono com suporte a pool de threads para tasks pesadas
    server = grpc.aio.server()
    
    # Registra o serviço de IA no roteador do gRPC
    ai_service_pb2_grpc.add_AiServiceServicer_to_server(
        AiServicer(), server
    )
    
    # Vincula a porta padrão
    listen_addr = "[::]:50051"
    server.add_insecure_port(listen_addr)
    print(f"Servidor gRPC iniciado na porta {listen_addr}")
    
    await server.start()
    await server.wait_for_termination()

if __name__ == "__main__":
    asyncio.run(serve())
```

### 2.3 Tratamento de Exceções com gRPC Status Codes
No seu Servicer (implementação do gRPC), intercepte erros lógicos internos e use `context.abort()` para retornar códigos de status gRPC sem expor logs confidenciais nem quebrar o pipeline de transporte.

```python
import grpc
from ai_engine.contracts import ai_service_pb2

class AiServicer(ai_service_pb2_grpc.AiServiceServicer):
    async def SummarizeText(
        self, 
        request: ai_service_pb2.SummaryRequest, 
        context: grpc.aio.ServicerContext
    ) -> ai_service_pb2.SummaryResponse:
        
        if not request.text:
            # Aborta imediatamente com status INVALID_ARGUMENT (HTTP 400 equivalente)
            await context.abort(
                grpc.StatusCode.INVALID_ARGUMENT, 
                "O texto de entrada não pode ser vazio."
            )

        try:
            summary = await run_summarizer_logic(request.text)
            return ai_service_pb2.SummaryResponse(success=True, summary=summary)
            
        except Exception as e:
            # Aborta com erro interno mapeado
            await context.abort(
                grpc.StatusCode.INTERNAL, 
                f"Erro interno de processamento de IA: {str(e)}"
            )
```

### 2.4 Cliente Assíncrono com Metadata e Timeouts
Para chamadas do Rust (cliente) ao `ia_engine` em Python, use `grpc.aio` com propagação de `traceparent` e `authorization` via metadata:

```python
import grpc
from ai_engine.contracts import ai_service_pb2

async def call_ia_service(host: str, port: int, request, traceparent: str, token: str):
    """Chama o serviço de IA com metadata de tracing e autenticação."""
    
    # Cria o canal
    channel = grpc.aio.secure_channel(
        f"{host}:{port}",
        grpc.ssl_channel_credentials()
    )
    
    # Metadata para propagação de contexto distribuído e autenticação
    metadata = [
        ("traceparent", traceparent),  # Propagação de trace W3C
        ("authorization", f"Bearer {token}"),
    ]
    
    # Stubber do serviço
    stub = ai_service_pb2_grpc.AiServiceStub(channel)
    
    try:
        # Chamada com timeout (deadline)
        response = await stub.SummarizeText(
            request,
            metadata=metadata,
            timeout=30.0  # 30 segundos
        )
        return response
    finally:
        await channel.close()
```

### 2.5 Health Checking com `grpcio-health-checking`
Para implementar health checks (liveness/readiness), use `grpcio-health-checking`:

```python
import asyncio
from grpc_health.v1 import health
from grpc_health.v1 import health_pb2_grpc
import grpc

async def serve_with_health() -> None:
    server = grpc.aio.server()
    
    # Registra serviço de health check
    health_servicer = health.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)
    
    # Define status de health para o serviço de IA
    health_servicer.set("ai_service.AiService", health_pb2.HealthCheckResponse.SERVING)
    
    # ... resto do setup
    await server.start()
```

---

## 3. Breaking Changes e Migrações (1.62.1 → 1.83.1)

### 3.1 Requisitos de Python
- **Removido:** Python 3.9 (dropado em favor de 3.10+)
- **Novo:** Python 3.15 suportado (com updates em build tools)

### 3.2 Post-Quantum Cryptography (v1.83.0)
Versão 1.83.0 introduz default para **Post-Quantum Cryptography em TLS key exchange**, representando melhoria significativa de segurança. Se seu cliente Rust usa TLS, confirme compatibilidade.

### 3.3 grpc.aio — Observability Support (v1.81.1)
A stack assíncrona ganhou suporte a observability em v1.81.1. Aproveite para integrar com seu stack LGTM (Grafana, Loki, Tempo):

```python
# Exemplo com interceptor de tracing
import grpc
from opentelemetry.instrumentation.grpc import GrpcInstrumentor

# Instrumentar automaticamente grpc.aio
GrpcInstrumentor().instrument()
```

### 3.4 Custom Interceptor Exception Handling (v1.83.0)
V1.83.0 melhorou tratamento de exceções em custom interceptors, permitindo lógica mais robusta para retry/fallback.

### 3.5 grpc-tools e Protobuf Compatibility
Atualizações contínuas asseguram compatibilidade com versões recentes de protobuf. Ao gerar stubs:

```bash
# Gera inclusive stubs .pyi para type hints
python -m grpc_tools.protoc \
  -I../server/crates/contracts/proto \
  --python_out=./src/ai_engine/contracts \
  --pyi_out=./src/ai_engine/contracts \
  --grpc_python_out=./src/ai_engine/contracts \
  ../server/crates/contracts/proto/ai_service.proto
```

### 3.6 V1.82.0 Yanked
Versão 1.82.0 foi yanked do PyPI (issue #42906). Não a utilize; migre para 1.82.1 ou 1.83.1.

---

## 4. gRPC Observability e Integração com LGTM

Desde v1.81.1, `grpc.aio` tem suporte melhorado para observability. Integre com seu stack LGTM:

### 4.1 Prometheus Metrics
```python
from prometheus_client import Counter, Histogram

grpc_calls = Counter(
    'grpc_calls_total',
    'Total gRPC calls',
    ['service', 'method', 'status']
)

grpc_duration = Histogram(
    'grpc_call_duration_seconds',
    'gRPC call duration in seconds',
    ['service', 'method']
)
```

### 4.2 Traçamento Distribuído (OpenTelemetry)
```python
from opentelemetry import trace
from opentelemetry.instrumentation.grpc import GrpcInstrumentor

GrpcInstrumentor().instrument()
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("ai_service_call") as span:
    span.set_attribute("rpc.service", "AiService")
    # sua lógica aqui
```

---

## 5. Histórico de Atualizações

| Data | Versão | Motivo da Atualização |
|------|--------|----------------------|
| 2026-09-06 | 1.62.1 → 1.83.1 | Verificação regular: versão antiga tinha >90 dias. Adicionadas seções sobre grpc.aio client (metadata, timeouts), health-checking, observability, breaking changes e v1.83.0 security. |
| 2026-05-31 | 1.62.1 | Última verificação anterior |
```
