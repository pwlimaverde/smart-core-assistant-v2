import 'package:dependencies_module/dependencies_module.dart';

import '../model/windows_download_link.dart';

/// Contrato do repositório para operações de download do Windows.
abstract class WindowsDownloadsRepository {
  /// Obtém um link seguro para download do instalador Windows.
  ///
  /// Retorna um [WindowsDownloadLink] contendo:
  /// - URL com ticket de segurança (válido por 5 minutos)
  /// - Versão, nome do arquivo, tamanho e SHA-256
  /// - Release notes em Markdown
  /// - Data de expiração do ticket
  Future<Result<WindowsDownloadLink, AppException>> getWindowsDownloadLink({
    required String channel,
    required String version,
  });
}
