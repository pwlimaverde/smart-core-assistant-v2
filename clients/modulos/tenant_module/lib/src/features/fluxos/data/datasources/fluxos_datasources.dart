import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/fluxo.dart';
import '../../domain/parameters/fluxos_parameters.dart';

Fluxo _fluxo(proto.MyFluxo f) => Fluxo(
      id: f.id,
      departamentoId: f.departamentoId,
      departamentoNome: f.departamentoNome,
      nome: f.nome,
      descricao: f.descricao,
      ativo: f.ativo,
      etapas: f.etapas,
      atendimentosAbertos: f.atendimentosAbertos,
    );

EtapaFluxo _etapa(proto.MyEtapaFluxo e) => EtapaFluxo(
      id: e.id,
      fluxoId: e.fluxoId,
      nome: e.nome,
      descricao: e.descricao,
      ordem: e.ordem,
      cor: e.cor,
      tipo: TipoEtapa.doCodigo(e.tipoEtapa),
      ativo: e.ativo,
    );

final class ListarFluxosDatasource implements Datasource<List<Fluxo>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarFluxosDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<List<Fluxo>> call(NoParams parameters) async {
    final resp = await _client.listMyFluxos(proto.ListMyFluxosRequest());
    return resp.fluxos.map(_fluxo).toList();
  }
}

final class CriarFluxoDatasource
    implements Datasource<Unit, CriarFluxoParameters> {
  final proto.AdminServiceClient _client;

  const CriarFluxoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(CriarFluxoParameters parameters) async {
    await _client.createMyFluxo(
      proto.CreateMyFluxoRequest(
        departamentoId: parameters.departamentoId,
        nome: parameters.nome,
        descricao: parameters.descricao,
      ),
    );
    return unit;
  }
}

final class AtualizarFluxoDatasource
    implements Datasource<Unit, AtualizarFluxoParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarFluxoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(AtualizarFluxoParameters parameters) async {
    await _client.updateMyFluxo(
      proto.UpdateMyFluxoRequest(
        id: parameters.id,
        nome: parameters.nome,
        descricao: parameters.descricao,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

final class DesativarFluxoDatasource
    implements Datasource<Unit, FluxoIdParameters> {
  final proto.AdminServiceClient _client;

  const DesativarFluxoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(FluxoIdParameters parameters) async {
    await _client.desativarMyFluxo(proto.MyFluxoIdRequest(id: parameters.id));
    return unit;
  }
}

final class ListarEtapasDatasource
    implements Datasource<List<EtapaFluxo>, FluxoIdParameters> {
  final proto.AdminServiceClient _client;

  const ListarEtapasDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<List<EtapaFluxo>> call(FluxoIdParameters parameters) async {
    final resp = await _client.listMyEtapasFluxo(
      proto.MyFluxoIdRequest(id: parameters.id),
    );
    return resp.etapas.map(_etapa).toList();
  }
}

final class CriarEtapaDatasource
    implements Datasource<Unit, CriarEtapaParameters> {
  final proto.AdminServiceClient _client;

  const CriarEtapaDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(CriarEtapaParameters parameters) async {
    await _client.createMyEtapaFluxo(
      proto.CreateMyEtapaFluxoRequest(
        fluxoId: parameters.fluxoId,
        nome: parameters.nome,
        tipoEtapa: parameters.tipo.codigo,
        cor: parameters.cor,
      ),
    );
    return unit;
  }
}

final class AtualizarEtapaDatasource
    implements Datasource<Unit, AtualizarEtapaParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarEtapaDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(AtualizarEtapaParameters parameters) async {
    await _client.updateMyEtapaFluxo(
      proto.UpdateMyEtapaFluxoRequest(
        id: parameters.id,
        nome: parameters.nome,
        descricao: parameters.descricao,
        cor: parameters.cor,
        tipoEtapa: parameters.tipo.codigo,
      ),
    );
    return unit;
  }
}

final class DesativarEtapaDatasource
    implements Datasource<Unit, EtapaIdParameters> {
  final proto.AdminServiceClient _client;

  const DesativarEtapaDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(EtapaIdParameters parameters) async {
    await _client.desativarMyEtapaFluxo(
      proto.MyEtapaFluxoIdRequest(id: parameters.id),
    );
    return unit;
  }
}

final class MoverEtapaDatasource
    implements Datasource<bool, MoverEtapaParameters> {
  final proto.AdminServiceClient _client;

  const MoverEtapaDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<bool> call(MoverEtapaParameters parameters) async {
    final resp = await _client.moverMyEtapaFluxo(
      proto.MoverMyEtapaFluxoRequest(
        id: parameters.id,
        paraCima: parameters.paraCima,
      ),
    );
    // `false` é "já está na ponta", não falha — quem chamou decide se recarrega.
    return resp.sucesso;
  }
}
