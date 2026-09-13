import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros do cadastro de clientes (B10).
sealed class ClientesError extends AppError {
  const ClientesError(super.message);
}

final class ClientesAcessoNegado extends ClientesError
    with UnauthorizedFailure {
  const ClientesAcessoNegado()
    : super('Você não tem permissão para mexer nos clientes.');
}

/// Sessão morta — e NÃO falta de permissão.
final class ClientesSessaoExpirada extends ClientesError
    with UnauthorizedFailure {
  const ClientesSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class ClientesIndisponivel extends ClientesError with NetworkFailure {
  const ClientesIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

/// O servidor recusou os dados — a mensagem dele diz o quê (CNPJ com tamanho
/// errado, UF, cliente que não existe mais).
final class ClienteInvalido extends ClientesError with ValidationFailure {
  const ClienteInvalido(String? doServidor)
    : super(doServidor ?? 'Confira os dados do cliente e tente de novo.');
}

final class ClientesInesperado extends ClientesError {
  const ClientesInesperado() : super('Algo deu errado. Tente de novo.');
}
