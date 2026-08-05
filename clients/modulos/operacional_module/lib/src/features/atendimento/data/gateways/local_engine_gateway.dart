import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart' as proto;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:local_engine_ffi/local_engine_ffi.dart';

import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/model/quadro.dart';

/// Debounce do gatilho de reconexão (N7.4): `connectivity_plus` reporta o tipo
/// de interface (não garante alcance real à internet) e pode disparar eventos
/// duplicados, especialmente iOS/macOS. Aguarda a rede estabilizar antes de
/// tentar sincronizar.
const _debounceReconexao = Duration(seconds: 3);

/// Timer de fundo (N7.4): cobre o caso de a conectividade não mudar mas o
/// servidor ter voltado (ex.: reinício do backend sem queda de rede local).
const _intervaloSyncPeriodico = Duration(seconds: 60);

/// Adapter nativo (desktop/`dart:io`) do [AtendimentoGateway] sobre o motor local
/// Rust via FFI (`local_engine_ffi`) — F8.
///
/// Mesmo port que `AtendimentoRemoteGateway`: telas/controllers não mudam ao
/// trocar Web↔desktop (DIP). Aqui as leituras vêm do índice SQLite local e as
/// mutações são otimistas + enfileiradas offline; a reconciliação com o servidor
/// (sync da fila) usa [sincronizarFilaOffline], disparada em best-effort ao
/// carregar a fila (`listAtendimentos`) e, desde a N7.4, também ao reconectar a
/// rede (`connectivity_plus`, com debounce) e por um timer periódico de fundo —
/// o transporte é o gRPC autenticado (`AdminServiceClient`), injetado, mantendo
/// o refresh de token do lado Dart.
///
/// A abertura do motor é **preguiçosa**: `RustLib.init()` carrega a lib nativa
/// uma única vez e `LocalEngineApi.open` cria/migra o índice sob `%APPDATA%`.
///
/// As falhas do Rust (`anyhow`, propagadas pelo FRB) são embrulhadas em
/// [LocalEngineFalha] — uma exceção **técnica**, não um erro de domínio. O
/// embrulho preserva a informação que o `mapError` de cada repositório usa para
/// distinguir "o armazenamento local falhou" de "a rede falhou": desfechos com
/// ações diferentes para o usuário (reiniciar o app vs. tentar de novo).
final class LocalEngineGateway implements AtendimentoGateway {
  final String? Function() _tenantIdProvider;
  final proto.AdminServiceClient _admin;
  Future<LocalEngineApi>? _engineFuture;
  bool _sincronizando = false;

  StreamSubscription<List<ConnectivityResult>>? _conectividadeSub;
  Timer? _debounceTimer;
  Timer? _syncPeriodicoTimer;
  bool _gatilhosDeSyncIniciados = false;

  /// `adminClient` e `tenantIdProvider` como private named parameters (Dart
  /// 3.12): nomes públicos no chamador, campos privados aqui.
  LocalEngineGateway({
    required this._tenantIdProvider,
    required proto.AdminServiceClient adminClient,
  }) : _admin = adminClient; // ignore: prefer_initializing_formals

  /// `RustLib.init()` é global (carrega a `.dll`): memoizado entre instâncias.
  static Future<void>? _rustInit;

  Future<LocalEngineApi> _engine() => _engineFuture ??= _abrir();

  Future<LocalEngineApi> _abrir() async {
    await (_rustInit ??= RustLib.init());
    final base = _baseDir();
    await Directory(base).create(recursive: true);
    final sep = Platform.pathSeparator;
    final engine = await LocalEngineApi.open(
      dbPath: [base, 'index.sqlite'].join(sep),
      mediaDir: [base, 'media_cache'].join(sep),
      tenantId: _tenantIdProvider() ?? 'default',
    );
    _iniciarGatilhosDeSincronizacao();
    return engine;
  }

