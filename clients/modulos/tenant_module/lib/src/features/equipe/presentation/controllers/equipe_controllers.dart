import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/equipe_errors.dart';
import '../../domain/model/equipe.dart';
import '../../domain/parameters/equipe_parameters.dart';
import '../../domain/usecases/equipe_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Departamentos e atendentes do tenant.
final class EquipeController extends BaseController<Equipe> {
  final CarregarEquipeUsecase _carregar;
  final CriarDepartamentoUsecase _criar;
  final AtualizarDepartamentoUsecase _atualizar;
  final DesativarDepartamentoUsecase _desativar;

  EquipeController({
    required CarregarEquipeUsecase carregar,
    required CriarDepartamentoUsecase criar,
    required AtualizarDepartamentoUsecase atualizar,
    required DesativarDepartamentoUsecase desativar,
  })  : _carregar = carregar,
        _criar = criar,
        _atualizar = atualizar,
        _desativar = desativar;

  Future<void> carregar() => execute<EquipeError>(() => _carregar(noParams));

  Future<ReturnSuccessOrError<Unit, EquipeError>> criarDepartamento({
    required String nome,
    required String descricao,
  }) async {
    final res = await _criar(
      CriarDepartamentoParameters(nome: nome, descricao: descricao),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> atualizarDepartamento({
    required int id,
    required String nome,
    required String descricao,
    required bool ativo,
  }) async {
    final res = await _atualizar(
      AtualizarDepartamentoParameters(
        id: id,
        nome: nome,
        descricao: descricao,
        ativo: ativo,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> desativarDepartamento(
    int id,
  ) async {
    final res = await _desativar(DepartamentoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}
