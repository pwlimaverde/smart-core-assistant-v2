import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da feature de convites.
///
/// **Dois conjuntos, não quatro:** `createInvite`, `listInvites` e
/// `revokeInvite` compartilham o mesmo repertório (são operações do admin do
/// tenant, autenticadas, sobre o mesmo recurso), então dividem [ConvitesError].
/// `acceptInvite` tem conjunto próprio: é a **única rota pública** do módulo — o
/// convidado ainda não tem conta —, e nela "acesso negado" não existe, enquanto
/// "convite expirado" e "usuário já existe" existem.
sealed class ConvitesError extends AppError {
  const ConvitesError(super.message);
}

/// Sem permissão de administrar o tenant (escopo `tenant:admin`).
final class ConvitesAcessoNegado extends ConvitesError
    with UnauthorizedFailure {
  const ConvitesAcessoNegado()
    : super('Você não tem permissão para gerenciar convites.');
}

/// O convite não existe ou já foi consumido/revogado.
final class ConviteNaoEncontrado extends ConvitesError {
  const ConviteNaoEncontrado() : super('Convite não encontrado.');
}

/// Já existe convite pendente (ou usuário) para aquele e-mail.
final class EmailJaConvidado extends ConvitesError {
  const EmailJaConvidado()
    : super('Já existe um convite pendente para este e-mail.');
}

/// Dados do convite recusados pelo servidor (e-mail inválido, papel
/// inexistente, permissão de fluxo desconhecida).
final class ConvitesDadosInvalidos extends ConvitesError
    with ValidationFailure {
  const ConvitesDadosInvalidos() : super('Verifique os dados do convite.');
}

final class ConvitesIndisponivel extends ConvitesError with NetworkFailure {
  const ConvitesIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class ConvitesInesperado extends ConvitesError with UnexpectedFailure {
  const ConvitesInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}

// ─── aceite do convite (rota pública) ─────────────────────────────────────────

/// Erros de `acceptInvite`.
sealed class AcceptInviteError extends AppError {
  const AcceptInviteError(super.message);
}

/// Token inexistente, expirado, revogado ou já usado.
///
/// Os quatro casos são um só de propósito: distinguir "expirado" de "não existe"
/// diria a quem tem o link se aquele convite algum dia foi válido.
final class ConviteInvalidoOuExpirado extends AcceptInviteError {
  const ConviteInvalidoOuExpirado()
    : super('Este convite não é mais válido. Peça um novo ao administrador.');
}

/// O e-mail ou nome de usuário escolhido já está em uso.
final class UsuarioJaExiste extends AcceptInviteError {
  const UsuarioJaExiste()
    : super('Já existe uma conta com este e-mail ou nome de usuário.');
}

/// Dados do cadastro recusados (senha fraca, e-mail malformado).
final class AcceptDadosInvalidos extends AcceptInviteError
    with ValidationFailure {
  const AcceptDadosInvalidos() : super('Verifique os dados informados.');
}

final class AcceptIndisponivel extends AcceptInviteError with NetworkFailure {
  const AcceptIndisponivel() : super('Servidor indisponível. Tente novamente.');
}

final class AcceptInesperado extends AcceptInviteError with UnexpectedFailure {
  const AcceptInesperado()
    : super('Não foi possível concluir o cadastro. Tente novamente.');
}
