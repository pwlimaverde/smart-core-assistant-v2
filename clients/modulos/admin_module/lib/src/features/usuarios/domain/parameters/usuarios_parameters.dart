import 'package:return_success_or_error/return_success_or_error.dart';

/// Filtro da listagem global de usuários (D7).
final class ListarUsuariosParameters extends Parameters {
  /// Casa em username, e-mail e nome. Vazio lista todo mundo.
  final String busca;
  final int limite;
  final int offset;

  const ListarUsuariosParameters({
    this.busca = '',
    this.limite = 50,
    this.offset = 0,
  });
}

/// Bloqueio/desbloqueio de acesso.
final class DefinirUsuarioAtivoParameters extends Parameters {
  final int userId;
  final bool ativo;

  const DefinirUsuarioAtivoParameters({
    required this.userId,
    required this.ativo,
  });
}
