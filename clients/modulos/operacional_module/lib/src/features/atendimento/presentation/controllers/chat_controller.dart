import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/get_thread_parameters.dart';
import '../../domain/parameters/presenca_parameters.dart';
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

  /// B6 — opcional: sem ele a conversa abre e só não marca a leitura.
  final MarcarAtendimentoLidoUsecase? _marcarLido;

  /// P3 — opcional pelo mesmo motivo: sem ele a conversa funciona e o contato
  /// apenas não vê o "digitando...".
  final EnviarPresencaUsecase? _presenca;

  /// Dependências como private named parameters (Dart 3.12): o chamador usa
  /// `getThreadUsecase`/`sendUsecase`/`eventos`, os campos ficam privados.
  ChatController({
    required this._getThreadUsecase,
    required this._sendUsecase,
    required this._eventos,
    MarcarAtendimentoLidoUsecase? marcarLidoUsecase,
    EnviarPresencaUsecase? presencaUsecase,
  }) : _marcarLido = marcarLidoUsecase,
       _presenca = presencaUsecase;

  static const _backoffBase = Duration(seconds: 1);
  static const _backoffMax = Duration(seconds: 30);
  final _random = Random();

  StreamSubscription<AtendimentoEvento>? _subscription;
  Timer? _reconnectTimer;
  int _tentativa = 0;
  bool _encerrado = false;
  int? _atendimentoId;

  /// Id da mensagem do contato mais recente já marcada como lida: evita ir
  /// ao servidor a cada rolagem quando nada novo chegou.
  int? _ultimaMarcada;

  /// P3 — quando a última presença do atendente foi enviada, e o timer que
  /// apaga a presença do contato quando ela para de ser renovada.
  DateTime? _ultimaPresencaEnviada;
  Timer? _limpezaDaPresenca;

  /// P10 — sobe a cada vez que a IA grava campos na ficha desta conversa.
  ///
  /// A v1 publicava `custom_field.updated` e a ficha aberta se atualizava; a v2
  /// gravava em silêncio. É um contador, e não o dado: a ficha tem controller
  /// próprio, e quem a desenha decide recarregar.
  final camposAtualizados = ValueNotifier<int>(0);

  /// O provedor mantém "digitando" por poucos segundos; renovar a cada tecla
  /// seria uma chamada por caractere, e renovar de menos faz o aviso piscar.
  static const _intervaloDePresenca = Duration(seconds: 4);

  /// Depois disso sem notícia, o "digitando..." some sozinho: o provedor nem
  /// sempre manda o evento de parada.
  static const _validadeDaPresenca = Duration(seconds: 8);

  /// Abre o chat de um atendimento: carrega o histórico e conecta o stream.
  Future<void> abrir(int atendimentoId) async {
    _atendimentoId = atendimentoId;
    _tentativa = 0;
    _ultimaMarcada = null;
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
    final atual = state;
    final citada = atual is SuccessState<ChatViewModel>
        ? atual.data.citando
        : null;
    final res = await _sendUsecase(
      SendOutboundMessageParameters(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
        mensagemCitadaId: citada?.id,
      ),
    );
    // Mandou: não está mais digitando.
    unawaited(pararDeDigitar());
    if (res case Failure(:final error)) return error;
    // A citação vale para UMA resposta: mantê-la faria a próxima mensagem
    // responder a mesma bolha sem que ninguém tenha pedido.
    cancelarCitacao();
    await _recarregarThread();
    return null;
  }

  /// P3 — a pessoa está escrevendo: avisa o contato, no máximo uma vez a
  /// cada [_intervaloDePresenca].
  ///
  /// Falha em silêncio de propósito: quem está digitando não pode receber um
  /// erro porque o "digitando..." não chegou.
  Future<void> avisarQueEstaDigitando({bool gravandoAudio = false}) async {
    final usecase = _presenca;
    final atendimentoId = _atendimentoId;
    if (usecase == null || atendimentoId == null) return;
    final agora = DateTime.now();
    final ultima = _ultimaPresencaEnviada;
    if (!gravandoAudio &&
        ultima != null &&
        agora.difference(ultima) < _intervaloDePresenca) {
      return;
    }
    _ultimaPresencaEnviada = agora;
    await usecase(
      EnviarPresencaParameters(
        atendimentoId: atendimentoId,
        situacao: gravandoAudio ? 'recording' : 'composing',
      ),
    );
  }

  /// P3 — parou de escrever (enviou ou desistiu).
  Future<void> pararDeDigitar() async {
    final usecase = _presenca;
    final atendimentoId = _atendimentoId;
    if (usecase == null || atendimentoId == null) return;
    if (_ultimaPresencaEnviada == null) return;
    _ultimaPresencaEnviada = null;
    await usecase(
      EnviarPresencaParameters(
        atendimentoId: atendimentoId,
        situacao: 'paused',
      ),
    );
  }

  /// P2 — a próxima resposta vai citar [mensagem].
  void citar(MensagemThread mensagem) {
    final atual = state;
    if (atual is! SuccessState<ChatViewModel>) return;
    emit(SuccessState(atual.data.copyWith(citando: mensagem)));
  }

  /// P2 — desiste de citar.
  void cancelarCitacao() {
    final atual = state;
    if (atual is! SuccessState<ChatViewModel>) return;
    if (atual.data.citando == null) return;
    emit(SuccessState(atual.data.copyWith(limparCitacao: true)));
  }

  /// P2 — a pessoa rolou até o topo: carrega o trecho anterior do histórico.
  ///
  /// Usa o id da bolha mais antiga como cursor, e não o total já carregado:
  /// enquanto se lê o histórico a conversa continua recebendo, e um offset
  /// mudaria de significado a cada mensagem que chega.
  Future<void> carregarAntigas() async {
    final atendimentoId = _atendimentoId;
    final atual = state;
    if (atendimentoId == null || atual is! SuccessState<ChatViewModel>) return;
    final vm = atual.data;
    if (vm.carregandoAntigas || vm.fimDoHistorico || vm.mensagens.isEmpty) {
      return;
    }
    emit(SuccessState(vm.copyWith(carregandoAntigas: true)));

    final res = await _getThreadUsecase(
      GetThreadParameters(
        atendimentoId: atendimentoId,
        beforeId: vm.mensagens.first.id,
      ),
    );
    final depois = state;
    if (depois is! SuccessState<ChatViewModel>) return;
    switch (res) {
      case Success(:final value):
        emit(
          SuccessState(
            depois.data.copyWith(
              mensagens: [...value, ...depois.data.mensagens],
              carregandoAntigas: false,
              // Página vazia = chegou ao começo da conversa.
              fimDoHistorico: value.isEmpty,
            ),
          ),
        );
      case Failure():
        // Falhar ao buscar histórico não derruba a conversa aberta: a pessoa
        // continua lendo e respondendo o que já está na tela.
        emit(SuccessState(depois.data.copyWith(carregandoAntigas: false)));
    }
  }

  /// B6 (N9 E4) — a pessoa está vendo o fim da conversa: marca como lido o
  /// que o contato mandou.
  ///
  /// Quem chama é a tela, que sabe se o fim está à vista — abrir a conversa
  /// rolada para cima não conta como leitura. Só vai ao servidor quando há
  /// mensagem do contato mais nova que a última marcada. Falha é silenciosa:
  /// a conversa continua utilizável, e a próxima leitura tenta de novo.
  Future<void> marcarComoLida() async {
    final usecase = _marcarLido;
    final atendimentoId = _atendimentoId;
    final atual = state;
    if (usecase == null ||
        atendimentoId == null ||
        atual is! SuccessState<ChatViewModel>) {
      return;
    }
    final doContato = atual.data.mensagens
        // "Do contato" = nem atendente nem bot, a mesma regra do balão e do
        // servidor.
        .where((m) => m.remetente != 'atendente' && m.remetente != 'bot')
        .map((m) => m.id);
    if (doContato.isEmpty) return;
    final maisRecente = doContato.reduce(max);
    final anterior = _ultimaMarcada;
    if (anterior != null && maisRecente <= anterior) return;
    _ultimaMarcada = maisRecente;
    final res = await usecase(
      MarcarAtendimentoLidoParameters(atendimentoId: atendimentoId),
    );
    if (res is Failure) _ultimaMarcada = anterior;
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
    // P3 — presença não é mensagem: muda uma linha do cabeçalho e não custa
    // uma recarga da conversa inteira.
    if (evento.tipo == 'whatsapp.presenca') {
      if (evento.atendimentoId == _atendimentoId) {
        _aplicarPresencaDoContato('${evento.payload['situacao'] ?? ''}');
      }
      return;
    }
    // P10 — campos que a IA preencheu mudam a ficha, não a conversa: recarregar
    // o thread por isso seria I/O à toa.
    if (evento.tipo == 'atendimento.campos_atualizados') {
      if (evento.atendimentoId == _atendimentoId) camposAtualizados.value++;
      return;
    }
    // Só recarrega o thread quando o evento é do atendimento aberto — evita
    // I/O desnecessário para eventos de outros atendimentos da fila.
    if (evento.atendimentoId == _atendimentoId) {
      unawaited(_recarregarThread());
    }
  }

  void _aplicarPresencaDoContato(String situacao) {
    final atual = state;
    if (atual is! SuccessState<ChatViewModel>) return;
    // "available"/"unavailable" são estado de conexão do contato, não de
    // digitação: para a conversa, valem como "nada acontecendo".
    final exibivel = situacao == 'composing' || situacao == 'recording'
        ? situacao
        : '';
    if (atual.data.presencaDoContato != exibivel) {
      emit(SuccessState(atual.data.copyWith(presencaDoContato: exibivel)));
    }
    _limpezaDaPresenca?.cancel();
    if (exibivel.isEmpty) return;
    _limpezaDaPresenca = Timer(_validadeDaPresenca, () {
      final agora = state;
      if (agora is SuccessState<ChatViewModel> &&
          agora.data.presencaDoContato.isNotEmpty) {
        emit(SuccessState(agora.data.copyWith(presencaDoContato: '')));
      }
    });
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
        // A recarga traz só a última página. Quem já tinha rolado para cima
        // perderia o histórico carregado se a lista fosse trocada inteira.
        final novos = {for (final m in value) m.id};
        final antigas = atual.data.mensagens.where((m) => !novos.contains(m.id));
        final unidas = [...antigas, ...value]
          ..sort((a, b) => a.id.compareTo(b.id));
        emit(SuccessState(atual.data.copyWith(mensagens: unidas)));
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
    _limpezaDaPresenca?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    camposAtualizados.dispose();
    return super.close();
  }
}
