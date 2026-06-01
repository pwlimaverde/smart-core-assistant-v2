# gRPC (grpcio e grpcio-tools)

- **Versão Recomendada:** 1.62.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
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
