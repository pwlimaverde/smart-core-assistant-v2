import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da lista de contatos.
sealed class ContatosError extends AppError {
  const ContatosError(super.message);
}

final class ContatosAcessoNegado extends ContatosError
    with UnauthorizedFailure {
  const ContatosAcessoNegado()
      : super('Você não tem permissão para ver os contatos.');
}

final class ContatosIndisponivel extends ContatosError with NetworkFailure {
  const ContatosIndisponivel()
      : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class ContatosInesperado extends ContatosError {
  const ContatosInesperado() : super('Algo deu errado. Tente de novo.');
}
