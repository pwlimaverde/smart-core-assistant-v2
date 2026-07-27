import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `tenants`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Carrega um tenant pelo id.
final class GetTenantParameters extends Parameters {
  final String id;

  const GetTenantParameters({required this.id});
}

/// Cria um tenant.
final class CreateTenantParameters extends Parameters {
  final String name;
  final String slug;
  final int ownerId;
  final String email;
  final String phone;

  const CreateTenantParameters({
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.email,
    required this.phone,
  });
}

/// Atualiza os dados de um tenant.
final class UpdateTenantParameters extends Parameters {
  final String id;
  final String name;
  final String slug;
  final int ownerId;
  final String email;
  final String phone;

  const UpdateTenantParameters({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.email,
    required this.phone,
  });
}

/// Ativa ou desativa um tenant.
final class SetTenantActiveParameters extends Parameters {
  final String id;
  final bool active;

  const SetTenantActiveParameters({required this.id, required this.active});
}

/// Gera um novo código de acesso (API key) do tenant.
final class GenerateAccessCodeParameters extends Parameters {
  final String id;

  const GenerateAccessCodeParameters({required this.id});
}
