import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/evolution_connection_result.dart';
import '../../domain/parameters/evolution_parameters.dart';

/// Datasources da feature `evolution`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Testa a conexão da instância WhatsApp de um tenant.
final class TestEvolutionConnectionDatasource
    implements
        Datasource<
          EvolutionConnectionResult,
          TestEvolutionConnectionParameters
        > {
  final proto.AdminServiceClient _client;

  const TestEvolutionConnectionDatasource({required this._client});

  @override
  Future<EvolutionConnectionResult> call(
    TestEvolutionConnectionParameters parameters,
  ) async {
    final resp = await _client.testEvolutionConnection(
      proto.TestEvolutionConnectionRequest(tenantId: parameters.tenantId),
    );
    return EvolutionConnectionResult(
      status: resp.status,
      errorMessage: resp.errorMessage,
    );
  }
}
