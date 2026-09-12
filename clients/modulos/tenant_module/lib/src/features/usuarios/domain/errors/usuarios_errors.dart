import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Erros da feature de gestão de usuários do tenant (papéis e permissões de
/// fluxo). As duas operações — listar e atualizar — têm o mesmo repertório.
sealed class TenantUsuariosError extends AppError {
  const TenantUsuariosError(super.message);
}

final class UsuariosAcessoNegado extends TenantUsuariosError
    with UnauthorizedFailure {
  const UsuariosAcessoNegado()
    : super('Você não tem permissão para gerenciar usuários.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [UsuariosAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class UsuariosSessaoExpirada extends TenantUsuariosError
    with UnauthorizedFailure {
  const UsuariosSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class UsuarioNaoEncontrado extends TenantUsuariosError {
  const UsuarioNaoEncontrado() : super('Usuário não encontrado neste tenant.');
}

/// Papel inexistente, permissão de módulo desconhecida ou fluxo que não pertence
/// ao tenant.
final class UsuariosDadosInvalidos extends TenantUsuariosError
    with ValidationFailure {
  const UsuariosDadosInvalidos()
    : super('Verifique o papel e as permissões selecionadas.');
}

final class UsuariosIndisponivel extends TenantUsuariosError
    with NetworkFailure {
  const UsuariosIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class UsuariosInesperado extends TenantUsuariosError
    with UnexpectedFailure {
  const UsuariosInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
