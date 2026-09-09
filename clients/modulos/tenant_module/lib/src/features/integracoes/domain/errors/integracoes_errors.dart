import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da feature de aplicativos conectados (N13.8).
///
/// Um conjunto só para as duas operações: listar e desconectar são o mesmo
/// recurso, do mesmo usuário, com o mesmo repertório de falhas.
sealed class IntegracoesError extends AppError {
  const IntegracoesError(super.message);
}

/// Sessão expirada ou inválida. Não existe "sem permissão" aqui: o recurso é do
/// próprio usuário, então quem está autenticado sempre pode ver e revogar os
/// seus.
final class IntegracoesSessaoInvalida extends IntegracoesError
    with UnauthorizedFailure {
  const IntegracoesSessaoInvalida()
    : super('Sua sessão expirou. Entre novamente.');
}

/// O consentimento não existe mais — provavelmente já foi desconectado, aqui ou
/// em outra aba.
final class ConexaoNaoEncontrada extends IntegracoesError {
  const ConexaoNaoEncontrada()
    : super('Este aplicativo já não está conectado.');
}

final class IntegracoesIndisponivel extends IntegracoesError
    with NetworkFailure {
  const IntegracoesIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class IntegracoesInesperado extends IntegracoesError
    with UnexpectedFailure {
  const IntegracoesInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
