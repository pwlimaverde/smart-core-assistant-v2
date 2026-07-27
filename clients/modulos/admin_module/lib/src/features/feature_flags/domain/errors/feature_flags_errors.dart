import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `feature_flags` (feature flag).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class FeatureFlagsError extends AppError {
  const FeatureFlagsError(super.message);
}

final class FeatureFlagsAcessoNegado extends FeatureFlagsError
    with UnauthorizedFailure {
  const FeatureFlagsAcessoNegado()
    : super('Somente o superusuário pode alterar feature flags.');
}

final class FeatureFlagsNaoEncontrado extends FeatureFlagsError {
  const FeatureFlagsNaoEncontrado() : super('Flag ou tenant não encontrado.');
}

final class FeatureFlagsConflito extends FeatureFlagsError {
  const FeatureFlagsConflito()
    : super('Já existe um override desta flag para o tenant.');
}

final class FeatureFlagsDadosInvalidos extends FeatureFlagsError
    with ValidationFailure {
  const FeatureFlagsDadosInvalidos()
    : super('Verifique a flag e o tenant informados.');
}

final class FeatureFlagsIndisponivel extends FeatureFlagsError
    with NetworkFailure {
  const FeatureFlagsIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class FeatureFlagsInesperado extends FeatureFlagsError
    with UnexpectedFailure {
  const FeatureFlagsInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
