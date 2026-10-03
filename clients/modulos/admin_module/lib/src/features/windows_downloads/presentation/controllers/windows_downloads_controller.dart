import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/windows_download_link.dart';
import '../../domain/parameters/windows_downloads_parameters.dart';
import '../../domain/usecases/windows_downloads_usecases.dart';

/// Estado do carregamento do link de download.
enum DownloadLinkState { initial, loading, success, failure }

/// Controller para gerenciar o estado e ações da tela de downloads.
class WindowsDownloadsController extends ValueNotifier<DownloadLinkState> {
  final GetWindowsDownloadLinkUsecase _usecase;

  WindowsDownloadLink? _link;
  AppException? _error;

  WindowsDownloadsController({
    required GetWindowsDownloadLinkUsecase usecase,
  })  : _usecase = usecase,
        super(DownloadLinkState.initial);

  /// Obtém o link de download atual (se houver sucesso).
  WindowsDownloadLink? get link => _link;

  /// Obtém o erro atual (se houver falha).
  AppException? get error => _error;

  /// Requisita um novo link de download.
  Future<void> fetchDownloadLink({
    String channel = 'beta',
    String? version,
  }) async {
    value = DownloadLinkState.loading;

    final params = GetWindowsDownloadLinkParams(
      channel: channel,
      version: version,
    );

    final result = await _usecase(params);

    result.fold(
      (success) {
        _link = success;
        _error = null;
        value = DownloadLinkState.success;
      },
      (failure) {
        _link = null;
        _error = failure;
        value = DownloadLinkState.failure;
      },
    );
  }

  /// Reset do estado.
  void reset() {
    _link = null;
    _error = null;
    value = DownloadLinkState.initial;
  }
}
