import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

sealed class PainelError extends AppError {
  const PainelError(super.message);
}

final class PainelAcessoNegado extends PainelError with UnauthorizedFailure {
  const PainelAcessoNegado() : super('Sua sessão expirou. Entre novamente.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [PainelAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class PainelSessaoExpirada extends PainelError with UnauthorizedFailure {
  const PainelSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class PainelIndisponivel extends PainelError with NetworkFailure {
  const PainelIndisponivel()
    : super('Não foi possível carregar os números. Tente de novo.');
}

final class PainelInesperado extends PainelError {
  const PainelInesperado() : super('Algo deu errado. Tente de novo.');
}
