# gRPC Dart

- **Versão Recomendada:** ~4.0.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Cliente gRPC-Web no Flutter Web/WASM (smart-core-admin) consumindo o AuthService da runtime_api; geração de stubs Dart dos .proto
- **Documentação Oficial:** https://grpc.io/docs/languages/dart/
- **Library ID Context7:** `/grpc/grpc-dart`

---

## Resumo

O `grpc` é a implementação oficial de gRPC para Dart/Flutter. No contexto do smart-core-admin (Flutter Web compilado para WASM), utiliza-se o `GrpcWebClientChannel` para comunicação HTTP(S) com um servidor Rust Tonic que serve gRPC-Web. A geração de stubs Dart ocorre via `protoc` com o plugin Dart (`protoc_plugin`), que produz arquivos `.pbgrpc.dart` a partir das definições `.proto`.

---

## 1. Instalação e Dependências

Adicione as dependências no `pubspec.yaml`:

```yaml
dependencies:
  grpc: ^4.0.0
  protobuf: ^3.0.0
```

### Ativar o Plugin Protoc (uma vez por máquina de desenvolvimento)

```bash
dart pub global activate protoc_plugin
# Verifique se ~/.pub-cache/bin está no PATH
```

---

## 2. Guia de Uso Rápido

### 2.1 Criar Canal gRPC-Web e Usar Stub

**Contexto:** Flutter Web falando com servidor Tonic via gRPC-Web.

```dart
import 'package:grpc/grpc_web.dart';
import 'src/generated/auth.pbgrpc.dart';  // gerado do auth.proto

Future<void> main() async {
  // Canal XHR (XMLHttpRequest) — não requer HTTP/2 no browser
  final channel = GrpcWebClientChannel.xhr(
    Uri.parse('https://api.example.com'),  // URL do servidor Tonic
  );

  final authStub = AuthServiceClient(channel);

  try {
    // Fazer uma chamada unária simples
    final response = await authStub.login(
      LoginRequest()..email = 'user@example.com',
    );
    print('Token recebido: ${response.token}');
  } on GrpcError catch (e) {
    print('Erro: ${e.codeName} — ${e.message}');
  } finally {
    await channel.shutdown();
  }
}
```

**Pontos-chave:**
- `GrpcWebClientChannel.xhr()` cria um canal que usa XMLHttpRequest (não HTTP/2).
- A URL deve apontar para o endpoint gRPC-Web (geralmente atrás de um proxy compatível).
- Chamar `channel.shutdown()` ao descartar.

> ⚠️ **ATENÇÃO — WASM (CanvasKit/Skwasm WASM):** o construtor `.xhr()` depende de
> `dart:html`/`XMLHttpRequest`, que **não está disponível quando o app é compilado
> para WebAssembly** (`flutter build web --wasm`). Em WASM use o transporte baseado
> em `package:web`/`dart:js_interop` (canal gRPC-Web sobre `fetch`), exposto pelo
> `grpc` nas versões recentes. **Esta é uma decisão a validar no início da Frente B**
> (provar a conexão gRPC-Web rodando de fato sob `--wasm`, não só em JS): confirmar
> o construtor/fábrica correto da versão fixada do package e, se necessário, ajustar
> a versão do `grpc`. Não assuma `.xhr()` no smart-core-admin.

---

### 2.2 Geração de Stubs Dart a partir de .proto

**Pré-requisito:** `protoc` instalado e `protoc_plugin` ativado (ver seção 1).

Arquivo `auth.proto` (exemplo):

```proto
syntax = "proto3";

package auth.v1;

service AuthService {
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc Refresh(RefreshRequest) returns (RefreshResponse);
}

message LoginRequest {
  string email = 1;
  string password = 2;
}

message LoginResponse {
  string token = 1;
  string refresh_token = 2;
}

message RefreshRequest {
  string refresh_token = 1;
}

message RefreshResponse {
  string token = 1;
}
```

Comando de geração:

```bash
protoc \
  --dart_out=grpc:lib/src/generated \
  -Iprotos \
  protos/auth.proto
```

**Resultado:** Produz `lib/src/generated/auth.pbgrpc.dart` (stub do cliente) e `lib/src/generated/auth.pb.dart` (mensagens).

