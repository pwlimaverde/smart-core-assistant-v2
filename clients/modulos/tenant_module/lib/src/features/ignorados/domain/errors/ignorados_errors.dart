import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da lista de números ignorados.
sealed class IgnoradosError extends AppError {
  const IgnoradosError(super.message);
}

final class IgnoradosAcessoNegado extends IgnoradosError
    with UnauthorizedFailure {
  const IgnoradosAcessoNegado()
    : super('Você não tem permissão para mexer nos números ignorados.');
}

/// Sessão morta — e NÃO falta de permissão. Juntar as duas manda a pessoa
/// caçar um acesso que ela já tem.
final class IgnoradosSessaoExpirada extends IgnoradosError
    with UnauthorizedFailure {
  const IgnoradosSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class IgnoradoNaoEncontrado extends IgnoradosError {
  const IgnoradoNaoEncontrado()
    : super('Este registro não existe mais. Atualize a lista.');
}

/// O mesmo número duas vezes na lista, ou um número que o servidor recusou.
final class IgnoradoRecusado extends IgnoradosError with ValidationFailure {
  const IgnoradoRecusado([String? mensagem])
    : super(mensagem ?? 'Este número já está na lista.');
}

final class IgnoradosIndisponivel extends IgnoradosError with NetworkFailure {
  const IgnoradosIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class IgnoradosInesperado extends IgnoradosError {
  const IgnoradosInesperado() : super('Algo deu errado. Tente de novo.');
}
