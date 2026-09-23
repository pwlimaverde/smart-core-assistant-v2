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

/// P17 — as avaliações do teste ainda não tratadas.
final class ListarAvaliacoesDatasource
    implements Datasource<List<AvaliacaoPendente>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarAvaliacoesDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<AvaliacaoPendente>> call(NoParams parameters) async {
    final resp = await _client.listMyAvaliacoesDeTeste(
      proto.ListMyAvaliacoesDeTesteRequest(limite: 50),
    );
    return [
      for (final a in resp.itens)
        AvaliacaoPendente(
          id: a.id,
          pergunta: a.pergunta,
          respostaBot: a.respostaBot,
          respostaCorrigida: a.respostaCorrigida,
          boa: a.avaliacao == 'boa',
          criadaEm: DateTime.fromMillisecondsSinceEpoch(a.criadaEm.toInt()),
        ),
    ];
  }
}

/// P17 — tira a avaliação da revisão.
final class TratarAvaliacaoDatasource
    implements Datasource<Unit, TratarAvaliacaoParameters> {
  final proto.AdminServiceClient _client;

  const TratarAvaliacaoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Unit> call(TratarAvaliacaoParameters parameters) async {
    await _client.marcarAvaliacaoTratada(
      proto.MarcarAvaliacaoTratadaRequest(
        id: parameters.id,
        virouTreinamento: parameters.virouTreinamento,
      ),
    );
    return unit;
  }
}
