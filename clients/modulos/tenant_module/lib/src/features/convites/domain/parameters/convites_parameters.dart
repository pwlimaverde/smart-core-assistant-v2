import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das quatro operações de convite.
///
/// Nenhum deles carrega `tenant_id`: o backend sempre resolve o tenant a partir
/// da sessão autenticada. Aceitar um tenant vindo do cliente seria abrir a porta
/// para convidar alguém para outro tenant.

/// Criação de convite pelo admin do tenant.
final class CreateInviteParameters extends Parameters {
  final String email;
  final String name;
  final String role;
  final List<String> modulePermissions;
  final List<int> flowPermissions;

  const CreateInviteParameters({
    required this.email,
    required this.name,
    required this.role,
    this.modulePermissions = const [],
    this.flowPermissions = const [],
  });
}

/// Revogação de um convite pendente.
final class RevokeInviteParameters extends Parameters {
  final String inviteId;

  const RevokeInviteParameters({required this.inviteId});
}

/// Aceite do convite pelo convidado (rota pública).
///
/// Carrega a senha escolhida: como o [LoginParameters] do `login_module`, nunca
/// entra em log, nem via `parameters` do `mapError`.
final class AcceptInviteParameters extends Parameters {
  final String token;
  final String username;
  final String email;
  final String password;

  const AcceptInviteParameters({
    required this.token,
    required this.username,
    required this.email,
    required this.password,
  });
}
