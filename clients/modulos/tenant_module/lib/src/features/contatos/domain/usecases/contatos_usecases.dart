import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/contatos_errors.dart';
import '../model/contato.dart';
import '../parameters/contatos_parameters.dart';

ContatosError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.contatos.usecase',
    error: e,
    stackTrace: s,
  );
  return const ContatosInesperado();
}

final class ListarContatosUsecase
    extends
        UsecaseBaseCallData<
          List<Contato>,
          List<Contato>,
          ListarContatosParameters,
          ContatosError
        > {
  const ListarContatosUsecase({required super.repository});

  @override
  ProcessData<
    List<Contato>,
    List<Contato>,
    ListarContatosParameters,
    ContatosError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ContatosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar contatos', e, s);
}

final class CriarContatoUsecase
    extends
        UsecaseBaseCallData<
          Contato,
          Contato,
          CriarContatoParameters,
          ContatosError
        > {
  const CriarContatoUsecase({required super.repository});

  @override
  ProcessData<Contato, Contato, CriarContatoParameters, ContatosError>
  get process =>
      (data, _) => Success(data);

  @override
  ContatosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar contato', e, s);
}

final class AtualizarContatoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          AtualizarContatoParameters,
          ContatosError
        > {
  const AtualizarContatoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarContatoParameters, ContatosError>
  get process =>
      (data, _) => Success(data);

  @override
  ContatosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar contato', e, s);
}

final class DefinirContatoAtivoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirContatoAtivoParameters,
          ContatosError
        > {
  const DefinirContatoAtivoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirContatoAtivoParameters, ContatosError>
  get process =>
      (data, _) => Success(data);

  @override
  ContatosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('definir contato ativo', e, s);
}
