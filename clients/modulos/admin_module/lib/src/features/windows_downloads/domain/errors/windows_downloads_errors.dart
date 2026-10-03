import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da feature `windows_downloads`.
sealed class WindowsDownloadsError extends AppError {
  const WindowsDownloadsError(super.message);
}

final class WindowsDownloadsAcessoNegado extends WindowsDownloadsError
    with UnauthorizedFailure {
  const WindowsDownloadsAcessoNegado()
    : super('Somente o superusuário pode baixar o instalador.');
}

/// Sessão expirada — distinta de falta de permissão (ver `DashboardSessaoExpirada`).
final class WindowsDownloadsSessaoExpirada extends WindowsDownloadsError
    with UnauthorizedFailure {
  const WindowsDownloadsSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class WindowsDownloadsCanalInvalido extends WindowsDownloadsError
    with ValidationFailure {
  const WindowsDownloadsCanalInvalido()
    : super('Canal de release inválido. Nesta versão só existe o canal beta.');
}

/// O control_plane está sem `RELEASES_DOWNLOAD_SECRET`.
final class WindowsDownloadsNaoConfigurado extends WindowsDownloadsError {
  const WindowsDownloadsNaoConfigurado()
    : super(
        'Os downloads do instalador ainda não foram configurados no servidor.',
      );
}

final class WindowsDownloadsSemRelease extends WindowsDownloadsError {
  const WindowsDownloadsSemRelease()
    : super('Nenhum instalador publicado neste canal ainda.');
}

final class WindowsDownloadsIndisponivel extends WindowsDownloadsError
    with NetworkFailure {
  const WindowsDownloadsIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

final class WindowsDownloadsInesperado extends WindowsDownloadsError
    with UnexpectedFailure {
  const WindowsDownloadsInesperado()
    : super('Não foi possível gerar o link de download. Tente novamente.');
}
