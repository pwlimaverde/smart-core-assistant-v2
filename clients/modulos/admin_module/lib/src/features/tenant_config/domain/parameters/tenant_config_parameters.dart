import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';

/// Parâmetros das operações da feature `tenant_config`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Lê a configuração de IA/persona de um tenant.
final class GetTenantConfigParameters extends Parameters {
  final String tenantId;

  const GetTenantConfigParameters({required this.tenantId});
}

/// Grava a configuração de IA/persona de um tenant.
final class UpdateTenantConfigParameters extends Parameters {
  final String tenantId;
  final TenantConfig config;

  const UpdateTenantConfigParameters({
    required this.tenantId,
    required this.config,
  });
}
