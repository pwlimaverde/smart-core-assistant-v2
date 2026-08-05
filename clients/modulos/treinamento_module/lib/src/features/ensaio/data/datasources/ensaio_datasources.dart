import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/ensaio.dart';
import '../../domain/parameters/ensaio_parameters.dart';

final class TestarPerguntaDatasource
    implements Datasource<Ensaio, TestarPerguntaParameters> {
  final proto.AdminServiceClient _client;

  const TestarPerguntaDatasource({required proto.AdminServiceClient client})
      // ignore: prefer_initializing_formals
      : _client = client;

  @override
  Future<Ensaio> call(TestarPerguntaParameters parameters) async {
    final resp = await _client.testarPergunta(
      proto.TestarPerguntaRequest(pergunta: parameters.pergunta),
    );
    return Ensaio(
      resposta: resp.resposta,
      comportamentoAplicado: resp.comportamentoAplicado,
      trechos: resp.trechos
          .map(
            (t) => TrechoUsado(conteudo: t.conteudo, distancia: t.distancia),
          )
          .toList(),
      confiabilidade: resp.confiabilidade,
      transferiria: resp.transferiria,
      fluxoTransferencia: resp.fluxoTransferencia,
    );
  }
}
