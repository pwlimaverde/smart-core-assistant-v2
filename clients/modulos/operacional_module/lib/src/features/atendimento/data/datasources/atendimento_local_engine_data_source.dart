import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart' as proto;
import 'package:domain_models/domain_models.dart';
import 'package:local_engine_ffi/local_engine_ffi.dart';

import '../../domain/datasources/atendimento_data_source.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';

/// Implementação nativa (desktop/`dart:io`) do [AtendimentoDataSource] sobre o
/// motor local Rust via FFI (`local_engine_ffi`) — F8.
///
/// Mesmo port que `AtendimentoRemoteDataSource`: telas/controllers não mudam ao
/// trocar Web↔desktop (DIP). Aqui as leituras vêm do índice SQLite local e as
/// mutações são otimistas + enfileiradas offline; a reconciliação com o servidor
/// (sync da fila) usa [sincronizarFilaOffline], disparada em best-effort ao
/// carregar a fila (`listAtendimentos`) — o transporte é o gRPC autenticado
/// (`AdminServiceClient`), injetado, mantendo o refresh de token do lado Dart.
///
/// A abertura do motor é **preguiçosa**: `RustLib.init()` carrega a lib nativa
/// uma única vez e `LocalEngineApi.open` cria/migra o índice sob `%APPDATA%`. As
/// falhas do Rust (`anyhow`) são mapeadas para [ErrorLocalEngine] na fronteira.
final class LocalEngineFfiDataSource implements AtendimentoDataSource {
  final String? Function() _tenantIdProvider;
  final proto.AdminServiceClient _admin;
  Future<LocalEngineApi>? _engineFuture;
  bool _sincronizando = false;

  LocalEngineFfiDataSource({
    required String? Function() tenantIdProvider,
    required proto.AdminServiceClient adminClient,
  })  : _admin = adminClient,
        // ignore: prefer_initializing_formals
        _tenantIdProvider = tenantIdProvider;

  /// `RustLib.init()` é global (carrega a `.dll`): memoizado entre instâncias.
  static Future<void>? _rustInit;

  Future<LocalEngineApi> _engine() => _engineFuture ??= _abrir();

  Future<LocalEngineApi> _abrir() async {
    await (_rustInit ??= RustLib.init());
    final base = _baseDir();
    await Directory(base).create(recursive: true);
    final sep = Platform.pathSeparator;
    return LocalEngineApi.open(
      dbPath: [base, 'index.sqlite'].join(sep),
      mediaDir: [base, 'media_cache'].join(sep),
      tenantId: _tenantIdProvider() ?? 'default',
    );
  }

  /// Diretório base do motor local (índice + cache) sob dados do usuário.
  static String _baseDir() {
    final appData = Platform.environment['APPDATA'] ??
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

  /// Mapeia falhas do Rust (`anyhow`, propagadas pelo FRB) para o erro de
  /// domínio [ErrorLocalEngine]. A mensagem do motor local não carrega PII
  /// (só descreve storage/sync/io/mídia), então é seguro anexá-la.
  static ErrorLocalEngine _mapErro(Object e) {
    if (e is ErrorLocalEngine) return e;
    return ErrorLocalEngine(message: 'Falha no motor local: $e');
  }
}
