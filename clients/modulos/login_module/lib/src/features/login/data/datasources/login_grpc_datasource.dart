import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/session.dart';
import '../../domain/parameters/login_parameters.dart';
import '../jwt_payload.dart';

/// Datasource gRPC-Web do login: **só I/O** e o mapeamento da resposta.
///
/// Sem `try/catch` — na v3 o datasource é burro e deixa a exceção técnica subir
/// com todo o contexto para o `mapError` do repositório traduzir. Isso inclui a
/// `FormatException` de um `accessToken` malformado: é falha de dados, não de
/// transporte, e o repositório a classifica como inesperada.
final class LoginGrpcDatasource
    implements Datasource<Session, LoginParameters> {
  final AuthServiceClient _client;

  const LoginGrpcDatasource({required this._client});

  @override
  Future<Session> call(LoginParameters parameters) async {
    final resp = await _client.login(
      LoginRequest(email: parameters.email, password: parameters.password),
    );
    return JwtPayload.decode(resp.accessToken).paraSession(
      accessToken: resp.accessToken,
      refreshToken: resp.refreshToken,
    );
  }
}
