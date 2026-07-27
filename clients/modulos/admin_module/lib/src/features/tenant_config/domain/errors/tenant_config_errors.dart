import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `tenant_config` (configuração de tenant).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class TenantConfigError extends AppError {
  const TenantConfigError(super.message);
}

final class TenantConfigAcessoNegado extends TenantConfigError
    with UnauthorizedFailure {
  const TenantConfigAcessoNegado()
    : super('Somente o superusuário pode alterar a configuração de um tenant.');
}

final class TenantConfigNaoEncontrado extends TenantConfigError {
  const TenantConfigNaoEncontrado() : super('Tenant não encontrado.');
}

final class TenantConfigConflito extends TenantConfigError {
  const TenantConfigConflito()
    : super(
        'A configuração foi alterada por outra sessão. Recarregue e tente novamente.',
      );
}

final class TenantConfigDadosInvalidos extends TenantConfigError
    with ValidationFailure {
  const TenantConfigDadosInvalidos()
    : super('Verifique os valores informados na configuração.');
}

final class TenantConfigIndisponivel extends TenantConfigError
    with NetworkFailure {
  const TenantConfigIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class TenantConfigInesperado extends TenantConfigError
    with UnexpectedFailure {
  const TenantConfigInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
