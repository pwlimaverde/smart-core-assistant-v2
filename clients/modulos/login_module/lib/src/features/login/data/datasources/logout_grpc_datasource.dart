import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/logout_parameters.dart';
import '../grpc_error_mapper.dart';

/// Datasource gRPC-Web do logout: só I/O. Chama `AuthService.Logout` (o access
/// token vai no metadata via interceptor) e devolve [Unit] em sucesso.
final class LogoutGrpcDatasource implements Datasource<Unit> {
  final AuthServiceClient _client;

  const LogoutGrpcDatasource({required this._client});

  @override
  Future<Unit> call(covariant LogoutParameters parameters) async {
    try {
      await _client.logout(
        LogoutRequest(refreshToken: parameters.refreshToken ?? ''),
      );
      return unit;
    } on GrpcError catch (e) {
      throw mapGrpcError(e, parameters.error);
    } catch (e) {
      throw parameters.error.copyWith(message: '$e');
    }
  }
}
