import 'package:meta/meta.dart';

import '../../domain/model/mensagem_thread.dart';

/// Estado da conexão realtime do chat lateral (WS-6.3): exibido como
/// indicador visual (ex.: badge "reconectando...") independente do
/// [ViewState] do thread em si.
enum ChatConnectionStatus { conectando, conectado, reconectando, caido }

/// View-model composto do chat lateral: thread carregado + estado da conexão
/// realtime, que evolui independente do carregamento do histórico.
@immutable
final class ChatViewModel {
  final int atendimentoId;
  final List<MensagemThread> mensagens;
  final ChatConnectionStatus connectionStatus;

  const ChatViewModel({
    required this.atendimentoId,
    required this.mensagens,
    required this.connectionStatus,
  });

  ChatViewModel copyWith({
    List<MensagemThread>? mensagens,
    ChatConnectionStatus? connectionStatus,
  }) => ChatViewModel(
    atendimentoId: atendimentoId,
    mensagens: mensagens ?? this.mensagens,
    connectionStatus: connectionStatus ?? this.connectionStatus,
  );
}
