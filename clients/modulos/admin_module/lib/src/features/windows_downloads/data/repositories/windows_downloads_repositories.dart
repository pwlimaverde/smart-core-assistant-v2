import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/windows_download_link.dart';
import '../../domain/repositories/windows_downloads_repository.dart';
import '../datasources/windows_downloads_datasources.dart';

/// Implementação do repositório para operações de download do Windows.
class GetWindowsDownloadLinkRepository implements WindowsDownloadsRepository {
  final GetWindowsDownloadLinkDatasource _datasource;

  GetWindowsDownloadLinkRepository({
    required GetWindowsDownloadLinkDatasource datasource,
  }) : _datasource = datasource;

  @override
  Future<Result<WindowsDownloadLink, AppException>> getWindowsDownloadLink({
    required String channel,
    required String version,
  }) {
    return _datasource.call(channel: channel, version: version);
  }
}