**Runtime necessário:**
- `package:protobuf` — tipos base para mensagens (já incluído como dependência do `grpc`).

---

### 2.3 Envio de Metadata (Headers) por Chamada

**Contexto:** Injetar token JWT como header `Authorization: Bearer <token>`.

#### Opção A: Metadata Estática via CallOptions

```dart
final opts = CallOptions(
  metadata: {
    'authorization': 'Bearer eyJhbGc...',
    'x-trace-id': '42',
  },
  timeout: Duration(seconds: 10),
);

final response = await authStub.someRpc(
  MyRequest(),
  options: opts,
);
```

#### Opção B: Metadata Dinâmica via MetadataProvider

Para injetar o token dinamicamente (útil se o token muda após refresh):

```dart
// Provider function — chamada uma vez por RPC
Future<void> addAuthToken(Map<String, String> metadata, String uri) async {
  final token = await tokenStorage.getToken();
  metadata['authorization'] = 'Bearer $token';
}

final dynamicOpts = CallOptions(
  providers: [addAuthToken],
);

final response = await authStub.login(
  LoginRequest(),
  options: dynamicOpts,
);
```

#### Opção C: Metadata Combinada (Merge)

```dart
final staticOpts = CallOptions(
  metadata: {'x-version': '1'},
  timeout: Duration(seconds: 10),
);

final dynamicOpts = CallOptions(
  providers: [addAuthToken],
);

final merged = staticOpts.mergedWith(dynamicOpts);

final response = await authStub.login(
  LoginRequest(),
  options: merged,
);
```

#### Opção D: gRPC-Web com CORS

```dart
final webOpts = WebCallOptions(
  metadata: {'authorization': 'Bearer <token>'},
  bypassCorsPreflight: true,   // evita preflight (HEAD request)
  withCredentials: true,        // envia cookies se necessário
  timeout: Duration(seconds: 10),
);

final response = await authStub.login(
  LoginRequest(),
  options: webOpts,
);
```

---

### 2.4 Interceptors de Cliente

**Contexto:** Injetar token, registrar chamadas, ou re-tentar após falha.

#### Implementar um ClientInterceptor

> ⚠️ **Assinatura correta:** `interceptUnary` **retorna `ResponseFuture<R>` de forma
> síncrona** (não é `async`/`async*` e não pode usar `await` no corpo). Para injetar
> token use um `CallOptions(providers: [...])` (assíncrono, resolvido por chamada) —
> o jeito idiomático de obter um token possivelmente novo. **Não** tente fazer o
> *retry após refresh* dentro do `interceptUnary` (a assinatura síncrona torna isso
> frágil): orquestre o refresh+retry no `AuthGrpcDatasource`/`AuthService` da Frente B,
> capturando `GrpcError(unauthenticated)`, chamando o `RefreshTokenUsecase` e refazendo
> a chamada. Mantém o fluxo dentro do padrão `return_success_or_error`.

```dart
import 'package:grpc/grpc.dart';

/// Injeta o access token corrente em cada RPC. O token é resolvido por um
/// provider assíncrono (lê o SessionService), então sempre pega o valor atual
/// — inclusive após um refresh.
class AuthTokenInterceptor implements ClientInterceptor {
  final Future<String?> Function() readAccessToken;
  AuthTokenInterceptor(this.readAccessToken);

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    final withAuth = options.mergedWith(
      CallOptions(providers: [
        (metadata, _) async {
          final token = await readAccessToken();
          if (token != null) metadata['authorization'] = 'Bearer $token';
        },
      ]),
    );
    return invoker(method, request, withAuth); // síncrono: retorna ResponseFuture
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) => invoker(method, requests, options);
}

// Usar com stub
final stub = AuthServiceClient(channel, interceptors: [
  AuthTokenInterceptor(() => inject<SessionService>().token),
]);
```

---

### 2.5 Tratamento de Erro (GrpcError e StatusCode)

**Padrão de Tratamento:**

