import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/windows_downloads_errors.dart';
import '../../domain/model/windows_download_link.dart';
import '../../domain/parameters/windows_downloads_parameters.dart';

/// Traduz a falha gRPC do `GetWindowsDownloadLink` no erro da feature.
///
/// Segue o que a borda devolve (runtime_api `status_do_erro_de_release`):
/// INVALID_ARGUMENT = canal recusado, FAILED_PRECONDITION = segredo não
/// configurado, NOT_FOUND = nada publicado no canal.
WindowsDownloadsError mapearFalhaWindowsDownloads(
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    'getWindowsDownloadLink falhou: $kind',
    name: 'admin_module.windows_downloads',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated => const WindowsDownloadsSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const WindowsDownloadsAcessoNegado(),
    GrpcFailureKind.invalidArgument => const WindowsDownloadsCanalInvalido(),
    GrpcFailureKind.failedPrecondition =>
      const WindowsDownloadsNaoConfigurado(),
    GrpcFailureKind.notFound => const WindowsDownloadsSemRelease(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const WindowsDownloadsIndisponivel(),
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.unknown => const WindowsDownloadsInesperado(),
  };
}

final class GetWindowsDownloadLinkRepository
    extends
        RepositoryBase<
          WindowsDownloadLink,
          GetWindowsDownloadLinkParameters,
          WindowsDownloadsError
        > {
  const GetWindowsDownloadLinkRepository({required super.datasource});

  @override
  WindowsDownloadsError mapError(
    Object exception,
    StackTrace stackTrace,
    GetWindowsDownloadLinkParameters parameters,
  ) => mapearFalhaWindowsDownloads(exception, stackTrace);
}
