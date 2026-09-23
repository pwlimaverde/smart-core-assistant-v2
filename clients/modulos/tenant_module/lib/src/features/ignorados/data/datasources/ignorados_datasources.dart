import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/numero_ignorado.dart';
import '../../domain/parameters/ignorados_parameters.dart';

NumeroIgnorado _paraDominio(proto.MyNumeroIgnorado n) => NumeroIgnorado(
  id: n.id,
  nome: n.nome,
  telefone: n.telefone,
  ativo: n.ativo,
  criadoEm: DateTime.fromMillisecondsSinceEpoch(n.criadoEm.toInt()),
);

final class ListarIgnoradosDatasource
    implements Datasource<List<NumeroIgnorado>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarIgnoradosDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<NumeroIgnorado>> call(NoParams parameters) async {
    final resp = await _client.listMyNumerosIgnorados(
      proto.ListMyNumerosIgnoradosRequest(),
    );
    return resp.itens.map(_paraDominio).toList();
  }
}

final class CriarIgnoradoDatasource
    implements Datasource<NumeroIgnorado, CriarIgnoradoParameters> {
  final proto.AdminServiceClient _client;

  const CriarIgnoradoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<NumeroIgnorado> call(CriarIgnoradoParameters parameters) async {
    final resp = await _client.criarNumeroIgnorado(
      proto.CriarNumeroIgnoradoRequest(
        nome: parameters.nome,
        telefone: parameters.telefone,
      ),
    );
    return _paraDominio(resp.item);
  }
}

final class AtualizarIgnoradoDatasource
    implements Datasource<Unit, AtualizarIgnoradoParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarIgnoradoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(AtualizarIgnoradoParameters parameters) async {
    await _client.atualizarNumeroIgnorado(
      proto.AtualizarNumeroIgnoradoRequest(
        id: parameters.id,
        nome: parameters.nome,
        telefone: parameters.telefone,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

final class RemoverIgnoradoDatasource
    implements Datasource<Unit, IgnoradoIdParameters> {
  final proto.AdminServiceClient _client;

  const RemoverIgnoradoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(IgnoradoIdParameters parameters) async {
    await _client.removerNumeroIgnorado(
      proto.NumeroIgnoradoIdRequest(id: parameters.id),
    );
    return unit;
  }
}
