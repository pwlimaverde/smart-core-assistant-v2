import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/model/midia_mensagem.dart';
import '../../domain/model/ordem_das_mensagens.dart';
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

  /// P1.1-A — pedidos de recarga dentro desta janela viram uma recarga só.
  ///
  /// Um envio gera vários eventos em sequência (`mensagem.enviada` do motor
  /// local e do servidor, os ticks, a resposta do bot); cada um recarregava a
  /// conversa inteira — 4 a 6 `GetThread` por mensagem.
  static const _janelaDeRecarga = Duration(milliseconds: 300);

  /// P1.1-A — sob fluxo contínuo de eventos a janela seria adiada para sempre;
  /// o teto, contado do primeiro pedido, garante que a conversa se atualiza.
  static const _tetoDeRecarga = Duration(seconds: 1);

  /// P1.1-A — quanto tempo depois de um envio as recargas ainda contam para
  /// ele no contador [_recargasPorEnvio] (o instrumento do aceite).
  static const _janelaDeMedicao = Duration(seconds: 5);

  /// P1.1-A (C17) — a URL assinada vale 15 min; acima de 80% disso a mídia
  /// antiga é trocada pela nova mesmo sendo o mesmo objeto.
  static const _frescorDaMidia = Duration(minutes: 12);

  /// P1.1-A — o agendador de recarga: o timer da janela (reiniciado a cada
  /// pedido) e o do teto (armado no primeiro pedido). O que vencer primeiro
  /// dispara a recarga e desarma o outro.
  ///
  /// Dois timers no lugar de `DateTime.now()`: o teto fica testável com
  /// `fakeAsync`, que adianta timers mas não o relógio de parede.
  Timer? _recargaAgendada;
  Timer? _tetoDaRecarga;
  String _motivoDaRecarga = '';

  /// P1.1-A — recargas efetivas desde o último envio; `null` fora da janela
  /// de medição.
  int? _recargasPorEnvio;
  Timer? _medicaoDoEnvio;

  /// Abre o chat de um atendimento: carrega o histórico e conecta o stream.
  Future<void> abrir(int atendimentoId) async {
    _atendimentoId = atendimentoId;
    _tentativa = 0;
    _ultimaMarcada = null;
    // A carga completa abaixo cobre qualquer recarga que estava agendada.
    _recargaAgendada?.cancel();
    _recargaAgendada = null;
    _tetoDaRecarga?.cancel();
    _tetoDaRecarga = null;
    await execute(() async {
      final res = await _getThreadUsecase(
        GetThreadParameters(atendimentoId: atendimentoId),
      );
      return switch (res) {
        Success(:final value) => Success<ChatViewModel, GetThreadError>(
          ChatViewModel(
            atendimentoId: atendimentoId,
            // P1 — o usecase ordena por horário; a tela usa a ordem de
            // exibição (pendente local sempre no fim).
            mensagens: ordenarParaExibir(value),
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

  /// P1.1-A — pede uma recarga da conversa sem trocar a tela pelo spinner.
  ///
  /// Para quem muda a conversa por fora do controller (o envio de anexo da
  /// página): passa pelo mesmo agendador dos eventos, então o
  /// `mensagem.enviada` que chega logo depois não custa outra recarga.
  void recarregar({String motivo = 'manual'}) {
    if (motivo.startsWith('envio')) _iniciarMedicaoDoEnvio();
    _agendarRecarga(motivo);
  }

  /// Envia uma mensagem outbound e agenda a recarga do thread em caso de
  /// sucesso. [conteudo] é PII — nunca logado pelo controller.
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
    // P1.1-A — agenda em vez de recarregar já: os eventos do próprio envio
    // chegam em seguida e entram na mesma recarga.
    _iniciarMedicaoDoEnvio();
    _agendarRecarga('envio');
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
    // P1 — o cursor é a confirmada mais antiga: uma pendente local (id
    // negativo) não existe no servidor e não serve de cursor.
    final maisAntiga = vm.mensagens.where((m) => m.id > 0).firstOrNull;
    if (vm.carregandoAntigas || vm.fimDoHistorico || maisAntiga == null) {
      return;
    }
    emit(SuccessState(vm.copyWith(carregandoAntigas: true)));

    final res = await _getThreadUsecase(
      GetThreadParameters(
        atendimentoId: atendimentoId,
        beforeId: maisAntiga.id,
      ),
    );
    if (isClosed) return;
    final depois = state;
    if (depois is! SuccessState<ChatViewModel>) return;
    switch (res) {
      case Success(:final value):
        emit(
          SuccessState(
            depois.data.copyWith(
              // A versão que está na tela vem por último: em id repetido,
              // é ela que fica.
              mensagens: ordenarParaExibir([
                ...value,
                ...depois.data.mensagens,
              ]),
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
    // P1.1-B/C18 — o servidor descartou eventos porque este assinante atrasou.
    // Não traz `atendimento_id`: não dá para saber se algum era desta
    // conversa, então recarrega uma vez (pelo agendador) por garantia.
    if (evento.tipo == 'stream.defasado') {
      _agendarRecarga('defasado');
      return;
    }
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
    if (evento.tipo == 'atendimento.campos_atualizados' ||
        // P14 — etiqueta posta pela IA também é mudança da ficha.
        evento.tipo == 'atendimento.etiquetas_atualizadas') {
      if (evento.atendimentoId == _atendimentoId) camposAtualizados.value++;
      return;
    }
    // Só recarrega o thread quando o evento é do atendimento aberto — evita
    // I/O desnecessário para eventos de outros atendimentos da fila.
    if (evento.atendimentoId != _atendimentoId) return;
    // P1.1-A (C16) — tick novo é uma bolha só: com o `mensagem_id` no payload
    // o status é aplicado no lugar, sem ir ao servidor. Sem ele (formato
    // antigo) ou sem a bolha na tela, cai na recarga agendada.
    if (evento.tipo == 'mensagem.status_atualizado' &&
        _aplicarStatusDeEntrega(evento.payload)) {
      return;
    }
    _agendarRecarga(evento.tipo);
  }

  /// P1.1-A — aplica o `mensagem.status_atualizado` na bolha correspondente.
  ///
  /// Devolve `false` quando não deu para aplicar localmente (sem
  /// `mensagem_id`, status desconhecido, bolha fora da tela) — quem chama
  /// recarrega. Status que regride (um `delivered` atrasado depois do `read`)
  /// é ignorado: os eventos não chegam necessariamente em ordem.
  bool _aplicarStatusDeEntrega(Map<String, Object?> payload) {
    final mensagemId = switch (payload['mensagem_id']) {
      final num n => n.toInt(),
      _ => null,
    };
    final status = payload['status'];
    if (mensagemId == null || status is! String) return false;
    final novo = StatusEntrega.derivar(statusEnvio: status);
    // Vocabulário que o cliente não conhece: a recarga traz o estado real.
    if (novo == StatusEntrega.pendente) return false;
    final atual = state;
    if (atual is! SuccessState<ChatViewModel>) return false;
    final mensagens = atual.data.mensagens;
    final i = mensagens.indexWhere((m) => m.id == mensagemId);
    if (i < 0) return false;

    final mensagem = mensagens[i];
    final antes = mensagem.statusEntrega;
    final avanca = novo == StatusEntrega.falhou
        // Falha só faz sentido antes de o provedor confirmar a entrega.
        ? antes.index <= StatusEntrega.enviada.index
        // Um recibo depois de "falhou" é o provedor corrigindo a si mesmo.
        : antes == StatusEntrega.falhou || novo.index > antes.index;
    if (!avanca) return true;

    final agora = DateTime.now();
    final chegou = novo == StatusEntrega.entregue || novo == StatusEntrega.lida;
    final atualizada = mensagem.copyWith(
      statusEnvio: status,
      entregueEm: chegou ? (mensagem.entregueEm ?? agora) : null,
      lidaEm: novo == StatusEntrega.lida ? (mensagem.lidaEm ?? agora) : null,
    );
    emit(
      SuccessState(
        atual.data.copyWith(mensagens: [...mensagens]..[i] = atualizada),
      ),
    );
    return true;
  }

  /// P1.1-A — junta pedidos de recarga em rajada numa recarga só.
  ///
  /// Cada pedido reinicia a janela de [_janelaDeRecarga]; o teto de
  /// [_tetoDeRecarga], armado no primeiro pedido, evita adiar para sempre
  /// sob fluxo contínuo. [motivo] é o tipo do evento (ou `envio`), nunca
  /// conteúdo.
  void _agendarRecarga(String motivo) {
    if (_encerrado || isClosed) return;
    _motivoDaRecarga = motivo;
    _recargaAgendada?.cancel();
    _recargaAgendada = Timer(_janelaDeRecarga, _dispararRecarga);
    _tetoDaRecarga ??= Timer(_tetoDeRecarga, _dispararRecarga);
  }

  void _dispararRecarga() {
    _recargaAgendada?.cancel();
    _recargaAgendada = null;
    _tetoDaRecarga?.cancel();
    _tetoDaRecarga = null;
    if (_encerrado || isClosed) return;
    final contagem = _recargasPorEnvio;
    if (contagem != null) _recargasPorEnvio = contagem + 1;
    developer.log(
      'recarga da thread',
      name: 'operacional_module.chat',
      level: 500,
      error: 'motivo=$_motivoDaRecarga',
    );
    unawaited(_recarregarThread());
  }

  /// P1.1-A — abre a janela de medição de recargas de um envio. Um envio
  /// novo antes do fim da janela fecha (e loga) a medição anterior.
  void _iniciarMedicaoDoEnvio() {
    if (_medicaoDoEnvio != null) _encerrarMedicaoDoEnvio();
    _recargasPorEnvio = 0;
    _medicaoDoEnvio = Timer(_janelaDeMedicao, _encerrarMedicaoDoEnvio);
  }

  void _encerrarMedicaoDoEnvio() {
    _medicaoDoEnvio?.cancel();
    _medicaoDoEnvio = null;
    final contagem = _recargasPorEnvio;
    _recargasPorEnvio = null;
    if (contagem == null) return;
    developer.log(
      'recargas por envio',
      name: 'operacional_module.chat',
      level: 500,
      error: 'recargasPorEnvio=$contagem',
    );
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
      if (isClosed) return;
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
    // A tela pode ter fechado (ou trocado de conversa) durante a ida ao
    // servidor: emitir agora seria erro, ou a conversa errada na tela.
    if (isClosed || atendimentoId != _atendimentoId) return;
    switch (res) {
      case Success(:final value):
        final atual = state;
        if (atual is! SuccessState<ChatViewModel>) return;
        // A recarga traz só a última página. Quem já tinha rolado para cima
        // perderia o histórico carregado se a lista fosse trocada inteira.
        final novos = {for (final m in value) m.id};
        final naTela = {for (final m in atual.data.mensagens) m.id: m};
        // A cópia local de uma mensagem ainda não sincronizada (id negativo)
        // não é histórico: o gateway a devolve enquanto estiver pendente.
        // Guardá-la aqui deixava a mensagem repetida no topo da conversa depois
        // que o servidor a confirmava com o id definitivo.
        final antigas = atual.data.mensagens.where(
          (m) => m.id > 0 && !novos.contains(m.id),
        );
        final recarregadas = [
          for (final m in value) _comMidiaEstavel(naTela[m.id], m),
        ];
        // P1 — confirmadas por id, pendentes locais no fim: ordenar tudo por
        // id desenhava a pendente (id negativo) no topo da conversa.
        final unidas = ordenarParaExibir([...antigas, ...recarregadas]);
        emit(SuccessState(atual.data.copyWith(mensagens: unidas)));
      case Failure(:final error):
        // A conversa na tela continua valendo; o próximo evento tenta de
        // novo. Só o tipo do erro: a mensagem pode citar dados da conversa.
        developer.log(
          'falha ao recarregar a thread',
          name: 'operacional_module.chat',
          level: 900,
          error: 'erro=${error.runtimeType}',
        );
    }
  }

  /// P1.1-A (C17) — a versão recarregada de [nova], mas com a mídia que já
  /// estava na tela quando ela ainda serve.
  static MensagemThread _comMidiaEstavel(
    MensagemThread? naTela,
    MensagemThread nova,
  ) {
    final midia = _midiaEstavel(naTela?.midia, nova.midia);
    return identical(midia, nova.midia) ? nova : nova.copyWith(midia: midia);
  }

  /// Mantém a URL antiga enquanto válida: URL nova = download novo = imagem
  /// piscando. "Mesmo objeto" = mesmo caminho no storage (a assinatura muda
  /// só na query string).
  static MidiaMensagem? _midiaEstavel(
    MidiaMensagem? antiga,
    MidiaMensagem? nova,
  ) {
    if (antiga == null || nova == null) return nova;
    final obtidaEm = antiga.obtidaEm;
    if (obtidaEm == null) return nova;
    final caminhoAntigo = Uri.tryParse(antiga.urlAssinada)?.path;
    final caminhoNovo = Uri.tryParse(nova.urlAssinada)?.path;
    final mesmoObjeto =
        caminhoAntigo != null &&
        caminhoAntigo.isNotEmpty &&
        caminhoAntigo == caminhoNovo;
    final fresca = DateTime.now().difference(obtidaEm) < _frescorDaMidia;
    return mesmoObjeto && fresca ? antiga : nova;
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
    _recargaAgendada?.cancel();
    _tetoDaRecarga?.cancel();
    // Fecha a medição em aberto: o número sai no log mesmo saindo da conversa.
    _encerrarMedicaoDoEnvio();
    _limpezaDaPresenca?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    camposAtualizados.dispose();
    return super.close();
  }
}
