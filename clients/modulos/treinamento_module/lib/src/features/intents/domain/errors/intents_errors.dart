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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [IntentsAcessoNegado], e o resultado foi um dono de
/// conta lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token dele havia expirado, o refresh foi rejeitado, e todas
/// as chamadas seguintes voltaram `unauthenticated`. A mensagem mandou a pessoa
/// investigar as próprias permissões em vez de reentrar.
final class IntentsSessaoExpirada extends IntentsError
    with UnauthorizedFailure {
  const IntentsSessaoExpirada()
      : super('Sua sessão expirou. Entre de novo para continuar.');
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
