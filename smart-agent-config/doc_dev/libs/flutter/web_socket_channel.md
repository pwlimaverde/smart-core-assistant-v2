# Web Socket Channel (web_socket_channel)

- **Versão Recomendada:** 2.4.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Conexão WebSocket de alta performance no Flutter para receber eventos de mensagens e movimentações em tempo real enviadas pela `runtime_api`.
- **Documentação Oficial:** [https://pub.dev/packages/web_socket_channel](https://pub.dev/packages/web_socket_channel)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 é um sistema em tempo real. O painel do atendente no Flutter não deve fazer polling para buscar novas mensagens. Ele mantém um WebSocket ativo com a `runtime_api` (Rust) que despacha atualizações instantaneamente.

O pacote **`web_socket_channel`** fornece uma abstração multiplataforma baseada em Streams para ler e escrever dados nos sockets com segurança.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Conexão Segura e Tratamento de Streams
A conexão deve passar o token de autenticação e o `tenant_id` no handshake. O canal WebSocket expõe uma Stream que deve ser mapeada para DTOs Dart.

```dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';

class RealtimeClient {
  WebSocketChannel? _channel;
  
  void connect(String tenantId, String token) {
    final wsUri = Uri.parse("wss://api.smartcore.com.br/ws?tenant=$tenantId&auth=$token");
    
    // Inicializa o canal WebSocket
    _channel = WebSocketChannel.connect(wsUri);
    
    // Escuta a Stream de dados recebidos
    _channel!.stream.listen(
      (data) {
        _handleIncomingMessage(data);
      },
      onError: (error) {
        logError("Erro na conexão WebSocket: $error");
        _reconnect(tenantId, token);
      },
      onDone: () {
        logInfo("Conexão WebSocket encerrada pelo servidor.");
        _reconnect(tenantId, token);
      },
    );
  }

  void _handleIncomingMessage(dynamic data) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(data as String);
      final event = RealtimeEvent.fromJson(jsonMap);
      
      // Despacha o evento para a ViewModel ou BLoC correspondente
      eventBus.emit(event);
    } catch (e) {
      logError("Erro ao processar dados do WS: $e");
    }
  }

  void disconnect() {
    _channel?.sink.close(status.goingAway);
  }
}
```

### 2.2 Estratégia de Reconexão Automática
Quedas de conexão no Windows Desktop são comuns (suspensão de máquina, oscilação de Wi-Fi). É obrigatório implementar um mecanismo de **Exponential Backoff** para reconectar automaticamente em caso de falha.

```dart
int _reconnectDelaySeconds = 2;

void _reconnect(String tenantId, String token) {
  // Aguarda delay exponencial (2s, 4s, 8s, máximo 30s) antes de tentar reconectar
  Future.delayed(Duration(seconds: _reconnectDelaySeconds), () {
    logInfo("Tentando reconectar ao WebSocket...");
    connect(tenantId, token);
    
    // Incrementa o delay
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(2, 30);
  });
}
```

### 2.3 Resiliência e Sincronização após Reconexão
Sempre que a conexão WebSocket cair e for restabelecida com sucesso, a aplicação Dart deve executar uma chamada de sincronização HTTP/gRPC tradicional (`fetchTickets`, `fetchMessages`) para recuperar as mensagens que foram entregues no servidor durante o período em que o cliente esteve offline, evitando lacunas no chat.
