import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';

Contato _contato(proto.MyContato c) => Contato(
  id: c.id,
  telefone: c.telefone,
  nomeContato: c.nomeContato,
  nomePerfilWhatsapp: c.nomePerfilWhatsapp,
  email: c.email,
  ativo: c.ativo,
  ultimaInteracao: DateTime.fromMillisecondsSinceEpoch(
    c.ultimaInteracao.toInt(),
  ),
  cadastradoEm: DateTime.fromMillisecondsSinceEpoch(c.cadastradoEm.toInt()),
);

final class ListarContatosDatasource
    implements Datasource<List<Contato>, ListarContatosParameters> {
  final proto.AdminServiceClient _client;

  const ListarContatosDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<Contato>> call(ListarContatosParameters parameters) async {
    // `limite` vai zerado de propósito: o servidor aplica o padrão dele, e
    // fixar um número aqui faria o cliente e o servidor discordarem do teto.
    final resp = await _client.listMyContatos(
      proto.ListMyContatosRequest(busca: parameters.busca),
    );
    return resp.contatos.map(_contato).toList();
  }
}

final class CriarContatoDatasource
    implements Datasource<Contato, CriarContatoParameters> {
  final proto.AdminServiceClient _client;

  const CriarContatoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Contato> call(CriarContatoParameters parameters) async {
    final resp = await _client.createMyContato(
      proto.CreateMyContatoRequest(
        telefone: parameters.telefone,
        nomeContato: parameters.nomeContato,
        email: parameters.email,
      ),
    );
    // O contato volta com o telefone já normalizado — é ele que a tela mostra
    // depois de salvar, e não o que foi digitado.
    return _contato(resp.contato);
  }
}

final class AtualizarContatoDatasource
    implements Datasource<Unit, AtualizarContatoParameters> {
  final proto.AdminServiceClient _client;

  const AtualizarContatoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(AtualizarContatoParameters parameters) async {
    await _client.updateMyContato(
      proto.UpdateMyContatoRequest(
        id: parameters.id,
        nomeContato: parameters.nomeContato,
        email: parameters.email,
        telefone: parameters.telefone,
      ),
    );
    return unit;
  }
}

final class DefinirContatoAtivoDatasource
    implements Datasource<Unit, DefinirContatoAtivoParameters> {
  final proto.AdminServiceClient _client;

  const DefinirContatoAtivoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(DefinirContatoAtivoParameters parameters) async {
    await _client.definirMyContatoAtivo(
      proto.DefinirMyContatoAtivoRequest(
        id: parameters.id,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}
