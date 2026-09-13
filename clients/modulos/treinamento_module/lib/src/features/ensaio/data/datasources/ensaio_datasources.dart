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
          .map((t) => TrechoUsado(conteudo: t.conteudo, distancia: t.distancia))
          .toList(),
      confiabilidade: resp.confiabilidade,
      transferiria: resp.transferiria,
      fluxoTransferencia: resp.fluxoTransferencia,
    );
  }
}

/// B9 (N10 E6) — envia a avaliação e devolve o id gravado.
final class RegistrarFeedbackTesteDatasource
    implements Datasource<int, RegistrarFeedbackTesteParameters> {
  final proto.AdminServiceClient _client;

  const RegistrarFeedbackTesteDatasource({
    required proto.AdminServiceClient client,
  })
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<int> call(RegistrarFeedbackTesteParameters parameters) async {
    final resp = await _client.registrarFeedbackTeste(
      proto.RegistrarFeedbackTesteRequest(
        pergunta: parameters.pergunta,
        respostaObtida: parameters.respostaObtida,
        respostaCorreta: parameters.respostaCorreta,
        avaliacao: parameters.boa ? 'boa' : 'ruim',
        comportamentoAplicado: parameters.comportamentoAplicado,
        confiabilidade: parameters.confiabilidade,
      ),
    );
    return resp.id;
  }
}
