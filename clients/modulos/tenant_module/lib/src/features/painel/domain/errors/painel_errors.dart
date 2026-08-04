import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

sealed class PainelError extends AppError {
  const PainelError(super.message);
}

final class PainelAcessoNegado extends PainelError with UnauthorizedFailure {
  const PainelAcessoNegado() : super('Sua sessão expirou. Entre novamente.');
}

final class PainelIndisponivel extends PainelError with NetworkFailure {
  const PainelIndisponivel()
      : super('Não foi possível carregar os números. Tente de novo.');
}

final class PainelInesperado extends PainelError {
  const PainelInesperado() : super('Algo deu errado. Tente de novo.');
}
