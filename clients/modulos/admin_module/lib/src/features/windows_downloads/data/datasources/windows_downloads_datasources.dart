import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/windows_download_link.dart';
import '../../domain/parameters/windows_downloads_parameters.dart';

/// Datasource burro: I/O gRPC e conversão protobuf → domínio. Sem `try/catch` —
/// a exceção sobe crua para o `mapError` do repositório.
final class GetWindowsDownloadLinkDatasource
    implements
        Datasource<WindowsDownloadLink, GetWindowsDownloadLinkParameters> {
  final proto.AdminServiceClient _client;

  const GetWindowsDownloadLinkDatasource({required this._client});

  @override
  Future<WindowsDownloadLink> call(
    GetWindowsDownloadLinkParameters parameters,
  ) async {
    final resp = await _client.getWindowsDownloadLink(
      proto.GetWindowsDownloadLinkRequest(
        channel: parameters.channel,
        version: parameters.version,
      ),
    );
    return WindowsDownloadLink(
      url: resp.url,
      version: resp.version,
      fileName: resp.fileName,
      sizeBytes: resp.sizeBytes.toInt(),
      sha256: resp.sha256,
      releaseNotesMd: resp.releaseNotesMd,
      expiresAtMs: resp.expiresAtMs.toInt(),
    );
  }
}
