import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `usuarios` (gestão global, D7).
///
/// Um conjunto para a feature inteira: listar e bloquear são operações sobre o
/// mesmo recurso e têm o mesmo repertório de falha.
sealed class UsuariosError extends AppError {
  const UsuariosError(super.message);
}

final class UsuariosAcessoNegado extends UsuariosError
    with UnauthorizedFailure {
  const UsuariosAcessoNegado()
    : super('Somente o superusuário pode administrar usuários.');
}

final class UsuariosNaoEncontrado extends UsuariosError {
  const UsuariosNaoEncontrado() : super('Usuário não encontrado.');
}

/// Cobre a recusa do servidor a bloquear o próprio acesso.
///
/// Chega como `invalid_argument` com a mensagem do servidor; a tela mostra o
/// texto que veio, e não este padrão, quando houver um.
final class UsuariosDadosInvalidos extends UsuariosError
    with ValidationFailure {
  const UsuariosDadosInvalidos([String? mensagem])
    : super(mensagem ?? 'Não foi possível concluir: verifique os dados.');
}

final class UsuariosIndisponivel extends UsuariosError with NetworkFailure {
  const UsuariosIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class UsuariosInesperado extends UsuariosError with UnexpectedFailure {
  const UsuariosInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
