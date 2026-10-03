import 'package:return_success_or_error/return_success_or_error.dart';

/// Pede o link de download do instalador Windows.
final class GetWindowsDownloadLinkParameters extends Parameters {
  /// Canal da release. Nesta entrega o servidor só aceita `beta`.
  final String channel;

  /// Versão específica; vazia = a publicada por último no canal.
  final String version;

  const GetWindowsDownloadLinkParameters({
    this.channel = 'beta',
    this.version = '',
  });
}
