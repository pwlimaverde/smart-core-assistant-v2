import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da feature de aplicativos conectados (N13.8).
///
/// Um conjunto só para as duas operações: listar e desconectar são o mesmo
/// recurso, do mesmo usuário, com o mesmo repertório de falhas.
sealed class IntegracoesError extends AppError {
  const IntegracoesError(super.message);
}

/// Sessão expirada ou inválida. Não existe "sem permissão" aqui: o recurso é do
/// próprio usuário, então quem está autenticado sempre pode ver e revogar os
/// seus.
final class IntegracoesSessaoInvalida extends IntegracoesError
    with UnauthorizedFailure {
  const IntegracoesSessaoInvalida()
    : super('Sua sessão expirou. Entre novamente.');
}

/// Recusa real de permissão — e NÃO sessão morta.
///
/// Esta família errava ao contrário das demais: mandava [IntegracoesSessaoInvalida]
/// ("sua sessão expirou") também para negação de escopo, dizendo à pessoa para
/// reentrar quando reentrar não resolveria nada.
final class IntegracoesAcessoNegado extends IntegracoesError
    with UnauthorizedFailure {
  const IntegracoesAcessoNegado()
    : super('Você não tem permissão para gerenciar estes aplicativos.');
}

/// O consentimento não existe mais — provavelmente já foi desconectado, aqui ou
/// em outra aba.
final class ConexaoNaoEncontrada extends IntegracoesError {
  const ConexaoNaoEncontrada()
    : super('Este aplicativo já não está conectado.');
}

/// B7 — o ajuste pedia permissão que o aplicativo não tem.
///
/// Dar mais acesso nunca acontece em silêncio: exige reconectar e aprovar na
/// tela de consentimento, onde quem aprova vê o que está concedendo.
final class AmpliarExigeReconectar extends IntegracoesError {
  const AmpliarExigeReconectar()
    : super(
        'Para dar mais permissões, desconecte e conecte o aplicativo de novo.',
      );
}

final class IntegracoesIndisponivel extends IntegracoesError
    with NetworkFailure {
  const IntegracoesIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class IntegracoesInesperado extends IntegracoesError
    with UnexpectedFailure {
  const IntegracoesInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
