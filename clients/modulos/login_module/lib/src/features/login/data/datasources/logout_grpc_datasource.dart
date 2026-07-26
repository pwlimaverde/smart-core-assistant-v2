import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/logout_parameters.dart';

/// Datasource gRPC-Web do logout: só I/O. O access token vai no metadata pelo
/// interceptor; o refresh (quando existe) revoga a família inteira no servidor.
final class LogoutGrpcDatasource implements Datasource<Unit, LogoutParameters> {
  final AuthServiceClient _client;

  const LogoutGrpcDatasource({required this._client});

  @override
  Future<Unit> call(LogoutParameters parameters) async {
    await _client.logout(
      LogoutRequest(refreshToken: parameters.refreshToken ?? ''),
    );
    return unit;
  }
}
