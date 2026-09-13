import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/recuperacao_parameters.dart';

/// Datasources da recuperação de senha: só I/O, sem `try/catch` — a exceção
/// sobe crua para o `mapError` do repositório.

final class SolicitarRedefinicaoDatasource
    implements Datasource<Unit, SolicitarRedefinicaoParameters> {
  final AuthServiceClient _client;

  const SolicitarRedefinicaoDatasource({required this._client});

  @override
  Future<Unit> call(SolicitarRedefinicaoParameters parameters) async {
    // A resposta não diz nada sobre a conta — por isso não há o que ler dela.
    await _client.solicitarRedefinicaoSenha(
      SolicitarRedefinicaoSenhaRequest(login: parameters.login),
    );
    return unit;
  }
}

final class RedefinirSenhaDatasource
    implements Datasource<Unit, RedefinirSenhaParameters> {
  final AuthServiceClient _client;

  const RedefinirSenhaDatasource({required this._client});

  @override
  Future<Unit> call(RedefinirSenhaParameters parameters) async {
    await _client.redefinirSenha(
      RedefinirSenhaRequest(
        token: parameters.token,
        novaSenha: parameters.novaSenha,
      ),
    );
    return unit;
  }
}
