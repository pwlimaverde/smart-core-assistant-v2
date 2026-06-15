import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/session.dart';
import '../../domain/parameters/refresh_parameters.dart';
import '../grpc_error_mapper.dart';
import '../jwt_payload.dart';

/// Datasource gRPC-Web do refresh: só I/O. Chama `AuthService.Refresh` e mapeia
/// a resposta rotacionada para [Session].
final class RefreshGrpcDatasource implements Datasource<Session> {
  final AuthServiceClient _client;

  const RefreshGrpcDatasource({required this._client});

  @override
  Future<Session> call(covariant RefreshParameters parameters) async {
    try {
      final resp = await _client.refresh(
        RefreshRequest(refreshToken: parameters.refreshToken),
      );
      return JwtPayload.decode(resp.accessToken).paraSession(
        accessToken: resp.accessToken,
        refreshToken: resp.refreshToken,
      );
    } on GrpcError catch (e) {
      throw mapGrpcError(e, parameters.error);
    } catch (e) {
      throw parameters.error.copyWith(message: '$e');
    }
  }
}
