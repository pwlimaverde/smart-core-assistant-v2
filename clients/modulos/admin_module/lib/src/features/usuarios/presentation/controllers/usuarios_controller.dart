import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/usuarios_errors.dart';
import '../../domain/model/usuario_global.dart';
import '../../domain/parameters/usuarios_parameters.dart';
import '../../domain/usecases/usuarios_usecases.dart';

// Campos privados com nomes públicos no construtor: é o padrão dos controllers
// do projeto (ver `FichaController`), e mantém a API de injeção legível.
// ignore_for_file: prefer_initializing_formals

/// Gestão global de usuários pelo superusuário (D7).
final class UsuariosController extends BaseController<List<UsuarioGlobal>> {
  final ListarUsuariosUsecase _listar;
  final DefinirUsuarioAtivoUsecase _definirAtivo;

  UsuariosController({
    required ListarUsuariosUsecase listar,
    required DefinirUsuarioAtivoUsecase definirAtivo,
  }) : _listar = listar,
       _definirAtivo = definirAtivo;

  String _busca = '';

  /// O termo corrente, para a recarga depois de um bloqueio manter o filtro.
  String get busca => _busca;

  Future<void> carregar({String? busca}) {
    if (busca != null) _busca = busca;
    return execute(() => _listar(ListarUsuariosParameters(busca: _busca)));
  }

  /// Bloqueia/desbloqueia e recarrega.
  ///
  /// Recarrega em vez de alterar o item em memória: o servidor é quem decide, e
  /// ele pode recusar (bloquear o próprio acesso, por exemplo). Refletir o
  /// clique antes da resposta deixaria a lista mentindo.
  Future<UsuariosError?> definirAtivo({
    required int userId,
    required bool ativo,
  }) async {
    final res = await _definirAtivo(
      DefinirUsuarioAtivoParameters(userId: userId, ativo: ativo),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }
}