  /// N7.4 — dispara [sincronizarFilaOffline] sozinho: (a) ao reconectar a rede
  /// (`connectivity_plus`, debounced) e (b) por um timer periódico de fundo.
  /// Idempotente (só arma os listeners uma vez); best-effort (nunca lança).
  void _iniciarGatilhosDeSincronizacao() {
    if (_gatilhosDeSyncIniciados) return;
    _gatilhosDeSyncIniciados = true;

    _conectividadeSub = Connectivity().onConnectivityChanged.listen((
      resultados,
    ) {
      // Evento é oportunista (tipo de interface, não garante internet real):
      // se o transporte falhar depois, as ações seguem na fila para retry.
      if (resultados.contains(ConnectivityResult.none)) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(
        _debounceReconexao,
        () => unawaited(_sincronizarBestEffort()),
      );
    });

    _syncPeriodicoTimer = Timer.periodic(
      _intervaloSyncPeriodico,
      (_) => unawaited(_sincronizarBestEffort()),
    );
  }

  /// Encerra os gatilhos de sincronização (assinatura de conectividade + timer
  /// periódico). Não faz parte do [AtendimentoGateway] (a instância é
  /// tipicamente um singleton de vida igual à do app) — disponível para quem
  /// monta/desmonta a instância explicitamente (ex.: testes, hot-restart).
  void dispose() {
    _conectividadeSub?.cancel();
    _conectividadeSub = null;
    _debounceTimer?.cancel();
    _syncPeriodicoTimer?.cancel();
  }

  /// Diretório base do motor local (índice + cache) sob dados do usuário.
  static String _baseDir() {
    final appData =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    final sep = Platform.pathSeparator;
    return '$appData${sep}SmartCoreAssistant${sep}local_engine';
  }

