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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [ContatosAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class ContatosSessaoExpirada extends ContatosError
    with UnauthorizedFailure {
  const ContatosSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class ContatosIndisponivel extends ContatosError with NetworkFailure {
  const ContatosIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

/// Telefone que já está na lista, ou troca de número barrada pelo histórico.
///
/// A mensagem vem do servidor porque só ele sabe qual dos dois casos é — e a
/// diferença muda o que a pessoa faz em seguida: procurar o contato que já
/// existe, ou cadastrar o número novo à parte.
final class ContatoEmConflito extends ContatosError with ValidationFailure {
  const ContatoEmConflito(String? doServidor)
    : super(doServidor ?? 'Este contato entra em conflito com outro já salvo.');
}

/// Telefone ou e-mail que o servidor recusou.
final class ContatoInvalido extends ContatosError with ValidationFailure {
  const ContatoInvalido(String? doServidor)
    : super(doServidor ?? 'Confira os dados do contato e tente de novo.');
}

final class ContatoNaoEncontrado extends ContatosError {
  const ContatoNaoEncontrado()
    : super('Este contato não existe mais. Recarregue a lista.');
}

final class ContatosInesperado extends ContatosError {
  const ContatosInesperado() : super('Algo deu errado. Tente de novo.');
}
