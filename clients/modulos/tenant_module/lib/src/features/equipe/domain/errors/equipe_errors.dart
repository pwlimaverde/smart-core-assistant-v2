import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da gestão de departamentos e atendentes.
sealed class EquipeError extends AppError {
  const EquipeError(super.message);
}

final class EquipeAcessoNegado extends EquipeError with UnauthorizedFailure {
  const EquipeAcessoNegado()
      : super('Você não tem permissão para gerenciar a equipe.');
}

final class DepartamentoNaoEncontrado extends EquipeError {
  const DepartamentoNaoEncontrado()
      : super('Este departamento não existe mais. Atualize a lista.');
}

/// Recusa do servidor — a mensagem vem dele, que é a autoridade.
final class EquipeDadosInvalidos extends EquipeError with ValidationFailure {
  const EquipeDadosInvalidos([String? mensagem])
      : super(mensagem ?? 'Verifique os dados informados.');
}

/// Teto de departamentos do plano atingido.
final class LimiteDeDepartamentos extends EquipeError {
  const LimiteDeDepartamentos()
      : super('Você atingiu o limite de departamentos do seu plano.');
}

final class EquipeIndisponivel extends EquipeError with NetworkFailure {
  const EquipeIndisponivel()
      : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class EquipeInesperado extends EquipeError {
  const EquipeInesperado() : super('Algo deu errado. Tente de novo.');
}
