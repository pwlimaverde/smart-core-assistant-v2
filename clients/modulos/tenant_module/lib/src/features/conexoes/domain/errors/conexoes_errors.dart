import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da gestão de conexões de WhatsApp do tenant.
sealed class ConexoesError extends AppError {
  const ConexoesError(super.message);
}

final class ConexoesAcessoNegado extends ConexoesError
    with UnauthorizedFailure {
  const ConexoesAcessoNegado()
      : super('Você não tem permissão para gerenciar as conexões.');
}

final class ConexaoNaoEncontrada extends ConexoesError {
  const ConexaoNaoEncontrada()
      : super('Esta conexão não existe mais. Atualize a lista.');
}

/// O provedor recusou — mensagem dele, que é quem sabe o motivo.
final class ConexaoRecusada extends ConexoesError with ValidationFailure {
  const ConexaoRecusada([String? mensagem])
      : super(mensagem ?? 'O provedor recusou a operação.');
}

final class ConexoesIndisponivel extends ConexoesError with NetworkFailure {
  const ConexoesIndisponivel()
      : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class ConexoesInesperado extends ConexoesError {
  const ConexoesInesperado() : super('Algo deu errado. Tente de novo.');
}
