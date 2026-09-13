import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da recuperação de senha (N11 E8) — um conjunto por operação, como no
/// login, porque o repertório das duas é diferente.

// ─── pedir o link ─────────────────────────────────────────────────────────────

/// Erros de pedir o link.
///
/// Não existe "conta não encontrada", e é de propósito: o servidor responde
/// igual exista a conta ou não. Um erro assim na tela diria a qualquer um quais
/// e-mails têm conta aqui.
sealed class SolicitarRedefinicaoError extends AppError {
  const SolicitarRedefinicaoError(super.message);
}

final class RedefinicaoMuitosPedidos extends SolicitarRedefinicaoError {
  const RedefinicaoMuitosPedidos()
    : super('Muitos pedidos seguidos. Aguarde alguns minutos e tente de novo.');
}

final class SolicitarRedefinicaoIndisponivel extends SolicitarRedefinicaoError
    with NetworkFailure {
  const SolicitarRedefinicaoIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class SolicitarRedefinicaoInesperado extends SolicitarRedefinicaoError
    with UnexpectedFailure {
  const SolicitarRedefinicaoInesperado()
    : super('Não foi possível pedir o link. Tente novamente.');
}

// ─── trocar a senha ───────────────────────────────────────────────────────────

/// Erros de trocar a senha com o link.
sealed class RedefinirSenhaError extends AppError {
  const RedefinirSenhaError(super.message);
}

/// O link venceu, já foi usado, ou nunca valeu.
///
/// Os três são uma mensagem só: distinguir "vencido" de "não existe" diria a
/// quem tem o link se ele algum dia foi válido. O que a pessoa precisa saber é
/// o que fazer — pedir outro.
final class LinkDeRedefinicaoInvalido extends RedefinirSenhaError {
  const LinkDeRedefinicaoInvalido()
    : super('Este link não vale mais. Peça um novo na tela de login.');
}

/// A senha nova não passou na regra do servidor.
final class SenhaRecusada extends RedefinirSenhaError with ValidationFailure {
  const SenhaRecusada() : super('Escolha uma senha com ao menos 8 caracteres.');
}

final class RedefinirSenhaMuitasTentativas extends RedefinirSenhaError {
  const RedefinirSenhaMuitasTentativas()
    : super('Muitas tentativas seguidas. Aguarde alguns minutos.');
}

final class RedefinirSenhaIndisponivel extends RedefinirSenhaError
    with NetworkFailure {
  const RedefinirSenhaIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class RedefinirSenhaInesperado extends RedefinirSenhaError
    with UnexpectedFailure {
  const RedefinirSenhaInesperado()
    : super('Não foi possível trocar a senha. Tente novamente.');
}
