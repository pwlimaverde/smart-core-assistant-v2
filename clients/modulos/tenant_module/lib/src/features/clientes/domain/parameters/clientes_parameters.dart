import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/cliente.dart';

final class ListarClientesParameters extends Parameters {
  /// Casa nome fantasia, razão social e documento. Vazio = sem filtro.
  final String busca;
  final bool incluirInativos;

  const ListarClientesParameters({
    this.busca = '',
    this.incluirInativos = false,
  });
}

/// Cadastro (`id` nulo) ou edição.
final class SalvarClienteParameters extends Parameters {
  final int? id;
  final DadosCliente dados;

  const SalvarClienteParameters({this.id, required this.dados});
}

final class DefinirClienteAtivoParameters extends Parameters {
  final int id;
  final bool ativo;

  const DefinirClienteAtivoParameters({required this.id, required this.ativo});
}

final class ClienteIdParameters extends Parameters {
  final int id;

  const ClienteIdParameters({required this.id});
}

final class VincularContatoParameters extends Parameters {
  final int clienteId;
  final int contatoId;

  /// `false` = desligar.
  final bool vincular;

  const VincularContatoParameters({
    required this.clienteId,
    required this.contatoId,
    this.vincular = true,
  });
}
