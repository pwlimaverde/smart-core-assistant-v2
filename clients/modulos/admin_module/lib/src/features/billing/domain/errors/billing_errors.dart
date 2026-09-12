import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `billing` (plano, assinatura ou pagamento).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class BillingError extends AppError {
  const BillingError(super.message);
}

final class BillingAcessoNegado extends BillingError with UnauthorizedFailure {
  const BillingAcessoNegado()
    : super('Somente o superusuário pode administrar a cobrança.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [BillingAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class BillingSessaoExpirada extends BillingError
    with UnauthorizedFailure {
  const BillingSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class BillingNaoEncontrado extends BillingError {
  const BillingNaoEncontrado()
    : super('Plano, assinatura ou pagamento não encontrado.');
}

final class BillingConflito extends BillingError {
  const BillingConflito() : super('Já existe um plano com este nome.');
}

final class BillingDadosInvalidos extends BillingError with ValidationFailure {
  const BillingDadosInvalidos() : super('Verifique os valores informados.');
}

final class BillingIndisponivel extends BillingError with NetworkFailure {
  const BillingIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class BillingInesperado extends BillingError with UnexpectedFailure {
  const BillingInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
