import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `feature_flags`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Liga ou desliga uma flag globalmente.
final class SetFeatureFlagParameters extends Parameters {
  final String key;
  final bool enabledGlobally;

  const SetFeatureFlagParameters({
    required this.key,
    required this.enabledGlobally,
  });
}

/// Define ou remove o override de uma flag para um tenant.
final class SetFeatureFlagOverrideParameters extends Parameters {
  final String key;
  final String tenantId;
  final bool enabled;
  final bool removeOverride;

  const SetFeatureFlagOverrideParameters({
    required this.key,
    required this.tenantId,
    required this.enabled,
    required this.removeOverride,
  });
}
