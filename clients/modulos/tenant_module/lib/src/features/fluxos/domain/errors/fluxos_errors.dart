import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da gestão de fluxos e etapas.
sealed class FluxosError extends AppError {
  const FluxosError(super.message);
}

final class FluxosAcessoNegado extends FluxosError with UnauthorizedFailure {
  const FluxosAcessoNegado()
    : super('Você não tem permissão para gerenciar fluxos.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [FluxosAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class FluxosSessaoExpirada extends FluxosError with UnauthorizedFailure {
  const FluxosSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// Recusa do servidor — a mensagem vem dele, que é quem conhece o motivo.
///
/// É por aqui que chegam as regras que a tela não consegue verificar sozinha:
/// etapa com atendimento parado nela, última fila de entrada, fluxo com
/// conversa aberta.
final class FluxosRecusado extends FluxosError with ValidationFailure {
  const FluxosRecusado([String? mensagem])
    : super(mensagem ?? 'Não foi possível concluir. Verifique os dados.');
}

/// Teto de fluxos do plano atingido.
final class LimiteDeFluxos extends FluxosError {
  const LimiteDeFluxos()
    : super('Você atingiu o limite de fluxos do seu plano.');
}

final class FluxoNaoEncontrado extends FluxosError {
  const FluxoNaoEncontrado()
    : super('Este item não existe mais. Atualize a lista.');
}

final class FluxosIndisponivel extends FluxosError with NetworkFailure {
  const FluxosIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class FluxosInesperado extends FluxosError {
  const FluxosInesperado() : super('Algo deu errado. Tente de novo.');
}
