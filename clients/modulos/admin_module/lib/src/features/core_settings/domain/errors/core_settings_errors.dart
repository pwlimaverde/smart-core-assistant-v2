import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `core_settings` (configuração global).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class CoreSettingsError extends AppError {
  const CoreSettingsError(super.message);
}

final class CoreSettingsAcessoNegado extends CoreSettingsError
    with UnauthorizedFailure {
  const CoreSettingsAcessoNegado()
    : super('Somente o superusuário pode alterar configurações globais.');
}

final class CoreSettingsNaoEncontrado extends CoreSettingsError {
  const CoreSettingsNaoEncontrado() : super('Configuração não encontrada.');
}

final class CoreSettingsConflito extends CoreSettingsError {
  const CoreSettingsConflito()
    : super('Já existe uma configuração com esta chave.');
}

final class CoreSettingsDadosInvalidos extends CoreSettingsError
    with ValidationFailure {
  const CoreSettingsDadosInvalidos()
    : super('Verifique a chave e o valor informados.');
}

final class CoreSettingsIndisponivel extends CoreSettingsError
    with NetworkFailure {
  const CoreSettingsIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class CoreSettingsInesperado extends CoreSettingsError
    with UnexpectedFailure {
  const CoreSettingsInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
