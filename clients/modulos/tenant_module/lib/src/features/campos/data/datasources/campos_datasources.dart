import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/campo_personalizado.dart';
import '../../domain/parameters/campos_parameters.dart';

CampoPersonalizado _campo(proto.MyCampoPersonalizado c) => CampoPersonalizado(
  id: c.id.toInt(),
  slug: c.slug,
  nome: c.nome,
  descricao: c.descricao,
  escopo: c.escopo,
  fluxoId: c.hasFluxoId() ? c.fluxoId : null,
  tipo: TipoCampo.doValor(c.tipo),
  opcoes: c.opcoes
      .map((o) => OpcaoCampo(id: o.id, rotulo: o.rotulo))
      .toList(growable: false),
  obrigatorio: c.obrigatorio,
  extrairAutomaticamente: c.extrairAutomaticamente,
  extrairHint: c.extrairHint,
  mostrarNoCard: c.mostrarNoCard,
  ordem: c.ordem,
  ativo: c.ativo,
);

List<proto.OpcaoCampo> _opcoes(List<OpcaoCampo> opcoes) => opcoes
    .map((o) => proto.OpcaoCampo(id: o.id, rotulo: o.rotulo))
    .toList(growable: false);

final class ListarCamposDatasource
    implements Datasource<List<CampoPersonalizado>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarCamposDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<CampoPersonalizado>> call(NoParams parameters) async {
    final resp = await _client.listMyCampos(proto.ListMyCamposRequest());
    return resp.campos.map(_campo).toList();
  }
}

final class CriarCampoDatasource
    implements Datasource<CampoPersonalizado, CriarCampoParameters> {
  final proto.AdminServiceClient _client;

  const CriarCampoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<CampoPersonalizado> call(CriarCampoParameters parameters) async {
    final resp = await _client.createMyCampo(
      proto.CreateMyCampoRequest(
        nome: parameters.nome,
        descricao: parameters.descricao,
        escopo: parameters.escopo,
        fluxoId: parameters.fluxoId,
        tipo: parameters.tipo.valor,
        opcoes: _opcoes(parameters.opcoes),
        obrigatorio: parameters.obrigatorio,
        extrairAutomaticamente: parameters.extrairAutomaticamente,
        extrairHint: parameters.extrairHint,
        mostrarNoCard: parameters.mostrarNoCard,
        ordem: parameters.ordem,
      ),
    );
    return _campo(resp.campo);
  }
}

final class AtualizarCampoDatasource
    implements Datasource<Unit, AtualizarCampoParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarCampoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(AtualizarCampoParameters parameters) async {
    await _client.updateMyCampo(
      proto.UpdateMyCampoRequest(
        id: Int64(parameters.id),
        nome: parameters.nome,
        descricao: parameters.descricao,
        tipo: parameters.tipo.valor,
        opcoes: _opcoes(parameters.opcoes),
        obrigatorio: parameters.obrigatorio,
        extrairAutomaticamente: parameters.extrairAutomaticamente,
        extrairHint: parameters.extrairHint,
        mostrarNoCard: parameters.mostrarNoCard,
        ordem: parameters.ordem,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

final class DesativarCampoDatasource
    implements Datasource<Unit, CampoIdParameters> {
  final proto.AdminServiceClient _client;

  const DesativarCampoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(CampoIdParameters parameters) async {
    await _client.desativarMyCampo(
      proto.MyCampoIdRequest(id: Int64(parameters.id)),
    );
    return unit;
  }
}