```dart
import 'package:grpc/grpc.dart';

try {
  final response = await authStub.login(
    LoginRequest()..email = 'user@example.com',
  );
  print('Sucesso: ${response.token}');
} on GrpcError catch (e) {
  // e.code: StatusCode enum
  // e.codeName: String (ex: 'UNAUTHENTICATED')
  // e.message: String com descrição do erro
  // e.details: List<GeneratedMessage> (detalhes estruturados do google.rpc)
  // e.trailers: Map<String, String> (headers de resposta)

  switch (e.code) {
    case StatusCode.unauthenticated:
      // 16 — credenciais ausentes ou inválidas
      print('Falha de autenticação: ${e.message}');
      // Ação: limpar token e pedir novo login
      break;

    case StatusCode.invalidArgument:
      // 3 — argumento inválido (ex: email vazio)
      print('Entrada inválida: ${e.message}');
      // Ação: mostrar erro de validação ao usuário
      break;

    case StatusCode.unavailable:
      // 14 — servidor não alcançável
      print('Servidor indisponível, tente mais tarde');
      // Ação: retry com backoff exponencial
      break;

    case StatusCode.permissionDenied:
      // 7 — sem permissão
      print('Sem permissão: ${e.message}');
      break;

    default:
      print('Erro ${e.codeName} (${e.code}): ${e.message}');
      if (e.details.isNotEmpty) {
        print('Detalhes: ${e.details}');
      }
      break;
  }
} catch (e) {
  // Exceção não-gRPC (ex: timeout de rede)
  print('Erro não-gRPC: $e');
}
```

**Códigos de Status Mais Comuns:**

| StatusCode | Código | Significado |
|---|---|---|
| `unauthenticated` | 16 | Credenciais ausentes ou inválidas |
| `permissionDenied` | 7 | Credenciais válidas mas sem permissão |
| `unavailable` | 14 | Servidor não alcançável |
| `invalidArgument` | 3 | Argumento de entrada inválido |
| `notFound` | 5 | Recurso não encontrado |
| `internalError` | 13 | Erro interno do servidor |
| `deadlineExceeded` | 4 | Timeout da chamada |

---

### 2.6 Limitações do gRPC-Web no Browser

**Suportado:**
- ✅ Chamadas **unárias** (request → response)
- ✅ **Server-streaming** (request → stream de responses)

**Não Suportado:**
- ❌ **Client-streaming** (stream de requests → response)
- ❌ **Bidirectional-streaming** (stream de requests ↔ stream de responses)

**Exemplo Válido (Server-Streaming):**

```dart
// Proto: rpc ListItems(Filter) returns (stream Item);

final stream = authStub.listItems(ListItemsRequest()..filter = 'active');

await for (final item in stream) {
  print('Item: ${item.name}');
}
```

**Por quê?** O browser usa HTTP/1.1 ou HTTP/2 com XMLHttpRequest, que não suportam multiplexing bidirecional eficiente. A gRPC-Web usa HTTP POST para requests e contorna essas limitações com unary e server-streaming.

---

## 3. APIs Depreciadas e Breaking Changes Recentes

### Versão ~4.0.0 (Atual)
- ✅ Sem breaking changes relevantes em relação à 3.x
- ✅ `GrpcWebClientChannel` é a forma moderna e recomendada
- ✅ `CallOptions` e `WebCallOptions` são estáveis

### Versão 3.x → 4.x
- **Mudança Menor:** A assinatura de `interceptors` no cliente pode ter evoluído, mas o padrão `ClientInterceptor` permanece compatível.
- **Recomendação:** Se ainda usar versão 3.x, atualizar para 4.x é seguro e recomendado.

---

## 4. Histórico de Atualizações

### 2026-06-14 — Criação Inicial
- Documentação coletada via Context7 (`/grpc/grpc-dart`).
- Versão recomendada: ~4.0.0 (✅ ATUALIZADA).
- Cobertos 6 recursos principais: GrpcWebClientChannel, geração de stubs, metadata, interceptors, tratamento de erro, limitações gRPC-Web.
- Exemplos Dart funcionais para cada padrão.
- Direcionado para smart-core-admin (Flutter Web/WASM) e AuthService da runtime_api.

---

## 5. Referências Rápidas

- **Documentação Oficial:** https://grpc.io/docs/languages/dart/
- **GitHub (grpc-dart):** https://github.com/grpc/grpc-dart
- **Pub.dev:** https://pub.dev/packages/grpc
- **Protocol Buffers:** https://developers.google.com/protocol-buffers/docs/darttutorial
- **gRPC-Web Spec:** https://github.com/grpc/grpc-web

