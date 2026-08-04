import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/conexoes_errors.dart';
import '../model/conexao.dart';
import '../parameters/conexoes_parameters.dart';

ConexoesError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.conexoes.usecase',
    error: e,
    stackTrace: s,
  );
  return const ConexoesInesperado();
}

final class ListarConexoesUsecase extends UsecaseBaseCallData<List<Conexao>,
    List<Conexao>, NoParams, ConexoesError> {
  const ListarConexoesUsecase({required super.repository});

  @override
  ProcessData<List<Conexao>, List<Conexao>, NoParams, ConexoesError>
      get process => (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar conexões', e, s);
}

final class ReconectarConexaoUsecase extends UsecaseBaseCallData<Unit, Unit,
    ConexaoIdParameters, ConexoesError> {
  const ReconectarConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, ConexaoIdParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('reconectar', e, s);
}

final class RemoverConexaoUsecase extends UsecaseBaseCallData<Unit, Unit,
    ConexaoIdParameters, ConexoesError> {
  const RemoverConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, ConexaoIdParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover conexão', e, s);
}
