import 'package:dependencies_module/dependencies_module.dart';

import '../model/windows_download_link.dart';
import '../parameters/windows_downloads_parameters.dart';
import '../../../domain/repositories/windows_downloads_repository.dart';

/// Usecase para obter link seguro de download do instalador Windows.
class GetWindowsDownloadLinkUsecase
    implements UseCase<WindowsDownloadLink, GetWindowsDownloadLinkParams> {
  final WindowsDownloadsRepository _repository;

  GetWindowsDownloadLinkUsecase({required WindowsDownloadsRepository repository})
      : _repository = repository;

  @override
  Future<Result<WindowsDownloadLink, AppException>> call(
    GetWindowsDownloadLinkParams params,
  ) async {
    return _repository.getWindowsDownloadLink(
      channel: params.channel,
      version: params.version ?? '',
    );
  }
}
