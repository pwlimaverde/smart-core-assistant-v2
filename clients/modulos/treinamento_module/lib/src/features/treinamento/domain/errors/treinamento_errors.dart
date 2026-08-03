import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros do treinamento da IA.
sealed class TreinamentoError extends AppError {
  const TreinamentoError(super.message);
}

/// O servidor recusou os dados — a mensagem vem dele, que é a autoridade.
final class TreinamentoDadosInvalidos extends TreinamentoError
    with ValidationFailure {
  const TreinamentoDadosInvalidos([String? mensagem])
      : super(mensagem ?? 'Verifique os dados informados.');
}

/// Sessão expirada ou sem escopo de treinamento.
final class TreinamentoNaoAutorizado extends TreinamentoError
    with UnauthorizedFailure {
  const TreinamentoNaoAutorizado()
      : super('Sua sessão expirou ou você não tem permissão para treinar a IA.');
}

/// Servidor fora do ar.
final class TreinamentoIndisponivel extends TreinamentoError
    with NetworkFailure {
  const TreinamentoIndisponivel()
      : super('Não foi possível falar com o servidor. Tente de novo.');
}

/// Qualquer coisa que não soubemos classificar.
final class TreinamentoInesperado extends TreinamentoError {
  const TreinamentoInesperado([String? mensagem])
      : super(mensagem ?? 'Algo deu errado. Tente de novo.');
}
