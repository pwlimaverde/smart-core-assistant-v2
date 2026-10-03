import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/windows_download_link.dart';
import '../../domain/parameters/windows_downloads_parameters.dart';
import '../../domain/usecases/windows_downloads_usecases.dart';

final class WindowsDownloadsController
    extends BaseController<WindowsDownloadLink> {
  final GetWindowsDownloadLinkUsecase _getLinkUsecase;

  WindowsDownloadsController({required this._getLinkUsecase});

  /// Gera um link novo (cada pedido emite um ticket de 5 minutos).
  Future<void> gerarLink() =>
      execute(() => _getLinkUsecase(const GetWindowsDownloadLinkParameters()));
}
