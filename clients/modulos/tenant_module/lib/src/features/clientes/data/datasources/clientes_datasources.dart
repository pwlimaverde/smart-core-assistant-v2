import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/cliente.dart';
import '../../domain/parameters/clientes_parameters.dart';

/// Datasources dos clientes (B10): I/O gRPC e conversão, sem `try/catch`.

proto.DadosMyCliente _dadosParaProto(DadosCliente d) => proto.DadosMyCliente(
  nomeFantasia: d.nomeFantasia.trim(),
  razaoSocial: d.razaoSocial.trim(),
  tipo: d.tipo.trim(),
  cnpj: d.cnpj.trim(),
  cpf: d.cpf.trim(),
  telefone: d.telefone.trim(),
  site: d.site.trim(),
  ramoAtividade: d.ramoAtividade.trim(),
  observacoes: d.observacoes.trim(),
  cep: d.cep.trim(),
  logradouro: d.logradouro.trim(),
  numero: d.numero.trim(),
  complemento: d.complemento.trim(),
  bairro: d.bairro.trim(),
  cidade: d.cidade.trim(),
  uf: d.uf.trim(),
);

DadosCliente _dadosDoProto(proto.DadosMyCliente d) => DadosCliente(
  nomeFantasia: d.nomeFantasia,
  razaoSocial: d.razaoSocial,
  tipo: d.tipo,
  cnpj: d.cnpj,
  cpf: d.cpf,
  telefone: d.telefone,
  site: d.site,
  ramoAtividade: d.ramoAtividade,
  observacoes: d.observacoes,
  cep: d.cep,
  logradouro: d.logradouro,
  numero: d.numero,
  complemento: d.complemento,
  bairro: d.bairro,
  cidade: d.cidade,
  uf: d.uf,
);

Cliente _cliente(proto.MyCliente c) => Cliente(
  id: c.id,
  dados: _dadosDoProto(c.dados),
  ativo: c.ativo,
  contatos: c.contatos,
);

final class ListarClientesDatasource
    implements Datasource<List<Cliente>, ListarClientesParameters> {
  final proto.AdminServiceClient _client;

  const ListarClientesDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<Cliente>> call(ListarClientesParameters parameters) async {
    final resp = await _client.listMyClientes(
      proto.ListMyClientesRequest(
        busca: parameters.busca,
        incluirInativos: parameters.incluirInativos,
      ),
    );
    return resp.clientes.map(_cliente).toList(growable: false);
  }
}

/// Cadastra (sem `id`) ou edita. Devolve o id do cliente.
final class SalvarClienteDatasource
    implements Datasource<int, SalvarClienteParameters> {
  final proto.AdminServiceClient _client;

  const SalvarClienteDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<int> call(SalvarClienteParameters parameters) async {
    final dados = _dadosParaProto(parameters.dados);
    final id = parameters.id;
    if (id == null) {
      final resp = await _client.createMyCliente(
        proto.CreateMyClienteRequest(dados: dados),
      );
      return resp.cliente.id;
    }
    await _client.updateMyCliente(
      proto.UpdateMyClienteRequest(id: id, dados: dados),
    );
    return id;
  }
}

final class DefinirClienteAtivoDatasource
    implements Datasource<Unit, DefinirClienteAtivoParameters> {
  final proto.AdminServiceClient _client;

  const DefinirClienteAtivoDatasource({
    required proto.AdminServiceClient client,
  })
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(DefinirClienteAtivoParameters parameters) async {
    await _client.definirMyClienteAtivo(
      proto.DefinirMyClienteAtivoRequest(
        id: parameters.id,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

final class ListarContatosDoClienteDatasource
    implements Datasource<List<ContatoDoCliente>, ClienteIdParameters> {
  final proto.AdminServiceClient _client;

  const ListarContatosDoClienteDatasource({
    required proto.AdminServiceClient client,
  })
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<ContatoDoCliente>> call(ClienteIdParameters parameters) async {
    final resp = await _client.listMyContatosDoCliente(
      proto.MyClienteIdRequest(id: parameters.id),
    );
    return resp.contatos
        .map(
          (c) => ContatoDoCliente(id: c.id, nome: c.nome, telefone: c.telefone),
        )
        .toList(growable: false);
  }
}

final class VincularContatoDatasource
    implements Datasource<Unit, VincularContatoParameters> {
  final proto.AdminServiceClient _client;

  const VincularContatoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(VincularContatoParameters parameters) async {
    await _client.vincularMyContatoCliente(
      proto.VincularMyContatoClienteRequest(
        clienteId: parameters.clienteId,
        contatoId: parameters.contatoId,
        vincular: parameters.vincular,
      ),
    );
    return unit;
  }
}
