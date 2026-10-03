import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/windows_downloads_controller.dart';
import '../pages/windows_downloads_page.dart';
import '../../domain/usecases/windows_downloads_usecases.dart';

/// Rota para a feature de downloads do Windows.
final class WindowsDownloadsRoute extends GetItModule {
  @override
  String get path => '/admin/windows-downloads';

  @override
  Widget get page => const WindowsDownloadsPage();

  @override
  void binds(Injector i) {
    i.controller<WindowsDownloadsController>(
      () => WindowsDownloadsController(
        usecase: inject<GetWindowsDownloadLinkUsecase>(),
      ),
    );
  }
}
