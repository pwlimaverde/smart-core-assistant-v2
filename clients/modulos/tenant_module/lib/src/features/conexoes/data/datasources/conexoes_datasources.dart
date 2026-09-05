import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/conexao.dart';
import '../../domain/parameters/conexoes_parameters.dart';

Conexao _paraDominio(proto.MyWhatsappInstance c) => Conexao(
      id: c.id,
      nome: c.name,
      telefone: c.phoneNumber,
      estado: c.connectionState,
      ativa: c.active,
      criadaEm: DateTime.fromMillisecondsSinceEpoch(c.createdAt.toInt()),
    );

final class ListarConexoesDatasource
    implements Datasource<List<Conexao>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarConexoesDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<List<Conexao>> call(NoParams parameters) async {
    final resp = await _client.listMyWhatsappInstances(
      proto.ListMyWhatsappInstancesRequest(),
    );
    return resp.instancias.map(_paraDominio).toList();
  }
}

final class ReconectarConexaoDatasource
    implements Datasource<Unit, ConexaoIdParameters> {
  final proto.AdminServiceClient _client;

  const ReconectarConexaoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(ConexaoIdParameters parameters) async {
    await _client.reconnectMyWhatsappInstance(
      proto.MyWhatsappInstanceIdRequest(id: parameters.id),
    );
    return unit;
  }
}

final class RemoverConexaoDatasource
    implements Datasource<Unit, ConexaoIdParameters> {
  final proto.AdminServiceClient _client;

  const RemoverConexaoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(ConexaoIdParameters parameters) async {
    await _client.deleteMyWhatsappInstance(
      proto.MyWhatsappInstanceIdRequest(id: parameters.id),
    );
    return unit;
  }
}

final class CriarConexaoDatasource
    implements Datasource<ConexaoCriada, CriarConexaoParameters> {
  final proto.AdminServiceClient _client;

  const CriarConexaoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<ConexaoCriada> call(CriarConexaoParameters parameters) async {
    final resp = await _client.createMyWhatsappInstance(
      proto.CreateMyWhatsappInstanceRequest(instanceName: parameters.nome),
    );
    return ConexaoCriada(id: resp.id, nome: resp.instanceName);
  }
}

final class EstadoPareamentoDatasource
    implements Datasource<EstadoPareamento, ConexaoIdParameters> {
  final proto.AdminServiceClient _client;

  const EstadoPareamentoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<EstadoPareamento> call(ConexaoIdParameters parameters) async {
    final resp = await _client.getMyWhatsappInstanceStatus(
      proto.GetMyWhatsappInstanceStatusRequest(id: parameters.id),
    );
    return EstadoPareamento(
      estado: resp.connectionState,
      qrCode: resp.qrCode,
    );
  }
}
