import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';

/// Gravação da configuração do próprio tenant.
///
/// Carrega o [config] inteiro porque o RPC é um upsert completo — o servidor
/// substitui todos os campos. A tela sempre parte da configuração lida, então não
/// há risco de apagar o que ela não exibiu.
///
/// `config.apiKeys` traz segredos (chaves de provedores de IA): este objeto não
/// entra em log em nenhuma camada.
final class UpdateMyTenantConfigParameters extends Parameters {
  final TenantConfig config;

  const UpdateMyTenantConfigParameters({required this.config});
}
