import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da tela "Transferência para atendente".
sealed class TransferenciaError extends AppError {
  const TransferenciaError(super.message);
}

final class TransferenciaAcessoNegado extends TransferenciaError
    with UnauthorizedFailure {
  const TransferenciaAcessoNegado()
    : super('Você não tem permissão para mexer nas regras de transferência.');
}

final class TransferenciaSessaoExpirada extends TransferenciaError
    with UnauthorizedFailure {
  const TransferenciaSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// O servidor recusou (condição vaga, nome repetido, destino sem fluxo…) —
/// a mensagem dele vai para a tela como veio.
final class TransferenciaRecusada extends TransferenciaError
    with ValidationFailure {
  const TransferenciaRecusada([String? mensagem])
    : super(mensagem ?? 'O servidor recusou a alteração.');
}

final class TransferenciaIndisponivel extends TransferenciaError
    with NetworkFailure {
  const TransferenciaIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class TransferenciaInesperado extends TransferenciaError {
  const TransferenciaInesperado() : super('Algo deu errado. Tente de novo.');
}
