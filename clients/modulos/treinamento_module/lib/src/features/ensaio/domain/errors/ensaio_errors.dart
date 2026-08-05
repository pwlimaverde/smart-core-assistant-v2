import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros do ensaio de pergunta.
sealed class EnsaioError extends AppError {
  const EnsaioError(super.message);
}

final class EnsaioAcessoNegado extends EnsaioError with UnauthorizedFailure {
  const EnsaioAcessoNegado()
      : super('Você não tem permissão para testar o assistente.');
}

final class EnsaioPerguntaInvalida extends EnsaioError with ValidationFailure {
  const EnsaioPerguntaInvalida([String? mensagem])
      : super(mensagem ?? 'Escreva a pergunta a testar.');
}

/// A IA não respondeu.
///
/// Separado de "servidor fora do ar" de propósito: o provedor de IA pode estar
/// fora com o resto do sistema de pé, e a ação de quem vê a mensagem é
/// diferente — esperar, e não procurar problema no treinamento.
final class EnsaioIaIndisponivel extends EnsaioError with NetworkFailure {
  const EnsaioIaIndisponivel()
      : super('A IA não respondeu agora. Tente de novo em instantes.');
}

final class EnsaioInesperado extends EnsaioError {
  const EnsaioInesperado() : super('Algo deu errado. Tente de novo.');
}
