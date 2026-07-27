import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/core_setting.dart';
import '../../domain/parameters/core_settings_parameters.dart';

/// Datasources da feature `core_settings`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lista as configurações globais do sistema.
final class ListCoreSettingsDatasource
    implements Datasource<List<CoreSetting>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListCoreSettingsDatasource({required this._client});

  @override
  Future<List<CoreSetting>> call(NoParams parameters) async {
    final resp = await _client.listCoreSettings(
      proto.ListCoreSettingsRequest(),
    );
    return resp.settings
        .map(
          (s) => CoreSetting(
            key: s.key,
            value: s.value,
            encrypted: s.encrypted,
            description: s.description,
          ),
        )
        .toList();
  }
}

/// Cria ou atualiza uma configuração global.
final class UpsertCoreSettingDatasource
    implements Datasource<Unit, UpsertCoreSettingParameters> {
  final proto.AdminServiceClient _client;

  const UpsertCoreSettingDatasource({required this._client});

  @override
  Future<Unit> call(UpsertCoreSettingParameters parameters) async {
    await _client.upsertCoreSetting(
      proto.UpsertCoreSettingRequest(
        key: parameters.key,
        value: parameters.value,
        encrypted: parameters.encrypted,
        description: parameters.description,
      ),
    );
    return unit;
  }
}

/// Remove uma configuração global.
final class DeleteCoreSettingDatasource
    implements Datasource<Unit, DeleteCoreSettingParameters> {
  final proto.AdminServiceClient _client;

  const DeleteCoreSettingDatasource({required this._client});

  @override
  Future<Unit> call(DeleteCoreSettingParameters parameters) async {
    await _client.deleteCoreSetting(
      proto.DeleteCoreSettingRequest(key: parameters.key),
    );
    return unit;
  }
}
