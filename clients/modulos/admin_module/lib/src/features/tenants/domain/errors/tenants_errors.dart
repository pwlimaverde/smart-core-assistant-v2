import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `tenants` (tenant).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class TenantsError extends AppError {
  const TenantsError(super.message);
}

final class TenantsAcessoNegado extends TenantsError with UnauthorizedFailure {
  const TenantsAcessoNegado()
    : super('Somente o superusuário pode administrar tenants.');
}

final class TenantsNaoEncontrado extends TenantsError {
  const TenantsNaoEncontrado() : super('Tenant não encontrado.');
}

final class TenantsConflito extends TenantsError {
  const TenantsConflito()
    : super('Já existe um tenant com este slug ou e-mail.');
}

final class TenantsDadosInvalidos extends TenantsError with ValidationFailure {
  const TenantsDadosInvalidos() : super('Verifique os dados do tenant.');
}

final class TenantsIndisponivel extends TenantsError with NetworkFailure {
  const TenantsIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class TenantsInesperado extends TenantsError with UnexpectedFailure {
  const TenantsInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
