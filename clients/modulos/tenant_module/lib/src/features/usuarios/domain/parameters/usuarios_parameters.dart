import 'package:return_success_or_error/return_success_or_error.dart';

/// Atualização de um usuário do tenant.
///
/// Campos `null` **preservam** o valor atual no servidor: o contrato usa flags
/// `set_*` para distinguir "não mexer" de "limpar". Enviar sempre todos os campos
/// faria a UI apagar permissões que ela nem exibiu.
final class UpdateTenantUserParameters extends Parameters {
  final int userId;
  final String? role;
  final List<String>? modulePermissions;
  final List<int>? flowPermissions;

  const UpdateTenantUserParameters({
    required this.userId,
    this.role,
    this.modulePermissions,
    this.flowPermissions,
  });
}
