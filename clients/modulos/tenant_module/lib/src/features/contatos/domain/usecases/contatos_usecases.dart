import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/contatos_errors.dart';
import '../model/contato.dart';
import '../parameters/contatos_parameters.dart';

final class ListarContatosUsecase extends UsecaseBaseCallData<List<Contato>,
    List<Contato>, ListarContatosParameters, ContatosError> {
  const ListarContatosUsecase({required super.repository});

  @override
  ProcessData<List<Contato>, List<Contato>, ListarContatosParameters,
      ContatosError> get process => (data, _) => Success(data);

  @override
  ContatosError onUnexpected(Object e, StackTrace s) {
    developer.log(
      'listar contatos: exceção fora da fronteira',
      name: 'tenant_module.contatos.usecase',
      error: e,
      stackTrace: s,
    );
    return const ContatosInesperado();
  }
}
