import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/ignorados_errors.dart';
import '../../domain/model/numero_ignorado.dart';
import '../../domain/parameters/ignorados_parameters.dart';
import '../../domain/usecases/ignorados_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Os números que o sistema ignora.
final class IgnoradosController extends BaseController<List<NumeroIgnorado>> {
  final ListarIgnoradosUsecase _listar;
  final CriarIgnoradoUsecase _criar;
  final AtualizarIgnoradoUsecase _atualizar;
  final RemoverIgnoradoUsecase _remover;

  IgnoradosController({
    required ListarIgnoradosUsecase listar,
    required CriarIgnoradoUsecase criar,
    required AtualizarIgnoradoUsecase atualizar,
    required RemoverIgnoradoUsecase remover,
  }) : _listar = listar,
       _criar = criar,
       _atualizar = atualizar,
       _remover = remover;

  Future<void> carregar() =>
      execute<IgnoradosError>(() => _listar(noParams));

  /// As mutações devolvem o erro em vez de emiti-lo no estado: recarregar
  /// depois de falhar apagaria da tela o motivo da falha.
  Future<IgnoradosError?> criar({
    required String nome,
    required String telefone,
  }) async {
    final res = await _criar(
      CriarIgnoradoParameters(nome: nome, telefone: telefone),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<IgnoradosError?> atualizar({
    required int id,
    required String nome,
    required String telefone,
    required bool ativo,
  }) async {
    final res = await _atualizar(
      AtualizarIgnoradoParameters(
        id: id,
        nome: nome,
        telefone: telefone,
        ativo: ativo,
      ),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<IgnoradosError?> remover(int id) async {
    final res = await _remover(IgnoradoIdParameters(id: id));
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }
}
