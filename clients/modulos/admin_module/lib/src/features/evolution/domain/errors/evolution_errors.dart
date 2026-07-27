import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `evolution` (instância do Evolution).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class EvolutionError extends AppError {
  const EvolutionError(super.message);
}

final class EvolutionAcessoNegado extends EvolutionError
    with UnauthorizedFailure {
  const EvolutionAcessoNegado()
    : super('Somente o superusuário pode testar instâncias.');
}

final class EvolutionNaoEncontrado extends EvolutionError {
  const EvolutionNaoEncontrado() : super('Tenant sem instância configurada.');
}

final class EvolutionConflito extends EvolutionError {
  const EvolutionConflito()
    : super('A instância está em uso por outra operação.');
}

final class EvolutionDadosInvalidos extends EvolutionError
    with ValidationFailure {
  const EvolutionDadosInvalidos()
    : super('Configuração da instância incompleta.');
}

final class EvolutionIndisponivel extends EvolutionError with NetworkFailure {
  const EvolutionIndisponivel()
    : super('Não foi possível falar com o provedor. Tente novamente.');
}

final class EvolutionInesperado extends EvolutionError with UnexpectedFailure {
  const EvolutionInesperado()
    : super('Não foi possível testar a conexão. Tente novamente.');
}
