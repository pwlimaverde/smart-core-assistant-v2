import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/cadastro_errors.dart';
import '../model/cadastro_models.dart';
import '../parameters/cadastro_parameters.dart';

/// Usecases do wizard.
///
/// A maioria é passthrough — o repositório já entrega o modelo pronto. Não é
/// código morto: é onde uma regra de cliente entraria, e é o que garante que uma
/// exceção no caminho vire [CadastroError] em vez de escapar para o controller.
/// [IniciarCadastroUsecase] e [ConfirmarPagamentoUsecase] têm regra de verdade.

CadastroError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    'process de $operacao quebrou',
    name: 'onboarding_module.cadastro',
    error: e,
    stackTrace: s,
  );
  return const CadastroInesperado();
}

final class VerificarSlugUsecase extends UsecaseBaseCallData<
    SlugDisponibilidade, SlugDisponibilidade, SlugParameters, CadastroError> {
  const VerificarSlugUsecase({required super.repository});

  @override
  ProcessData<SlugDisponibilidade, SlugDisponibilidade, SlugParameters,
      CadastroError> get process => (data, _) => Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('verificar slug', e, s);
}

final class ListarPlanosUsecase extends UsecaseBaseCallData<List<PlanoPublico>,
    List<PlanoPublico>, SemParametros, CadastroError> {
  const ListarPlanosUsecase({required super.repository});

  @override
  ProcessData<List<PlanoPublico>, List<PlanoPublico>, SemParametros,
      CadastroError> get process => (data, _) => Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar planos', e, s);
}

final class ListarProvedoresUsecase extends UsecaseBaseCallData<
    List<ProvedorPagamento>,
    List<ProvedorPagamento>,
    SemParametros,
    CadastroError> {
  const ListarProvedoresUsecase({required super.repository});

  /// Nenhuma forma de pagamento habilitada é falha de configuração do servidor,
  /// não uma lista vazia a exibir: sem provedor, ninguém conclui o cadastro, e a
  /// tela precisa dizer isso em vez de mostrar um espaço em branco.
  @override
  ProcessData<List<ProvedorPagamento>, List<ProvedorPagamento>, SemParametros,
          CadastroError>
      get process => (data, _) => data.isEmpty
          ? const Failure(CadastroIndisponivel())
          : Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar provedores', e, s);
}

final class IniciarCadastroUsecase extends UsecaseBaseCallData<
    CadastroIniciado,
    CadastroIniciado,
    IniciarCadastroParameters,
    CadastroError> {
  const IniciarCadastroUsecase({required super.repository});

  /// Sem `signup_token` os passos seguintes são inalcançáveis. Um servidor que
  /// responde 200 sem o token deixaria o usuário preso numa tela que não avança;
  /// falhar aqui pelo menos dá a ele o botão de tentar de novo.
  @override
  ProcessData<CadastroIniciado, CadastroIniciado, IniciarCadastroParameters,
          CadastroError>
      get process => (data, _) =>
          data.signupToken.isEmpty || data.tenantId.isEmpty
              ? const Failure(CadastroInesperado())
              : Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('iniciar cadastro', e, s);
}

final class SelecionarPlanoUsecase extends UsecaseBaseCallData<int, int,
    SelecionarPlanoParameters, CadastroError> {
  const SelecionarPlanoUsecase({required super.repository});

  @override
  ProcessData<int, int, SelecionarPlanoParameters, CadastroError> get process =>
      (data, _) => Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('selecionar plano', e, s);
}

final class ConfirmarPagamentoUsecase extends UsecaseBaseCallData<
    ResultadoPagamento,
    ResultadoPagamento,
    ConfirmarPagamentoParameters,
    CadastroError> {
  const ConfirmarPagamentoUsecase({required super.repository});

  /// **A recusa passa como `Success`.** Código expirado ou revogado não é falha
  /// da operação: o servidor respondeu, e a resposta é "não". A tela mostra
  /// `mensagem` no campo e deixa o usuário tentar outro código — o que um
  /// `Failure` transformaria num erro de sistema, indistinguível de servidor
  /// fora do ar.
  ///
  /// O que este `process` barra é a resposta incoerente: não confirmou, não
  /// mandou redirecionar e não explicou por quê. Aí não há o que mostrar.
  @override
  ProcessData<ResultadoPagamento, ResultadoPagamento,
          ConfirmarPagamentoParameters, CadastroError>
      get process => (data, _) =>
          !data.confirmado &&
                  !data.exigeRedirecionamento &&
                  data.mensagem.trim().isEmpty
              ? const Failure(CadastroInesperado())
              : Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('confirmar pagamento', e, s);
}

final class StatusCadastroUsecase extends UsecaseBaseCallData<StatusCadastro,
    StatusCadastro, StatusCadastroParameters, CadastroError> {
  const StatusCadastroUsecase({required super.repository});

  @override
  ProcessData<StatusCadastro, StatusCadastro, StatusCadastroParameters,
      CadastroError> get process => (data, _) => Success(data);

  @override
  CadastroError onUnexpected(Object e, StackTrace s) =>
      _inesperado('consultar status', e, s);
}
