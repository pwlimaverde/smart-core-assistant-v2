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
  respostaBot: c.respostaBot,
  departamentoId: c.departamentoId,
  departamentoNome: c.departamentoNome,
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
    return EstadoPareamento(estado: resp.connectionState, qrCode: resp.qrCode);
  }
}

/// D3 — liga/desliga a IA para a conexão inteira.
final class DefinirRespostaBotDatasource
    implements Datasource<bool, RespostaBotParameters> {
  final proto.AdminServiceClient _client;

  const DefinirRespostaBotDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<bool> call(RespostaBotParameters parameters) async {
    final resp = await _client.definirRespostaBotInstancia(
      proto.DefinirRespostaBotInstanciaRequest(
        id: parameters.id,
        habilitado: parameters.habilitado,
      ),
    );
    return resp.habilitado;
  }
}

/// P7 — encerra a sessão sem apagar a conexão.
final class DesconectarConexaoDatasource
    implements Datasource<Unit, ConexaoIdParameters> {
  final proto.AdminServiceClient _client;

  const DesconectarConexaoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(ConexaoIdParameters parameters) async {
    await _client.desconectarMyWhatsappInstance(
      proto.MyWhatsappInstanceIdRequest(id: parameters.id),
    );
    return unit;
  }
}

/// P7 — para qual departamento este número roteia.
final class DefinirDepartamentoDaConexaoDatasource
    implements Datasource<Unit, DepartamentoDaConexaoParameters> {
  final proto.AdminServiceClient _client;

  const DefinirDepartamentoDaConexaoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(DepartamentoDaConexaoParameters parameters) async {
    await _client.definirDepartamentoDaConexao(
      proto.DefinirDepartamentoDaConexaoRequest(
        id: parameters.id,
        departamentoId: parameters.departamentoId,
      ),
    );
    return unit;
  }
}

/// P7 — o detalhe da conexão.
final class DetalheDaConexaoDatasource
    implements Datasource<DetalheConexao, ConexaoIdParameters> {
  final proto.AdminServiceClient _client;

  const DetalheDaConexaoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<DetalheConexao> call(ConexaoIdParameters parameters) async {
    final resp = await _client.detalheDaConexao(
      proto.DetalheDaConexaoRequest(id: parameters.id),
    );
    final checagem = resp.ultimaChecagem.toInt();
    return DetalheConexao(
      conexao: _paraDominio(resp.conexao),
      instanciaNoProvedor: resp.instanciaNoProvedor,
      atendimentosAbertos: resp.atendimentosAbertos,
      mensagens24h: resp.mensagens24h,
      // 0 é "nunca conferida", não 1970: mostrar a data da época seria pior do
      // que não mostrar nada.
      ultimaChecagem: checagem == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checagem),
    );
  }
}
