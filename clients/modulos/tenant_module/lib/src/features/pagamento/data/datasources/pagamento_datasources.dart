import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/quitacao.dart';
import '../../domain/parameters/pagamento_parameters.dart';

/// Datasource da quitação: I/O gRPC e conversão protobuf → domínio.
///
/// Burro por contrato (sem `try/catch`): a exceção sobe crua para o `mapError`
/// do repositório.
final class QuitarAssinaturaDatasource
    implements Datasource<Quitacao, QuitarAssinaturaParameters> {
  final proto.AdminServiceClient _client;

  const QuitarAssinaturaDatasource({required this._client});

  @override
  Future<Quitacao> call(QuitarAssinaturaParameters parameters) async {
    final resp = await _client.quitarMinhaAssinatura(
      proto.QuitarMinhaAssinaturaRequest(
        provedor: parameters.provedor,
        credencial: parameters.credencial,
      ),
    );
    return Quitacao(
      confirmado: resp.confirmado,
      assinaturaStatus: resp.assinaturaStatus,
      urlExterna: resp.urlExterna,
      motivo: resp.motivo,
      erroLegivel: resp.erroLegivel,
    );
  }
}
