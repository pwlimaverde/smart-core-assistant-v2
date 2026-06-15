import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/session.dart';
import '../../domain/parameters/login_parameters.dart';
import '../grpc_error_mapper.dart';
import '../jwt_payload.dart';

/// Datasource gRPC-Web do login: só I/O. Chama `AuthService.Login` e mapeia a
/// resposta para [Session]; falhas viram [AppError] tipado (sem vazar segredo).
final class LoginGrpcDatasource implements Datasource<Session> {
  final AuthServiceClient _client;

  const LoginGrpcDatasource({required this._client});

  @override
  Future<Session> call(covariant LoginParameters parameters) async {
    try {
      final resp = await _client.login(
        LoginRequest(email: parameters.email, password: parameters.password),
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
