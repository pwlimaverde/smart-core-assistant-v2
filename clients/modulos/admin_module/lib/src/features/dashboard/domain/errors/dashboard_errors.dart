import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `dashboard` (painel).
///
/// **Um conjunto para a feature inteira, não um por operação:** as operações
/// aqui são CRUD sobre o mesmo recurso, e o repertório de falha é o mesmo em
/// todas — listar, criar e atualizar podem receber acesso negado, conflito,
/// dado inválido, indisponibilidade. Onde o repertório divergisse de verdade
/// (como no aceite de convite do `tenant_module`, que é rota pública), o
/// conjunto seria separado.
sealed class DashboardError extends AppError {
  const DashboardError(super.message);
}

final class DashboardAcessoNegado extends DashboardError
    with UnauthorizedFailure {
  const DashboardAcessoNegado()
    : super('Somente o superusuário pode ver o painel.');
}

final class DashboardNaoEncontrado extends DashboardError {
  const DashboardNaoEncontrado() : super('Dados do painel indisponíveis.');
}

final class DashboardConflito extends DashboardError {
  const DashboardConflito()
    : super('Leitura conflitante. Recarregue a página.');
}

final class DashboardDadosInvalidos extends DashboardError
    with ValidationFailure {
  const DashboardDadosInvalidos() : super('Parâmetros do painel inválidos.');
}

final class DashboardIndisponivel extends DashboardError with NetworkFailure {
  const DashboardIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class DashboardInesperado extends DashboardError with UnexpectedFailure {
  const DashboardInesperado()
    : super('Não foi possível carregar o painel. Tente novamente.');
}
