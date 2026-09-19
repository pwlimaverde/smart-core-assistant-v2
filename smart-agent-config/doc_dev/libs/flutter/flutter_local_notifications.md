# flutter_local_notifications

- **Versão Recomendada:** 22.3.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-19
- **Propósito no Projeto:** Notificação nativa do Windows quando uma conversa é atribuída ao atendente — alerta visual integrado ao SO, com suporte a cliques para navegar até a conversa.
- **Documentação Oficial:** https://pub.dev/packages/flutter_local_notifications

---

## Histórico de Atualizações

- **2026-09-19** — Documentação inicial criada. Plugin recomendado por suporte ativo (22.3.1, atualizado há 6 dias), comunidade grande (2.7k stars), compatibilidade com Web (via import condicional) e API robusta de callbacks.

---

## 1. Instalação

```yaml
# pubspec.yaml
dependencies:
  flutter_local_notifications: ^22.3.1
```

Plataformas suportadas: Android, iOS, macOS, Linux, **Windows**, Web.

---

## 2. Inicialização no Windows

A inicialização no Windows requer três parâmetros obrigatórios:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final localNotifications = FlutterLocalNotificationsPlugin();

void inicializarNotificacoes() async {
  const windowsSettings = WindowsInitializationSettings(
    appName: 'Smart Core Assistant',
    appUserModelId: 'com.smartcore.assistant', // AUMID único do app
    guid: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d', // GUID único (gere em https://www.uuidgenerator.net/)
  );

  const initializationSettings = InitializationSettings(
    windows: windowsSettings,
  );

  await localNotifications.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: _onNotificationTapped,
  );
}

void _onNotificationTapped(NotificationResponse response) {
  // Callback quando o usuário toca na notificação
  final String? payload = response.payload;
  if (payload != null) {
    // Extrair dados e navegar para a conversa
    _handleNotificationPayload(payload);
  }
}

void _handleNotificationPayload(String payload) {
  // Exemplo: payload = '{"conversationId":"abc123"}'
  final data = jsonDecode(payload);
  final conversationId = data['conversationId'] as String?;
  if (conversationId != null) {
    // Navegar para a tela de conversa
    navigatorKey.currentState?.pushNamed(
      '/conversations/$conversationId',
    );
  }
}
```

---

## 3. Envio de Notificação Simples

```dart
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> enviarNotificacaoConversa(
  String conversationId,
  String operadorNome,
) async {
  const notificationDetails = NotificationDetails(
    windows: WindowsNotificationDetails(
      actions: [
        const AndroidNotificationAction(
          'default',
          'Abrir',
        ),
      ],
    ),
  );

  final payload = jsonEncode({
    'conversationId': conversationId,
  });

  await localNotifications.show(
    conversationId.hashCode, // ID único da notificação
    'Nova conversa atribuída', // Título
    'Operador $operadorNome atribuiu uma conversa para você', // Corpo
    notificationDetails,
    payload: payload,
  );
}
```

---

## 4. Padrão Recomendado: Singleton com Gerenciamento de Ciclo

```dart
class NotificationsService {
  static final NotificationsService _instance = NotificationsService._internal();

  factory NotificationsService() {
    return _instance;
  }

  NotificationsService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const windowsSettings = WindowsInitializationSettings(
      appName: 'Smart Core Assistant',
      appUserModelId: 'com.smartcore.assistant',
      guid: '1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d',
    );

