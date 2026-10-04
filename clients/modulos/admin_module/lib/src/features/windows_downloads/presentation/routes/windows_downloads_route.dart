import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/windows_downloads_usecases.dart';
import '../controllers/windows_downloads_controller.dart';
import '../pages/windows_downloads_page.dart';

final class WindowsDownloadsRoute extends GetItModule {
  @override
  String get path => '/windows-downloads';

  @override
  Widget get page => const WindowsDownloadsPage();

  @override
  void binds(Injector i) {
    i.controller<WindowsDownloadsController>(
      () => WindowsDownloadsController(
        getLinkUsecase: inject<GetWindowsDownloadLinkUsecase>(),
      ),
    );
  }
}
