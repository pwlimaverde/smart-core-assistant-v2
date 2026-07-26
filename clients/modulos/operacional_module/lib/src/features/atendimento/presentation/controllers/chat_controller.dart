import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/parameters/get_thread_parameters.dart';
import '../../domain/parameters/send_outbound_message_parameters.dart';
import '../../domain/streams/atendimento_evento_stream.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import 'chat_state.dart';

/// Controller do chat lateral (WS-6.3): carrega o thread e consome o stream
/// realtime (`streamAtendimentos`), filtrando pelo [atendimentoId] atual.
///
/// Reconecta com **backoff exponencial + jitter** quando o stream cai (erro ou
/// encerramento), expondo o estado da conexão via [ChatViewModel.connectionStatus]
/// para a UI mostrar um indicador (ex.: "reconectando..."). Erros de stream são
/// logados de forma estruturada (tentativa/backoff), NUNCA o conteúdo do evento
/// (payload pode carregar mensagem/PII).
final class ChatController extends BaseController<ChatViewModel> {
  final GetThreadUsecase _getThreadUsecase;
  final SendOutboundMessageUsecase _sendUsecase;
  final AtendimentoEventoStream _eventos;

  /// Dependências como private named parameters (Dart 3.12): o chamador usa
  /// `getThreadUsecase`/`sendUsecase`/`eventos`, os campos ficam privados.
  ChatController({
    required this._getThreadUsecase,
    required this._sendUsecase,
    required this._eventos,
  });

  static const _backoffBase = Duration(seconds: 1);
  static const _backoffMax = Duration(seconds: 30);
  final _random = Random();

  StreamSubscription<AtendimentoEvento>? _subscription;
  Timer? _reconnectTimer;
  int _tentativa = 0;
  bool _encerrado = false;
  int? _atendimentoId;

  /// Abre o chat de um atendimento: carrega o histórico e conecta o stream.
  Future<void> abrir(int atendimentoId) async {
    _atendimentoId = atendimentoId;
    _tentativa = 0;
    await execute(() async {
      final res = await _getThreadUsecase(
        GetThreadParameters(atendimentoId: atendimentoId),
      );
      return switch (res) {
        Success(:final value) => Success<ChatViewModel, GetThreadError>(
          ChatViewModel(
            atendimentoId: atendimentoId,
            mensagens: value,
            connectionStatus: ChatConnectionStatus.conectando,
          ),
        ),
        // O caso é reconstruído porque Failure<List<MensagemThread>, E> não é um
        // ReturnSuccessOrError<ChatViewModel, E>.
        Failure(:final error) => Failure<ChatViewModel, GetThreadError>(error),
      };
    });
    _conectarStream();
  }

  /// Envia uma mensagem outbound e recarrega o thread em caso de sucesso.
  /// [conteudo] é PII — nunca logado pelo controller.
  Future<SendOutboundMessageError?> enviar(String conteudo) async {
    final atendimentoId = _atendimentoId;
    if (atendimentoId == null) return null;
    final res = await _sendUsecase(
      SendOutboundMessageParameters(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
      ),
    );
    if (res case Failure(:final error)) return error;
    await _recarregarThread();
    return null;
  }

  void _conectarStream() {
    _subscription?.cancel();
    _atualizarStatus(ChatConnectionStatus.conectando);
    _subscription = _eventos.abrir().listen(
      _aoReceberEvento,
      onError: _aoFalharStream,
      onDone: _aoEncerrarStream,
      cancelOnError: true,
    );
  }

  void _aoReceberEvento(AtendimentoEvento evento) {
    _tentativa = 0;
    _atualizarStatus(ChatConnectionStatus.conectado);
    // Só recarrega o thread quando o evento é do atendimento aberto — evita
    // I/O desnecessário para eventos de outros atendimentos da fila.
    if (evento.atendimentoId == _atendimentoId) {
      unawaited(_recarregarThread());
    }
  }

  void _aoFalharStream(Object error, StackTrace stackTrace) {
    // Log estruturado de reconexão — NUNCA o conteúdo/payload do evento (pode
    // carregar mensagem/PII). Só registra a tentativa para diagnóstico.
    developer.log(
      'stream de atendimentos caiu; agendando reconexão',
      name: 'operacional_module.chat',
      error: 'tentativa=$_tentativa',
    );
    _agendarReconexao();
  }

  void _aoEncerrarStream() {
    if (_encerrado) return;
    _agendarReconexao();
  }

  void _agendarReconexao() {
    if (_encerrado) return;
    _atualizarStatus(ChatConnectionStatus.reconectando);
    _tentativa++;
    final delay = _proximoBackoff(_tentativa);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_encerrado) _conectarStream();
    });
  }

  /// Backoff exponencial (base 1s, teto 30s) com jitter de até 20% para
  /// evitar reconexões sincronizadas de múltiplos clientes.
  Duration _proximoBackoff(int tentativa) {
    final exponencial = _backoffBase * pow(2, tentativa - 1).toInt();
    final limitado = exponencial > _backoffMax ? _backoffMax : exponencial;
    final jitterMs = (_random.nextDouble() * 0.2 * limitado.inMilliseconds)
        .toInt();
    return limitado + Duration(milliseconds: jitterMs);
  }

  Future<void> _recarregarThread() async {
    final atendimentoId = _atendimentoId;
    if (atendimentoId == null) return;
    final res = await _getThreadUsecase(
      GetThreadParameters(atendimentoId: atendimentoId),
    );
    if (res case Success(:final value)) {
      final atual = state;
      if (atual is SuccessState<ChatViewModel>) {
        emit(SuccessState(atual.data.copyWith(mensagens: value)));
      }
    }
  }

  void _atualizarStatus(ChatConnectionStatus status) {
    final atual = state;
    if (atual is SuccessState<ChatViewModel>) {
      emit(SuccessState(atual.data.copyWith(connectionStatus: status)));
    }
  }

  @override
  Future<void> close() {
    _encerrado = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
