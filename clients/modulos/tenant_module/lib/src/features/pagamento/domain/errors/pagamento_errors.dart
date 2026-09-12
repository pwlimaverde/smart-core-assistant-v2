import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da quitação da assinatura.
///
/// Repertório curto de propósito: recusa de voucher (expirado, esgotado, já
/// usado) **não** aparece aqui — vem como sucesso com `confirmado: false` e
/// mensagem, para a tela mostrá-la junto do campo. Estes são os casos em que a
/// chamada não chegou a acontecer.
sealed class PagamentoError extends AppError {
  const PagamentoError(super.message);
}

/// Sem escopo `tenant:admin`: cobrança é assunto do dono da conta.
final class PagamentoAcessoNegado extends PagamentoError
    with UnauthorizedFailure {
  const PagamentoAcessoNegado()
    : super('Só o responsável pela conta pode resolver o pagamento.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [PagamentoAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class PagamentoSessaoExpirada extends PagamentoError
    with UnauthorizedFailure {
  const PagamentoSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// Provedor desconhecido ou dados recusados na borda.
final class PagamentoDadosInvalidos extends PagamentoError
    with ValidationFailure {
  const PagamentoDadosInvalidos()
    : super('Forma de pagamento indisponível. Recarregue a tela.');
}

final class PagamentoIndisponivel extends PagamentoError with NetworkFailure {
  const PagamentoIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class PagamentoInesperado extends PagamentoError with UnexpectedFailure {
  const PagamentoInesperado()
    : super('Não foi possível concluir. Tente novamente.');
}
