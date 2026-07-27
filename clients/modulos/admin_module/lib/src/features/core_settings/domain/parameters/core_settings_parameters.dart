import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `core_settings`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Cria ou atualiza uma configuração global.
final class UpsertCoreSettingParameters extends Parameters {
  final String key;
  final String value;
  final bool encrypted;
  final String description;

  const UpsertCoreSettingParameters({
    required this.key,
    required this.value,
    required this.encrypted,
    required this.description,
  });
}

/// Remove uma configuração global.
final class DeleteCoreSettingParameters extends Parameters {
  final String key;

  const DeleteCoreSettingParameters({required this.key});
}
