import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/datasources/atendimento_data_source.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/services/atendimento_service.dart';

/// Implementação de [AtendimentoService]: encapsula o [AtendimentoDataSource]
/// injetado em `try/catch`, convertendo exceções em [ReturnSuccessOrError].
/// Nenhuma lógica de negócio aqui além do mapeamento de erro — mantém o
/// datasource (I/O) e o domínio (regras) separados (SRP).
final class AtendimentoServiceImpl implements AtendimentoService {
  final AtendimentoDataSource _datasource;

  const AtendimentoServiceImpl({required AtendimentoDataSource datasource})
    : _datasource = datasource; // ignore: prefer_initializing_formals

  @override
  Future<ReturnSuccessOrError<List<AtendimentoResumo>>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    try {
      final result = await _datasource.listAtendimentos(
        status: status,
        departamentoId: departamentoId,
        limit: limit,
      );
      return SuccessReturn(success: result);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<MensagemThread>>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final result = await _datasource.getThread(
        atendimentoId: atendimentoId,
        limit: limit,
        offset: offset,
      );
      return SuccessReturn(success: result);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    try {
      await _datasource.moveAtendimentoEtapa(
        atendimentoId: atendimentoId,
        etapaDestinoId: etapaDestinoId,
        motivo: motivo,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<int>> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    try {
      final messageId = await _datasource.sendOutboundMessage(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
        tipo: tipo,
      );
      return SuccessReturn(success: messageId);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() =>
      _datasource.streamAtendimentos();
}
