import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../domain/versao_do_app.dart';

final class ConsultarVersaoDatasource
    implements Datasource<VersaoPublicada, ConsultarVersaoParameters> {
  final proto.AdminServiceClient _client;

  const ConsultarVersaoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<VersaoPublicada> call(ConsultarVersaoParameters parameters) async {
    final resp = await _client.getVersaoDoApp(
      proto.GetVersaoDoAppRequest(plataforma: parameters.plataforma),
    );
    return VersaoPublicada(
      build: resp.buildAtual.toInt(),
      urlDownload: resp.urlDownload,
      notas: resp.notas,
    );
  }
}

/// Qualquer falha vira [VersaoIndisponivel]: não há o que o usuário faça com
/// o motivo, e o aviso simplesmente não aparece.
final class ConsultarVersaoRepository
    extends
        RepositoryBase<
          VersaoPublicada,
          ConsultarVersaoParameters,
          VersaoIndisponivel
        > {
  const ConsultarVersaoRepository({required super.datasource});

  @override
  VersaoIndisponivel mapError(
    Object e,
    StackTrace s,
    ConsultarVersaoParameters p,
  ) => const VersaoIndisponivel();
}
