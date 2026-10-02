# HTTP

- **Versão Recomendada:** 1.2.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Único uso de HTTP cru do `operacional_module` (desde a N9/E1): PUT direto da mídia na URL assinada do R2, fora do gRPC-Web, porque o binário não cabe no envelope. Já está no `pubspec.yaml` (`http: ^1.2.2`).
- **Documentação Oficial:** [https://pub.dev/packages/http](https://pub.dev/packages/http)

---

## 1. Contexto e Uso no Projeto

O pacote `http` é a lib padrão do Dart/Flutter para requisições HTTP/HTTPS. No Smart Core Assistant v2, é usado para:
- **Upload de mídia (áudio/imagem)** via PUT em URLs assinadas (R2/S3)
- Requisições de API com autenticação (Bearer tokens)
- Tratamento de timeouts e retries
- Suporte cross-platform (Windows desktop incluído)

---

## 2. Guia de Uso Rápido

### 2.1 Instalação

```yaml
dependencies:
  http: ^1.2.2
```

### 2.2 Requisições Básicas

```dart
import 'package:http/http.dart' as http;

// GET simples
Future<void> fetchData() async {
  final response = await http.get(
    Uri.parse('https://api.example.com/data'),
    headers: {'Authorization': 'Bearer token'},
  );
  
  if (response.statusCode == 200) {
    print('Sucesso: ${response.body}');
  } else {
    print('Erro: ${response.statusCode}');
  }
}

// POST com body JSON
Future<void> postData() async {
  final response = await http.post(
    Uri.parse('https://api.example.com/data'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'key': 'value'}),
  );
  
  if (response.statusCode == 201) {
    print('Criado: ${response.body}');
  }
}
```

### 2.3 PUT em URL Assinada (R2/S3)

Para fazer upload de arquivo via URL assinada (sem autenticação adicional):

```dart
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> uploadAudioToR2(String filePath, String signedUrl) async {
  final file = File(filePath);
  final bytes = await file.readAsBytes();
  
  final response = await http.put(
    Uri.parse(signedUrl),
    headers: {
      'Content-Type': 'audio/ogg', // ou 'audio/opus' conforme encoder
      'Content-Length': bytes.length.toString(),
    },
    body: bytes,
  );
  
  if (response.statusCode == 200) {
    print('Upload bem-sucedido');
  } else {
    print('Erro: ${response.statusCode} - ${response.body}');
  }
}
```

### 2.4 StreamedRequest para Uploads Grandes

Para uploads com progresso ou requisições muito grandes:

```dart
Future<void> uploadWithProgress(String filePath, String signedUrl) async {
  final file = File(filePath);
  final fileSize = await file.length();
  
  final request = http.StreamedRequest(
    'PUT',
    Uri.parse(signedUrl),
  )
    ..headers['Content-Type'] = 'audio/ogg'
    ..headers['Content-Length'] = fileSize.toString()
    ..bodyBytes = await file.readAsBytes();
  
  final streamedResponse = await request.send();
  
  if (streamedResponse.statusCode == 200) {
    print('Upload concluído');
  } else {
    print('Erro: ${streamedResponse.statusCode}');
  }
}
```

### 2.5 Client com Timeouts

Reutilizar um `Client` com timeouts:

```dart
final client = http.Client();

Future<void> fetchWithTimeout() async {
  try {
    final response = await client.get(
      Uri.parse('https://api.example.com/data'),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Requisição excedeu tempo limite'),
    );
    
    print('Resposta: ${response.statusCode}');
  } finally {
    client.close(); // Importante: liberar recursos
  }
}
```

### 2.6 Requisições com Headers Customizados

```dart
Future<void> customHeaders() async {
  final response = await http.get(
    Uri.parse('https://api.example.com/data'),
    headers: {
      'Authorization': 'Bearer eyJhbGc...',
      'User-Agent': 'SmartCore/1.0',
      'Accept-Language': 'pt-BR',
    },
  );
  
  print('Status: ${response.statusCode}');
  print('Headers: ${response.headers}');
}
```

---

## 3. APIs Principais

| API | Descrição |
|-----|-----------|
| `http.get(uri, {headers})` | GET simples |
| `http.post(uri, {headers, body})` | POST simples |
| `http.put(uri, {headers, body})` | PUT simples |
| `http.patch(uri, {headers, body})` | PATCH simples |
| `http.delete(uri, {headers})` | DELETE simples |
| `http.head(uri, {headers})` | HEAD simples |
| `http.read(uri, {headers})` | GET e retorna body como String |
| `http.readBytes(uri, {headers})` | GET e retorna body como List<int> |
| `StreamedRequest(method, uri)` | Requisição com stream customizado |
| `Client()` | Cliente HTTP reutilizável |
| `Client.close()` | Fechar e liberar conexões |
| `BaseClient` | Base para clientes customizados (retry, proxy) |
| `RetryClient` | Client com retry automático |

---

## 4. Tratamento de Erros

```dart
Future<void> robustRequest() async {
  final client = http.Client();
  
  try {
    final response = await client.put(
      Uri.parse('https://api.example.com/upload'),
      body: <int>[/* bytes */],
    ).timeout(const Duration(seconds: 60));
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Sucesso');
    } else if (response.statusCode == 413) {
      throw Exception('Arquivo muito grande');
    } else if (response.statusCode >= 500) {
      throw Exception('Erro do servidor: ${response.statusCode}');
    } else {
      throw Exception('Erro: ${response.statusCode} - ${response.body}');
    }
  } on TimeoutException {
    print('Requisição expirou');
  } on SocketException {
    print('Erro de conectividade');
  } catch (e) {
    print('Erro desconhecido: $e');
  } finally {
    client.close();
  }
}
```

---

## 5. Composição com RetryClient

Para retry automático com backoff exponencial:

```dart
import 'package:http/retry.dart';

final client = RetryClient(
  http.Client(),
  retries: 3,
  when: (response) {
    // Retry em 5xx ou timeout
    return response.statusCode >= 500 || response.statusCode == 408;
  },
  delay: (retryCount) => Duration(seconds: 1 << retryCount), // 1s, 2s, 4s
);

final response = await client.get(Uri.parse('https://api.example.com/data'));
client.close();
```

---

## 6. Plataformas Suportadas

| Plataforma | Suporte | Notas |
|-----------|---------|-------|
| **Windows Desktop** | ✅ Completo | Usa WinHTTP nativo |
| Web | ✅ Completo | XMLHttpRequest do navegador |
| Android | ✅ Completo | HttpURLConnection |
| iOS | ✅ Completo | NSURLSession |
| macOS | ✅ Completo | NSURLSession |
| Linux | ✅ Completo | curl |

---

## 7. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 1.2.2 | 2026-10-01 | Versão EM_HOMOLOGACAO para upload de mídia via R2 assinado; StreamedRequest para grande escala; suporte Windows estável |

---

## 8. Referências

- **Documentação:** https://pub.dev/packages/http
- **Repositório:** https://github.com/dart-lang/http
- **API Reference:** https://pub.dev/documentation/http/latest/

