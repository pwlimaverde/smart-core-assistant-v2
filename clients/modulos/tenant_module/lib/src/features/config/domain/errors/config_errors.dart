import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da feature de configuração do próprio tenant (persona do bot, modelos
/// de IA, chaves de API). Leitura e escrita têm o mesmo repertório.
sealed class TenantConfigError extends AppError {
  const TenantConfigError(super.message);
}

final class ConfigAcessoNegado extends TenantConfigError
    with UnauthorizedFailure {
  const ConfigAcessoNegado()
    : super('Você não tem permissão para alterar a configuração do tenant.');
}

/// Valor recusado pelo servidor (temperatura fora da faixa, modelo inexistente,
/// limiar inválido).
final class ConfigDadosInvalidos extends TenantConfigError
    with ValidationFailure {
  const ConfigDadosInvalidos()
    : super('Verifique os valores informados na configuração.');
}

final class ConfigIndisponivel extends TenantConfigError with NetworkFailure {
  const ConfigIndisponivel() : super('Servidor indisponível. Tente novamente.');
}

final class ConfigInesperado extends TenantConfigError with UnexpectedFailure {
  const ConfigInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
