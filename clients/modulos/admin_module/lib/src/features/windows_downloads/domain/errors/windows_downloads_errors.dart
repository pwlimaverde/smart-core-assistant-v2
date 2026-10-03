import 'package:dependencies_module/dependencies_module.dart';

/// Erro específico: usuário não é superusuário.
class NotSuperuserError extends AppException {
  NotSuperuserError() : super(
    message: 'Apenas administradores podem acessar downloads',
    code: 'auth_access_denied',
    stackTrace: StackTrace.current,
  );
}

/// Erro: canal inválido.
class InvalidChannelError extends AppException {
  InvalidChannelError(String channel) : super(
    message: 'Canal "$channel" inválido. Use "beta".',
    code: 'invalid_argument',
    stackTrace: StackTrace.current,
  );
}

/// Erro: serviço de downloads não configurado.
class ReleasesNotConfiguredError extends AppException {
  ReleasesNotConfiguredError() : super(
    message: 'Serviço de downloads não está configurado',
    code: 'failed_precondition',
    stackTrace: StackTrace.current,
  );
}

/// Erro: nenhuma release encontrada.
class NoReleaseFoundError extends AppException {
  NoReleaseFoundError(String channel) : super(
    message: 'Nenhuma release encontrada para o canal "$channel"',
    code: 'not_found',
    stackTrace: StackTrace.current,
  );
}
