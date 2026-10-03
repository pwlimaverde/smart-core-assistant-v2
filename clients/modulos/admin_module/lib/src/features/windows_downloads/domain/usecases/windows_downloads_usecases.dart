import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/windows_downloads_errors.dart';
import '../model/windows_download_link.dart';
import '../parameters/windows_downloads_parameters.dart';

/// Pede o link de download do instalador Windows.
///
/// A regra (superusuário, canal, versão, assinatura) vive no servidor; o
/// `process` só recusa um link vazio ou que já chegou vencido — relógios muito
/// distantes entre servidor e navegador levariam o botão a um 401.
final class GetWindowsDownloadLinkUsecase
    extends
        UsecaseBaseCallData<
          WindowsDownloadLink,
          WindowsDownloadLink,
          GetWindowsDownloadLinkParameters,
          WindowsDownloadsError
        > {
  const GetWindowsDownloadLinkUsecase({required super.repository});

  @override
  ProcessData<
    WindowsDownloadLink,
    WindowsDownloadLink,
    GetWindowsDownloadLinkParameters,
    WindowsDownloadsError
  >
  get process => _process;

  @override
  WindowsDownloadsError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log(
      'process de getWindowsDownloadLink quebrou',
      name: 'admin_module.windows_downloads',
      error: exception,
      stackTrace: stackTrace,
    );
    return const WindowsDownloadsInesperado();
  }

  static ReturnSuccessOrError<WindowsDownloadLink, WindowsDownloadsError>
  _process(
    WindowsDownloadLink data,
    GetWindowsDownloadLinkParameters parameters,
  ) => data.url.isEmpty || !data.validoEm()
      ? const Failure(WindowsDownloadsInesperado())
      : Success(data);
}
