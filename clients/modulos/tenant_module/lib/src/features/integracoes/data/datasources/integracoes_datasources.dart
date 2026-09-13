import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/atividade.dart';
import '../../domain/model/mcp_grant.dart';
import '../../domain/parameters/integracoes_parameters.dart';

/// Datasources da feature de aplicativos conectados: I/O gRPC e conversão
/// protobuf → domínio. Burros por contrato (sem `try/catch`).

/// Lista os aplicativos que **este usuário** conectou.
final class ListMcpGrantsDatasource
    implements Datasource<List<McpGrant>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListMcpGrantsDatasource({required this._client});

  @override
  Future<List<McpGrant>> call(NoParams parameters) async {
    final resp = await _client.listMcpGrants(proto.ListMcpGrantsRequest());
    return resp.grants
        .map(
          (g) => McpGrant(
            id: g.id,
            clientId: g.clientId,
            clientName: g.clientName,
            redirectUri: g.redirectUri,
            scopes: g.scopes,
            // O backend usa 0 para "nunca usado"; no domínio isso é `null`, para
            // que a tela não mostre "usado em 01/01/1970".
            lastUsedAt: g.lastUsedAt == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(g.lastUsedAt.toInt()),
            createdAt: DateTime.fromMillisecondsSinceEpoch(g.createdAt.toInt()),
          ),
        )
        .toList(growable: false);
  }
}

/// Desconecta um aplicativo e devolve a janela de revogação em minutos.
final class RevokeMcpGrantDatasource
    implements Datasource<int, RevokeMcpGrantParameters> {
  final proto.AdminServiceClient _client;

  const RevokeMcpGrantDatasource({required this._client});

  @override
  Future<int> call(RevokeMcpGrantParameters parameters) async {
    final resp = await _client.revokeMcpGrant(
      proto.RevokeMcpGrantRequest(grantId: parameters.grantId),
    );
    return resp.janelaRevogacaoMin;
  }
}

/// A atividade do tenant (B3), já no formato do domínio.
final class ListarAtividadeDatasource
    implements Datasource<List<Atividade>, ListarAtividadeParameters> {
  final proto.AdminServiceClient _client;

  const ListarAtividadeDatasource({required this._client});

  @override
  Future<List<Atividade>> call(ListarAtividadeParameters parameters) async {
    final resp = await _client.listMyAuditLog(
      proto.ListMyAuditLogRequest(
        origem: parameters.soAgentes ? 'mcp' : '',
        grantId: parameters.grantId ?? '',
        desde: Int64(parameters.desde?.millisecondsSinceEpoch ?? 0),
        limit: 100,
      ),
    );
    return resp.entries
        .map(
          (e) => Atividade(
            quando: DateTime.fromMillisecondsSinceEpoch(e.timestamp.toInt()),
            evento: e.eventType,
            porAgente: e.origem == 'mcp',
            aplicativo: e.clientName,
            operacao: e.tool,
            quem: e.userNome,
            grantId: e.grantId,
          ),
        )
        .toList(growable: false);
  }
}
