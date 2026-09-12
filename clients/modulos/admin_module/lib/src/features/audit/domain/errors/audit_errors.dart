import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `audit` (registro de auditoria).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class AuditError extends AppError {
  const AuditError(super.message);
}

final class AuditAcessoNegado extends AuditError with UnauthorizedFailure {
  const AuditAcessoNegado()
    : super('Somente o superusuário pode consultar a auditoria.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [AuditAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class AuditSessaoExpirada extends AuditError with UnauthorizedFailure {
  const AuditSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class AuditNaoEncontrado extends AuditError {
  const AuditNaoEncontrado() : super('Nenhum registro corresponde ao filtro.');
}

final class AuditConflito extends AuditError {
  const AuditConflito() : super('Consulta conflitante. Recarregue a página.');
}

final class AuditDadosInvalidos extends AuditError with ValidationFailure {
  const AuditDadosInvalidos() : super('Verifique os filtros informados.');
}

final class AuditIndisponivel extends AuditError with NetworkFailure {
  const AuditIndisponivel() : super('Servidor indisponível. Tente novamente.');
}

final class AuditInesperado extends AuditError with UnexpectedFailure {
  const AuditInesperado()
    : super('Não foi possível consultar a auditoria. Tente novamente.');
}
