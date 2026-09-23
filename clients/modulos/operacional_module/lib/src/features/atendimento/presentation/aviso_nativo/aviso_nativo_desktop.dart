import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// P16 — notificação nativa do Windows quando uma conversa é atribuída.
///
/// Só aparece com o app fora de foco (quem chama decide): com a janela na
/// frente, o aviso do quadro basta. O clique abre a conversa.
///
/// O texto leva só o fluxo, nunca o conteúdo da mensagem — o aviso do sistema
/// pode aparecer na tela bloqueada.
final class AvisoNativo {
  AvisoNativo._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _pronto = false;

  /// Identidade fixa do app no Windows. O GUID foi gerado uma vez e não muda:
  /// trocá-lo faria o Windows tratar o app como outro e perder as permissões
  /// de notificação que a pessoa já deu.
  static const _aumid = 'br.com.smartcoreassistant.tenant';
  static const _guid = '6f2d8a3e-4b1c-4e9f-9a7d-2c5b8e1f3a60';

  static Future<void> iniciar({
    required void Function(int atendimentoId) aoClicar,
  }) async {
    if (_pronto || !Platform.isWindows) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: 'Smart Core Assistant',
            appUserModelId: _aumid,
            guid: _guid,
          ),
        ),
        onDidReceiveNotificationResponse: (resposta) {
          final id = _idDoPayload(resposta.payload);
          if (id != null) aoClicar(id);
        },
      );
      _pronto = true;
    } catch (_) {
      // Sem permissão ou sem suporte: o aviso do quadro continua existindo.
    }
  }

  static Future<void> mostrar({
    required int atendimentoId,
    required String titulo,
    required String corpo,
  }) async {
    if (!_pronto) return;
    try {
      await _plugin.show(
        id: atendimentoId,
        title: titulo,
        body: corpo,
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
        payload: jsonEncode({'atendimento_id': atendimentoId}),
      );
    } catch (_) {}
  }

  static int? _idDoPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final v = jsonDecode(payload);
      return v is Map ? (v['atendimento_id'] as num?)?.toInt() : null;
    } on FormatException {
      return null;
    }
  }
}
