import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/treinamento.dart';
import '../../domain/parameters/treinamento_parameters.dart';

/// Datasources do treinamento: I/O gRPC e conversão protobuf → domínio.
/// Burros de propósito — a exceção sobe crua para o `mapError` do repositório.

Treinamento _paraDominio(proto.MyTreinamento t) => Treinamento(
      id: t.id,
      tag: t.tag,
      grupo: t.grupo,
      conteudo: t.conteudo,
      finalizado: t.finalizado,
      vetorizado: t.vetorizado,
      criadoEm: DateTime.fromMillisecondsSinceEpoch(t.criadoEm.toInt()),
      atualizadoEm: DateTime.fromMillisecondsSinceEpoch(t.atualizadoEm.toInt()),
    );

final class ListarTreinamentosDatasource
    implements Datasource<List<Treinamento>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarTreinamentosDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<List<Treinamento>> call(NoParams parameters) async {
    final resp = await _client.listMyTreinamentos(
      proto.ListMyTreinamentosRequest(),
    );
    return resp.treinamentos.map(_paraDominio).toList();
  }
}

final class CriarTreinamentoDatasource
    implements Datasource<Treinamento, CriarTreinamentoParameters> {
  final proto.AdminServiceClient _client;

  const CriarTreinamentoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Treinamento> call(CriarTreinamentoParameters parameters) async {
    final resp = await _client.createMyTreinamento(
      proto.CreateMyTreinamentoRequest(
        tag: parameters.tag,
        grupo: parameters.grupo,
        conteudo: parameters.conteudo,
      ),
    );
    return _paraDominio(resp.treinamento);
  }
}

final class ObterTreinamentoDatasource
    implements Datasource<Treinamento, TreinamentoIdParameters> {
  final proto.AdminServiceClient _client;

  const ObterTreinamentoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Treinamento> call(TreinamentoIdParameters parameters) async {
    final resp = await _client.getMyTreinamento(
      proto.GetMyTreinamentoRequest(id: parameters.id),
    );
    return _paraDominio(resp.treinamento);
  }
}

final class FinalizarTreinamentoDatasource
    implements Datasource<Unit, FinalizarTreinamentoParameters> {
  final proto.AdminServiceClient _client;

  const FinalizarTreinamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(FinalizarTreinamentoParameters parameters) async {
    await _client.finalizarMyTreinamento(
      proto.FinalizarMyTreinamentoRequest(
        id: parameters.id,
        conteudo: parameters.conteudo,
      ),
    );
    return unit;
  }
}

final class RemoverTreinamentoDatasource
    implements Datasource<Unit, TreinamentoIdParameters> {
  final proto.AdminServiceClient _client;

  const RemoverTreinamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(TreinamentoIdParameters parameters) async {
    await _client.removerMyTreinamento(
      proto.RemoverMyTreinamentoRequest(id: parameters.id),
    );
    return unit;
  }
}
