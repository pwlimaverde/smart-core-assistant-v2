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

final class ListarConexoesUsecase
    extends
        UsecaseBaseCallData<
          List<Conexao>,
          List<Conexao>,
          NoParams,
          ConexoesError
        > {
  const ListarConexoesUsecase({required super.repository});

  @override
  ProcessData<List<Conexao>, List<Conexao>, NoParams, ConexoesError>
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar conexões', e, s);
}

final class ReconectarConexaoUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, ConexaoIdParameters, ConexoesError> {
  const ReconectarConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, ConexaoIdParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('reconectar', e, s);
}

final class RemoverConexaoUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, ConexaoIdParameters, ConexoesError> {
  const RemoverConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, ConexaoIdParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover conexão', e, s);
}

final class CriarConexaoUsecase
    extends
        UsecaseBaseCallData<
          ConexaoCriada,
          ConexaoCriada,
          CriarConexaoParameters,
          ConexoesError
        > {
  const CriarConexaoUsecase({required super.repository});

  @override
  ProcessData<
    ConexaoCriada,
    ConexaoCriada,
    CriarConexaoParameters,
    ConexoesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar conexão', e, s);
}

final class EstadoPareamentoUsecase
    extends
        UsecaseBaseCallData<
          EstadoPareamento,
          EstadoPareamento,
          ConexaoIdParameters,
          ConexoesError
        > {
  const EstadoPareamentoUsecase({required super.repository});

  @override
  ProcessData<
    EstadoPareamento,
    EstadoPareamento,
    ConexaoIdParameters,
    ConexoesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('consultar pareamento', e, s);
}

final class DefinirRespostaBotUsecase
    extends
        UsecaseBaseCallData<bool, bool, RespostaBotParameters, ConexoesError> {
  const DefinirRespostaBotUsecase({required super.repository});

  @override
  ProcessData<bool, bool, RespostaBotParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('definirRespostaBot', e, s);
}

/// P7 — encerra a sessão sem apagar a conexão.
final class DesconectarConexaoUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, ConexaoIdParameters, ConexoesError> {
  const DesconectarConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, ConexaoIdParameters, ConexoesError> get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('desconectar', e, s);
}

/// P7 — roteamento por conexão.
final class DefinirDepartamentoDaConexaoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DepartamentoDaConexaoParameters,
          ConexoesError
        > {
  const DefinirDepartamentoDaConexaoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DepartamentoDaConexaoParameters, ConexoesError>
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('definir departamento da conexão', e, s);
}

/// P7 — o detalhe da conexão.
final class DetalheDaConexaoUsecase
    extends
        UsecaseBaseCallData<
          DetalheConexao,
          DetalheConexao,
          ConexaoIdParameters,
          ConexoesError
        > {
  const DetalheDaConexaoUsecase({required super.repository});

  @override
  ProcessData<DetalheConexao, DetalheConexao, ConexaoIdParameters, ConexoesError>
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('detalhe da conexão', e, s);
}

/// P9 — as mensagens que ficaram sem destino.
final class ListarNaoEntreguesUsecase
    extends
        UsecaseBaseCallData<
          List<MensagemParada>,
          List<MensagemParada>,
          NoParams,
          ConexoesError
        > {
  const ListarNaoEntreguesUsecase({required super.repository});

  @override
  ProcessData<
    List<MensagemParada>,
    List<MensagemParada>,
    NoParams,
    ConexoesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar não entregues', e, s);
}

/// P9 — devolve a mensagem ao outbox.
final class ReenviarNaoEntregueUsecase
    extends
        UsecaseBaseCallData<
          DesfechoReenvio,
          DesfechoReenvio,
          ConexaoIdParameters,
          ConexoesError
        > {
  const ReenviarNaoEntregueUsecase({required super.repository});

  @override
  ProcessData<
    DesfechoReenvio,
    DesfechoReenvio,
    ConexaoIdParameters,
    ConexoesError
  >
  get process =>
      (data, _) => Success(data);

  @override
  ConexoesError onUnexpected(Object e, StackTrace s) =>
      _inesperado('reenviar não entregue', e, s);
}
