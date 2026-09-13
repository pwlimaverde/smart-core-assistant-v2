import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/clientes_errors.dart';
import '../model/cliente.dart';
import '../parameters/clientes_parameters.dart';

ClientesError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.clientes.usecase',
    error: e,
    stackTrace: s,
  );
  return const ClientesInesperado();
}

final class ListarClientesUsecase
    extends
        UsecaseBaseCallData<
          List<Cliente>,
          List<Cliente>,
          ListarClientesParameters,
          ClientesError
        > {
  const ListarClientesUsecase({required super.repository});

  @override
  ProcessData<
    List<Cliente>,
    List<Cliente>,
    ListarClientesParameters,
    ClientesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ClientesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar clientes', e, s);
}

final class SalvarClienteUsecase
    extends
        UsecaseBaseCallData<int, int, SalvarClienteParameters, ClientesError> {
  const SalvarClienteUsecase({required super.repository});

  @override
  ProcessData<int, int, SalvarClienteParameters, ClientesError> get process =>
      (data, _) => Success(data);

  @override
  ClientesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('salvar cliente', e, s);
}

final class DefinirClienteAtivoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirClienteAtivoParameters,
          ClientesError
        > {
  const DefinirClienteAtivoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirClienteAtivoParameters, ClientesError>
  get process =>
      (data, _) => Success(data);

  @override
  ClientesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('definir cliente ativo', e, s);
}

final class ListarContatosDoClienteUsecase
    extends
        UsecaseBaseCallData<
          List<ContatoDoCliente>,
          List<ContatoDoCliente>,
          ClienteIdParameters,
          ClientesError
        > {
  const ListarContatosDoClienteUsecase({required super.repository});

  @override
  ProcessData<
    List<ContatoDoCliente>,
    List<ContatoDoCliente>,
    ClienteIdParameters,
    ClientesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ClientesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar contatos do cliente', e, s);
}

final class VincularContatoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          VincularContatoParameters,
          ClientesError
        > {
  const VincularContatoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, VincularContatoParameters, ClientesError>
  get process =>
      (data, _) => Success(data);

  @override
  ClientesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('vincular contato', e, s);
}