    const initSettings = InitializationSettings(
      windows: windowsSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleResponse,
    );

    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    try {
      final data = jsonDecode(payload);
      final conversationId = data['conversationId'] as String?;
      if (conversationId != null) {
        // Delegar navegação para a camada de UI
        _navigateToConversation(conversationId);
      }
    } catch (e) {
      print('Erro ao processar notificação: $e');
    }
  }

  Future<void> mostrarNotificacao({
    required String titulo,
    required String corpo,
    required String conversationId,
  }) async {
    if (!_initialized) await initialize();

    final payload = jsonEncode({
      'conversationId': conversationId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    const details = NotificationDetails(
      windows: WindowsNotificationDetails(),
    );

    await _plugin.show(
      conversationId.hashCode,
      titulo,
      corpo,
      details,
      payload: payload,
    );
  }

  Future<void> cancelar(String conversationId) async {
    await _plugin.cancel(conversationId.hashCode);
  }

  void _navigateToConversation(String conversationId) {
    // Implementar lógica de navegação
    // Pode usar: navigatorKey.currentState?.pushNamed(...)
  }
}
```

---

## 5. Caveats Críticos e Limitações

### ⚠️ Empacotamento sem MSIX (ZIP simples)

O Windows permite notificações em aplicativos não empacotados (ZIP), **mas com restrições**:
- ✅ **Funciona:** Mostrar notificações simples com `show()`
- ❌ **Não funciona:** Cancelar notificações ativas com `cancel()`, recuperar histórico com `getActiveNotifications()`
- A razão: Windows exige package identity (MSIX) para gerenciar o repositório de notificações.

**Impacto prático:** Para uma aplicação distribuída como ZIP puro, use notificações de **disparo único** sem preocupação em cancelar. Se precisar gerenciar histórico (ex: evitar duplicatas), considere usar a Store do Windows ou empacotar como MSIX.

### ⚠️ Compatibilidade com Flutter Web (import condicional obrigatório)

O plugin **não suporta Web** diretamente. Se o app tem build web, use import condicional:

```dart
// Exemplo: notificacoes_service.dart

// Importação condicional
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'notificacoes_stub.dart' as notifications;

// Ou, no início do arquivo:
import 'dart:io' show Platform;

class NotificationsService {
  static final NotificationsService _instance = NotificationsService._internal();

  factory NotificationsService() {
    return _instance;
  }

  NotificationsService._internal();

  late final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Pular inicialização em Web
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    // Resto da inicialização (Windows/Desktop)
    // ...
  }

  Future<void> mostrarNotificacao({...}) async {
    if (kIsWeb) {
      // Usar alternativa em Web (ex: snackbar, toast da web)
      return;
    }
    // Resto do código...
  }
}
```

**Importar necessário:**
```dart
import 'package:flutter/foundation.dart' show kIsWeb;
```

**No `pubspec.yaml`, marque o plugin como desktop-only se usar `flutter_web_plugins`:**
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  # Não incluir flutter_local_notifications em web builds
```

Alternativamente, configure a compilação web para excluir:
```bash
flutter build web --dart-define-from-file=web.env
```

### ⚠️ GUID e AUMID são obrigatórios no Windows

- **`appName`:** Nome visível da aplicação (usado no painel de notificações do Windows)
- **`appUserModelId` (AUMID):** Identificador único do modelo; padrão: `company.app_name` (ex: `com.smartcore.assistant`)
- **`guid`:** Identificador único global da notificação; gere em https://www.uuidgenerator.net/

Sem esses valores, o Windows rejeitará a inicialização.

### ⚠️ Instabilidade em eventos rápidos

Se disparar múltiplas notificações em sequência rápida (< 100ms), algumas podem ser **engolidas** pelo sistema operacional (batching nativo do Windows). Implemente **debounce** ou **throttle** ao disparar notificações em resposta a eventos do servidor:

```dart
Timer? _notificationDebounce;

void _disparar(String conversationId, String operadorNome) {
  _notificationDebounce?.cancel();
  _notificationDebounce = Timer(const Duration(milliseconds: 500), () async {
    await NotificationsService().mostrarNotificacao(
      titulo: 'Nova conversa',
      corpo: 'Atribuída a $operadorNome',
      conversationId: conversationId,
    );
  });
}
```

---

## 6. Notas de Compatibilidade

- **Windows:** Suportado plenamente. Usa C++/WinRT para integração com o toast notification center nativo. Requer embedding padrão do Flutter (sem configuração extra).
- **Desktop (Linux, macOS):** Também suportado, com APIs semelhantes (mas sem AUMID).
- **Web:** Não suportado. Use import condicional + fallback (snackbar/toast web) ou exclua do build web.
- **Sem bateria/performance:** Plugin é leve; o custo vem de gerenciar callbacks, não da notificação em si.

---

## 7. Referências

| Recurso | Link |
|---------|------|
| Pub.dev | https://pub.dev/packages/flutter_local_notifications |
| Repositório | https://github.com/MaikuB/flutter_local_notifications |
| API docs | https://pub.dev/documentation/flutter_local_notifications/latest/ |
| Gerador UUID | https://www.uuidgenerator.net/ |
| Documentação Windows Toast | https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-tile-notification |