  @override
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    try {
      final engine = await _engine();
      final rows = await engine.listAtendimentos(
        status: status,
        departamentoId: departamentoId,
        limit: limit,
      );
      // Ao abrir a fila, tenta escoar as ações offline pendentes (best-effort):
      // se estiver offline, as ações permanecem enfileiradas para nova tentativa.
      unawaited(_sincronizarBestEffort());
      return rows.map(_paraResumo).toList();
    } catch (e) {
      throw _mapErro(e);
    }
  }

  /// Sincroniza a fila offline com o servidor e devolve quantas ações foram
  /// aplicadas. A resolução last-write-wins e a marcação de sincronizadas ficam
  /// no motor Rust; aqui só se injeta o transporte gRPC (callbacks Dart).
  Future<int> sincronizarFilaOffline() async {
    try {
      final engine = await _engine();
      final report = await engine.sincronizar(
        onMove: (actionId, atendimentoId, etapaDestinoId, motivo) async {
          try {
            await _admin.moveAtendimentoEtapa(
              proto.MoveAtendimentoEtapaRequest(
                atendimentoId: atendimentoId,
                etapaDestinoId: etapaDestinoId,
                motivo: motivo,
                // N7.2: idempotência do sync — reenviar a mesma ação (retry/
                // reconexão) não duplica o movimento no servidor.
                actionId: actionId,
              ),
            );
            return '';
          } catch (e) {
            return '$e';
          }
        },
        onSend: (actionId, atendimentoId, conteudo, tipo) async {
          try {
            // NUNCA logar `conteudo` (PII) — só trafega no corpo da chamada RPC.
            final resp = await _admin.sendOutboundMessage(
              proto.SendOutboundMessageRequest(
                atendimentoId: atendimentoId,
                conteudo: conteudo,
                tipo: tipo,
                // N7.2: idempotência do sync — reenviar a mesma ação devolve o
                // mesmo message_id definitivo, sem duplicar a mensagem.
                actionId: actionId,
              ),
            );
            // Sucesso = id definitivo em decimal: o motor promove a mensagem
            // pendente local (id negativo) a este id, evitando duplicata na
            // re-ingestão. Falha = prefixo "ERR " (contrato do DartSyncTransport).
            return '${resp.messageId}';
          } catch (e) {
            return 'ERR $e';
          }
        },
      );
      return report.aplicadas;
    } catch (e) {
      throw _mapErro(e);
    }
  }

  /// Dispara [sincronizarFilaOffline] sem propagar erro nem permitir passadas
  /// concorrentes — usado nos gatilhos oportunistas (abertura da fila).
  Future<void> _sincronizarBestEffort() async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      await sincronizarFilaOffline();
    } catch (_) {
      // Offline/erro de transporte: as ações continuam na fila para retry.
    } finally {
      _sincronizando = false;
    }
  }

  @override
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final engine = await _engine();
      final rows = await engine.getThread(
        atendimentoId: atendimentoId,
        limit: limit,
        offset: offset,
      );
      return rows.map(_paraMensagem).toList();
    } catch (e) {
      throw _mapErro(e);
    }
  }

  @override
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    try {
      final engine = await _engine();
      await engine.moveAtendimentoEtapa(
        atendimentoId: atendimentoId,
        etapaDestinoId: etapaDestinoId,
        motivo: motivo,
      );
    } catch (e) {
      throw _mapErro(e);
    }
  }

  @override
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    try {
      // NUNCA logar `conteudo` (PII) — só trafega no corpo da chamada FFI.
      final engine = await _engine();
      return await engine.sendOutboundMessage(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
        tipo: tipo,
      );
    } catch (e) {
      throw _mapErro(e);
    }
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() async* {
    final engine = await _engine();
    yield* engine.streamAtendimentos().map(_paraEvento).handleError((
      Object e,
      StackTrace st,
    ) {
      throw _mapErro(e);
    });
  }

  static AtendimentoResumo _paraResumo(AtendimentoResumoFfi a) =>
      AtendimentoResumo(
        id: a.id,
        contatoId: a.contatoId,
        status: a.status,
        departamentoId: a.departamentoId,
        fluxoAtendimentoId: a.fluxoAtendimentoId,
        etapaAtualId: a.etapaAtualId,
        assunto: a.assunto,
        prioridade: a.prioridade,
        atendenteHumanoId: a.atendenteHumanoId,
        dataInicio: DateTime.fromMillisecondsSinceEpoch(a.dataInicio),
        dataUltimaMensagem: a.dataUltimaMensagem != null
            ? DateTime.fromMillisecondsSinceEpoch(a.dataUltimaMensagem!)
            : null,
      );

  static MensagemThread _paraMensagem(MensagemThreadFfi m) => MensagemThread(
    id: m.id,
    atendimentoId: m.atendimentoId,
    tipo: m.tipo,
    conteudo: m.conteudo,
    remetente: m.remetente,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp),
    statusEnvio: m.statusEnvio,
    geradoPorIa: m.geradoPorIa,
    resumoMidia: m.resumoMidia,
  );

  static AtendimentoEvento _paraEvento(AtendimentoEventoFfi e) {
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(e.payloadJson);
      payload = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } catch (_) {
      payload = <String, Object?>{};
    }
    return AtendimentoEvento(
      tipo: e.tipo,
      tenantId: e.tenantId,
      payload: payload,
    );
  }

  /// Embrulha a falha do Rust em [LocalEngineFalha], preservando a causa. A
  /// mensagem do motor descreve storage/sync/io/mídia e não carrega PII, então é
  /// seguro guardá-la — mas ela vai para log/diagnóstico, nunca para a tela: o
  /// repositório traduz para um erro de domínio com texto próprio.
  static LocalEngineFalha _mapErro(Object e) {
    if (e is LocalEngineFalha) return e;
    return LocalEngineFalha('falha no motor local: $e', e);
  }

  @override
  Future<void> setAtendimentoStatus({
    required int atendimentoId,
    required String status,
    String motivo = '',
  }) async {
    await _admin.setAtendimentoStatus(
      proto.SetAtendimentoStatusRequest(
        atendimentoId: atendimentoId,
        status: status,
        motivo: motivo,
      ),
    );
  }

  @override
  Future<List<FluxoDoQuadro>> listFluxos() async {
    final resp = await _admin.listMyFluxos(proto.ListMyFluxosRequest());
    return resp.fluxos
        .where((f) => f.ativo)
        .map(
          (f) => FluxoDoQuadro(
            id: f.id,
            nome: f.nome,
            departamentoNome: f.departamentoNome,
          ),
        )
        .toList();
  }

  @override
  Future<List<ColunaDoQuadro>> listColunas(int fluxoId) async {
    final resp = await _admin.listMyEtapasFluxo(
      proto.MyFluxoIdRequest(id: fluxoId),
    );
    return resp.etapas
        .map(
          (e) => ColunaDoQuadro(
            id: e.id,
            nome: e.nome,
            cor: e.cor,
            ordem: e.ordem,
            tipo: e.tipoEtapa,
          ),
        )
        .toList();
  }
}
