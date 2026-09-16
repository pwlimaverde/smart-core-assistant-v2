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

  /// P2 — uma página antiga está a caminho (spinner no topo da rolagem).
  final bool carregandoAntigas;

  /// P2 — o começo da conversa já está na tela: rolar mais não busca nada.
  final bool fimDoHistorico;

  /// P2 — a mensagem que a próxima resposta vai citar, se houver.
  final MensagemThread? citando;

  const ChatViewModel({
    required this.atendimentoId,
    required this.mensagens,
    required this.connectionStatus,
    this.carregandoAntigas = false,
    this.fimDoHistorico = false,
    this.citando,
  });

  ChatViewModel copyWith({
    List<MensagemThread>? mensagens,
    ChatConnectionStatus? connectionStatus,
    bool? carregandoAntigas,
    bool? fimDoHistorico,
    MensagemThread? citando,
    // `citando: null` no copyWith seria indistinguível de "não mexer"; este
    // sinalizador é como se cancela a citação.
    bool limparCitacao = false,
  }) => ChatViewModel(
    atendimentoId: atendimentoId,
    mensagens: mensagens ?? this.mensagens,
    connectionStatus: connectionStatus ?? this.connectionStatus,
    carregandoAntigas: carregandoAntigas ?? this.carregandoAntigas,
    fimDoHistorico: fimDoHistorico ?? this.fimDoHistorico,
    citando: limparCitacao ? null : (citando ?? this.citando),
  );
}
