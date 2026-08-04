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
