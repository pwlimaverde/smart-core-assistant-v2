import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/treinamento_errors.dart';
import '../../domain/model/treinamento.dart';
import '../../domain/parameters/treinamento_parameters.dart';
import '../../domain/usecases/treinamento_usecases.dart';

/// Estado da tela de treinamento: a lista do tenant.
// ignore_for_file: prefer_initializing_formals
final class TreinamentoController extends BaseController<List<Treinamento>> {
  final ListarTreinamentosUsecase _listar;
  final CriarTreinamentoUsecase _criar;
  final FinalizarTreinamentoUsecase _finalizar;
  final RemoverTreinamentoUsecase _remover;

  TreinamentoController({
    required ListarTreinamentosUsecase listar,
    required CriarTreinamentoUsecase criar,
    required FinalizarTreinamentoUsecase finalizar,
    required RemoverTreinamentoUsecase remover,
  })  : _listar = listar,
        _criar = criar,
        _finalizar = finalizar,
        _remover = remover;

  Future<void> carregar() =>
      execute<TreinamentoError>(() => _listar(noParams));

  /// As mutações devolvem o resultado para a tela decidir o que dizer, e só
  /// recarregam quando deram certo — recarregar depois de uma falha apagaria
  /// da tela o motivo dela.
  Future<ReturnSuccessOrError<Treinamento, TreinamentoError>> criar({
    required String tag,
    required String grupo,
    required String conteudo,
  }) async {
    final res = await _criar(
      CriarTreinamentoParameters(tag: tag, grupo: grupo, conteudo: conteudo),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, TreinamentoError>> finalizar({
    required int id,
    required String conteudo,
  }) async {
    final res = await _finalizar(
      FinalizarTreinamentoParameters(id: id, conteudo: conteudo),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, TreinamentoError>> remover(int id) async {
    final res = await _remover(TreinamentoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}
