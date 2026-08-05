import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da curadoria de intenções.
sealed class IntentsError extends AppError {
  const IntentsError(super.message);
}

final class IntentsAcessoNegado extends IntentsError with UnauthorizedFailure {
  const IntentsAcessoNegado()
      : super('Você não tem permissão para editar as intenções.');
}

final class IntentNaoEncontrada extends IntentsError {
  const IntentNaoEncontrada()
      : super('Esta intenção não existe mais. Atualize a lista.');
}

/// Recusa do servidor — a mensagem vem dele. É por aqui que chega a duplicata
/// de tag+grupo, que tem `UNIQUE` no banco.
final class IntentsRecusado extends IntentsError with ValidationFailure {
  const IntentsRecusado([String? mensagem])
      : super(mensagem ?? 'Verifique os dados informados.');
}

final class IntentsIndisponivel extends IntentsError with NetworkFailure {
  const IntentsIndisponivel()
      : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class IntentsInesperado extends IntentsError {
  const IntentsInesperado() : super('Algo deu errado. Tente de novo.');
}
