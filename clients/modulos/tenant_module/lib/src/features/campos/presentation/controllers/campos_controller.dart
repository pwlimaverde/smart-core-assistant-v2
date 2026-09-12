import 'package:presentation_module/presentation_module.dart';

// ignore_for_file: prefer_initializing_formals
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/campos_errors.dart';
import '../../domain/model/campo_personalizado.dart';
import '../../domain/parameters/campos_parameters.dart';
import '../../domain/usecases/campos_usecases.dart';

/// O catálogo de campos do cartão (N9 E13).
final class CamposController extends BaseController<List<CampoPersonalizado>> {
  final ListarCamposUsecase _listar;
  final CriarCampoUsecase _criar;
  final AtualizarCampoUsecase _atualizar;
  final DesativarCampoUsecase _desativar;

  CamposController({
    required ListarCamposUsecase listar,
    required CriarCampoUsecase criar,
    required AtualizarCampoUsecase atualizar,
    required DesativarCampoUsecase desativar,
  }) : _listar = listar,
       _criar = criar,
       _atualizar = atualizar,
       _desativar = desativar;

  Future<void> carregar() => execute<CamposError>(() => _listar(noParams));

  /// Devolve o erro, ou `null` em caso de sucesso.
  ///
  /// A janela precisa do erro para mostrá-lo **dentro dela** — fechar a janela
  /// e piscar um aviso atrás faria a pessoa perder o que digitou.
  Future<CamposError?> criar(CriarCampoParameters p) async {
    final res = await _criar(p);
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<CamposError?> atualizar(AtualizarCampoParameters p) async {
    final res = await _atualizar(p);
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<CamposError?> desativar(int id) async {
    final res = await _desativar(CampoIdParameters(id: id));
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }
}
