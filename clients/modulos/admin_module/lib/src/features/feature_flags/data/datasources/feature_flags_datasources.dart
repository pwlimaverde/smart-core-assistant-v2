import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/feature_flag.dart';
import '../../domain/parameters/feature_flags_parameters.dart';

/// Datasources da feature `feature_flags`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lista as flags e seus overrides por tenant.
final class ListFeatureFlagsDatasource
    implements Datasource<List<FeatureFlag>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListFeatureFlagsDatasource({required this._client});

  @override
  Future<List<FeatureFlag>> call(NoParams parameters) async {
    final resp = await _client.listFeatureFlags(
      proto.ListFeatureFlagsRequest(),
    );
    return resp.flags
        .map(
          (f) => FeatureFlag(
            key: f.key,
            description: f.description,
            enabledGlobally: f.enabledGlobally,
            overrides: f.overrides
                .map(
                  (o) => FeatureFlagOverride(
                    tenantId: o.tenantId,
                    enabled: o.enabled,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }
}

/// Liga ou desliga uma flag globalmente.
final class SetFeatureFlagDatasource
    implements Datasource<Unit, SetFeatureFlagParameters> {
  final proto.AdminServiceClient _client;

  const SetFeatureFlagDatasource({required this._client});

  @override
  Future<Unit> call(SetFeatureFlagParameters parameters) async {
    await _client.setFeatureFlag(
      proto.SetFeatureFlagRequest(
        key: parameters.key,
        enabledGlobally: parameters.enabledGlobally,
      ),
    );
    return unit;
  }
}

/// Define ou remove o override de uma flag para um tenant.
final class SetFeatureFlagOverrideDatasource
    implements Datasource<Unit, SetFeatureFlagOverrideParameters> {
  final proto.AdminServiceClient _client;

  const SetFeatureFlagOverrideDatasource({required this._client});

  @override
  Future<Unit> call(SetFeatureFlagOverrideParameters parameters) async {
    await _client.setFeatureFlagOverride(
      proto.SetFeatureFlagOverrideRequest(
        key: parameters.key,
        tenantId: parameters.tenantId,
        enabled: parameters.enabled,
        removeOverride: parameters.removeOverride,
      ),
    );
    return unit;
  }
}
