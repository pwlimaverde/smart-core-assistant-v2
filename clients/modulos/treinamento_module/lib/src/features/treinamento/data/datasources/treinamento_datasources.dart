import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:http/http.dart' as http;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/treinamento.dart';
import '../../domain/parameters/treinamento_parameters.dart';

/// Datasources do treinamento: I/O gRPC e conversão protobuf → domínio.
/// Burros de propósito — a exceção sobe crua para o `mapError` do repositório.

Treinamento _paraDominio(proto.MyTreinamento t) => Treinamento(
  id: t.id,
  tag: t.tag,
  grupo: t.grupo,
  conteudo: t.conteudo,
  finalizado: t.finalizado,
  vetorizado: t.vetorizado,
  criadoEm: DateTime.fromMillisecondsSinceEpoch(t.criadoEm.toInt()),
  atualizadoEm: DateTime.fromMillisecondsSinceEpoch(t.atualizadoEm.toInt()),
  arquivoNome: t.arquivoNome,
  extracaoStatus: t.extracaoStatus,
  extracaoErro: t.extracaoErro,
);

final class ListarTreinamentosDatasource
    implements Datasource<List<Treinamento>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListarTreinamentosDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<List<Treinamento>> call(NoParams parameters) async {
    final resp = await _client.listMyTreinamentos(
      proto.ListMyTreinamentosRequest(),
    );
    return resp.treinamentos.map(_paraDominio).toList();
  }
}

final class CriarTreinamentoDatasource
    implements Datasource<Treinamento, CriarTreinamentoParameters> {
  final proto.AdminServiceClient _client;

  const CriarTreinamentoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Treinamento> call(CriarTreinamentoParameters parameters) async {
    final resp = await _client.createMyTreinamento(
      proto.CreateMyTreinamentoRequest(
        tag: parameters.tag,
        grupo: parameters.grupo,
        conteudo: parameters.conteudo,
      ),
    );
    return _paraDominio(resp.treinamento);
  }
}

final class ObterTreinamentoDatasource
    implements Datasource<Treinamento, TreinamentoIdParameters> {
  final proto.AdminServiceClient _client;

  const ObterTreinamentoDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<Treinamento> call(TreinamentoIdParameters parameters) async {
    final resp = await _client.getMyTreinamento(
      proto.GetMyTreinamentoRequest(id: parameters.id),
    );
    return _paraDominio(resp.treinamento);
  }
}

final class FinalizarTreinamentoDatasource
    implements Datasource<Unit, FinalizarTreinamentoParameters> {
  final proto.AdminServiceClient _client;

  const FinalizarTreinamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(FinalizarTreinamentoParameters parameters) async {
    await _client.finalizarMyTreinamento(
      proto.FinalizarMyTreinamentoRequest(
        id: parameters.id,
        conteudo: parameters.conteudo,
      ),
    );
    return unit;
  }
}

final class RemoverTreinamentoDatasource
    implements Datasource<Unit, TreinamentoIdParameters> {
  final proto.AdminServiceClient _client;

  const RemoverTreinamentoDatasource({
    required proto.AdminServiceClient client,
    // ignore: prefer_initializing_formals
  }) : _client = client;

  @override
  Future<Unit> call(TreinamentoIdParameters parameters) async {
    await _client.removerMyTreinamento(
      proto.RemoverMyTreinamentoRequest(id: parameters.id),
    );
    return unit;
  }
}

/// O PUT no bucket não terminou. Sem a URL na mensagem: é credencial de escrita.
final class FalhaEnvioArquivo implements Exception {
  final String mensagem;

  const FalhaEnvioArquivo(this.mensagem);

  @override
  String toString() => 'FalhaEnvioArquivo: $mensagem';
}

/// B9 (N10 E5) — envia um arquivo de treinamento em três passos.
///
/// 1. O servidor confere formato, tamanho e quota e diz onde subir;
/// 2. o arquivo vai direto ao bucket — o binário não passa pelo gRPC;
/// 3. o servidor confere o conteúdo real e cria o treinamento, com a leitura
///    do texto pendente.
final class EnviarArquivoTreinamentoDatasource
    implements Datasource<Treinamento, EnviarArquivoTreinamentoParameters> {
  final proto.AdminServiceClient _client;
  final http.Client _http;

  EnviarArquivoTreinamentoDatasource({
    required proto.AdminServiceClient client,
    http.Client? httpClient,
  }) : _client = client, // ignore: prefer_initializing_formals
       _http = httpClient ?? http.Client();

  @override
  Future<Treinamento> call(
    EnviarArquivoTreinamentoParameters parameters,
  ) async {
    final autorizacao = await _client.solicitarUploadTreinamento(
      proto.SolicitarUploadTreinamentoRequest(
        nomeArquivo: parameters.nomeArquivo,
        mimetype: parameters.mimetype,
        bytes: Int64(parameters.bytes.length),
      ),
    );

    // O `Content-Type` tem de ser exatamente o assinado: divergir faz o R2
    // responder 403 sem explicar.
    final resposta = await _http.put(
      Uri.parse(autorizacao.urlUpload),
      headers: {'Content-Type': autorizacao.contentType},
      body: parameters.bytes,
    );
    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw FalhaEnvioArquivo(
        'o envio do arquivo falhou (HTTP ${resposta.statusCode})',
      );
    }

    final criado = await _client.createMyTreinamentoComArquivo(
      proto.CreateMyTreinamentoComArquivoRequest(
        tag: parameters.tag,
        grupo: parameters.grupo,
        chave: autorizacao.chave,
        nomeArquivo: parameters.nomeArquivo,
        mimetype: parameters.mimetype,
      ),
    );
    return _paraDominio(criado.treinamento);
  }
}
