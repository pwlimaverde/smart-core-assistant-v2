import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/conexao.dart';
import '../../domain/parameters/conexoes_parameters.dart';
import '../../domain/usecases/conexoes_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Conexões de WhatsApp do tenant.
final class ConexoesController extends BaseController<List<Conexao>> {
  final ListarConexoesUsecase _listar;
  final ReconectarConexaoUsecase _reconectar;
  final RemoverConexaoUsecase _remover;

  ConexoesController({
    required ListarConexoesUsecase listar,
    required ReconectarConexaoUsecase reconectar,
    required RemoverConexaoUsecase remover,
  })  : _listar = listar,
        _reconectar = reconectar,
        _remover = remover;

  Future<void> carregar() => execute<ConexoesError>(() => _listar(noParams));

  /// As mutações devolvem o resultado para a tela dizer o que houve, e só
  /// recarregam quando deram certo — recarregar depois de falhar apagaria da
  /// tela o motivo dela.
  Future<ReturnSuccessOrError<Unit, ConexoesError>> reconectar(int id) async {
    final res = await _reconectar(ConexaoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, ConexoesError>> remover(int id) async {
    final res = await _remover(ConexaoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}
