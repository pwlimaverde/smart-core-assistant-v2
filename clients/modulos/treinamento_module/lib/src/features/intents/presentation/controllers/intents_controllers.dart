import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/intents_errors.dart';
import '../../domain/model/intent.dart';
import '../../domain/parameters/intents_parameters.dart';
import '../../domain/usecases/intents_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Curadoria de intenções do tenant.
final class IntentsController extends BaseController<List<IntentIa>> {
  final ListarIntentsUsecase _listar;
  final CriarIntentUsecase _criar;
  final AtualizarIntentUsecase _atualizar;
  final RemoverIntentUsecase _remover;

  IntentsController({
    required ListarIntentsUsecase listar,
    required CriarIntentUsecase criar,
    required AtualizarIntentUsecase atualizar,
    required RemoverIntentUsecase remover,
  })  : _listar = listar,
        _criar = criar,
        _atualizar = atualizar,
        _remover = remover;

  Future<void> carregar() => execute<IntentsError>(() => _listar(noParams));

  Future<ReturnSuccessOrError<Unit, IntentsError>> criar(DadosIntent d) async {
    final res = await _criar(CriarIntentParameters(dados: d));
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, IntentsError>> atualizar({
    required int id,
    required DadosIntent dados,
  }) async {
    final res = await _atualizar(
      AtualizarIntentParameters(id: id, dados: dados),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, IntentsError>> remover(int id) async {
    final res = await _remover(IntentIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}
