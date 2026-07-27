import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `evolution`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Testa a conexão da instância WhatsApp de um tenant.
final class TestEvolutionConnectionParameters extends Parameters {
  final String tenantId;

  const TestEvolutionConnectionParameters({required this.tenantId});
}
