import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros do catálogo de campos do cartão (N9 E13).
sealed class CamposError extends AppError {
  const CamposError(super.message);
}

final class CamposAcessoNegado extends CamposError with UnauthorizedFailure {
  const CamposAcessoNegado()
    : super('Você não tem permissão para configurar os campos do cartão.');
}

/// Sessão morta — e **não** falta de permissão.
///
/// As duas chegavam como acesso negado no resto do app, e o resultado foi um
/// dono de conta caçando permissões que sempre teve. Aqui já nascem separadas.
final class CamposSessaoExpirada extends CamposError with UnauthorizedFailure {
  const CamposSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class CampoNaoEncontrado extends CamposError {
  const CampoNaoEncontrado()
    : super('Este campo não existe mais. Atualize a lista.');
}

/// O servidor recusou com um motivo legível — nome vazio, lista sem opções,
/// escopo de fluxo sem quadro. A mensagem é dele, que é quem sabe o que falta.
final class CampoInvalido extends CamposError with ValidationFailure {
  const CampoInvalido([String? mensagem])
    : super(mensagem ?? 'Confira os dados do campo.');
}

/// Já existe um campo com esse nome no mesmo escopo.
///
/// O slug vem do nome, e dois campos com o mesmo slug seriam indistinguíveis
/// para a IA — que grava o valor **pelo slug**.
final class CampoDuplicado extends CamposError with ValidationFailure {
  const CampoDuplicado()
    : super('Já existe um campo com esse nome. Escolha outro.');
}

final class CamposIndisponivel extends CamposError with NetworkFailure {
  const CamposIndisponivel()
    : super('Não foi possível falar com o servidor. Tente de novo.');
}

final class CamposInesperado extends CamposError {
  const CamposInesperado() : super('Algo deu errado. Tente de novo.');
}
