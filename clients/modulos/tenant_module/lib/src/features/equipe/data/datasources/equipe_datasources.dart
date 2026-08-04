import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/equipe.dart';
import '../../domain/parameters/equipe_parameters.dart';

Departamento _dep(proto.MyDepartamento d) => Departamento(
      id: d.id,
      nome: d.nome,
      slug: d.slug,
      descricao: d.descricao,
      ativo: d.ativo,
      criadoEm: DateTime.fromMillisecondsSinceEpoch(d.criadoEm.toInt()),
    );

Atendente _at(proto.MyAtendente a) => Atendente(
      id: a.id,
      nome: a.nome,
      email: a.email,
      cargo: a.cargo,
      departamentoId: a.departamentoId,
      fluxoId: a.fluxoId,
      ativo: a.ativo,
      disponivel: a.disponivel,
      maxSimultaneos: a.maxAtendimentosSimultaneos,
    );

/// Busca as duas listas numa passada.
///
/// Duas chamadas, um estado: a tela mostra departamentos e atendentes juntos,
/// e carregar em separado deixaria uma metade na tela enquanto a outra falha.
final class CarregarEquipeDatasource implements Datasource<Equipe, NoParams> {
  final proto.AdminServiceClient _client;

  const CarregarEquipeDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Equipe> call(NoParams parameters) async {
    final deps = await _client.listMyDepartamentos(
      proto.ListMyDepartamentosRequest(),
    );
    final ats = await _client.listMyAtendentes(proto.ListMyAtendentesRequest());
    return Equipe(
      departamentos: deps.departamentos.map(_dep).toList(),
      atendentes: ats.atendentes.map(_at).toList(),
    );
  }
}

final class CriarDepartamentoDatasource
    implements Datasource<Unit, CriarDepartamentoParameters> {
  final proto.AdminServiceClient _client;

  const CriarDepartamentoDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(CriarDepartamentoParameters parameters) async {
    await _client.createMyDepartamento(
      proto.CreateMyDepartamentoRequest(
        nome: parameters.nome,
        descricao: parameters.descricao,
      ),
    );
    return unit;
  }
}

final class AtualizarDepartamentoDatasource
    implements Datasource<Unit, AtualizarDepartamentoParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarDepartamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(AtualizarDepartamentoParameters parameters) async {
    await _client.updateMyDepartamento(
      proto.UpdateMyDepartamentoRequest(
        id: parameters.id,
        nome: parameters.nome,
        descricao: parameters.descricao,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

final class DesativarDepartamentoDatasource
    implements Datasource<Unit, DepartamentoIdParameters> {
  final proto.AdminServiceClient _client;

  const DesativarDepartamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(DepartamentoIdParameters parameters) async {
    await _client.desativarMyDepartamento(
      proto.MyDepartamentoIdRequest(id: parameters.id),
    );
    return unit;
  }
}

final class CriarAtendenteDatasource
    implements Datasource<Unit, CriarAtendenteParameters> {
  final proto.AdminServiceClient _client;

  const CriarAtendenteDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Unit> call(CriarAtendenteParameters parameters) async {
    await _client.createMyAtendente(
      proto.CreateMyAtendenteRequest(
        nome: parameters.nome,
        email: parameters.email,
        cargo: parameters.cargo,
        fluxoId: parameters.fluxoId,
        departamentoId: parameters.departamentoId,
      ),
    );
    return unit;
  }
}

final class AtualizarAtendenteDatasource
    implements Datasource<Unit, AtualizarAtendenteParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarAtendenteDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(AtualizarAtendenteParameters parameters) async {
    await _client.updateMyAtendente(
      proto.UpdateMyAtendenteRequest(
        id: parameters.id,
        nome: parameters.nome,
        cargo: parameters.cargo,
        departamentoId: parameters.departamentoId,
        fluxoId: parameters.fluxoId,
        ativo: parameters.ativo,
        disponivel: parameters.disponivel,
        maxAtendimentosSimultaneos: parameters.maxSimultaneos,
      ),
    );
    return unit;
  }
}

final class DesativarAtendenteDatasource
    implements Datasource<Unit, AtendenteIdParameters> {
  final proto.AdminServiceClient _client;

  const DesativarAtendenteDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(AtendenteIdParameters parameters) async {
    await _client.desativarMyAtendente(
      proto.MyAtendenteIdRequest(id: parameters.id),
    );
    return unit;
  }
}
