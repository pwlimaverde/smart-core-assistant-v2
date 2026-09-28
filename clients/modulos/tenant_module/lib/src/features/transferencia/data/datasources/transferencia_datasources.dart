import 'dart:developer' as developer;

import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/transferencia.dart';
import '../../domain/parameters/transferencia_parameters.dart';

RegraDeTransferencia regraDoProto(proto.RegraTransferencia r) =>
    RegraDeTransferencia(
      id: r.id.toInt(),
      nome: r.nome,
      gatilhoTipo: r.gatilhoTipo,
      condicao: r.condicao,
      intencaoTag: r.intencaoTag,
      exemplosSim: List.unmodifiable(r.exemplosSim),
      exemplosNao: List.unmodifiable(r.exemplosNao),
      momento: r.momento,
      camposColeta: List.unmodifiable(r.camposColeta),
      destinoTipo: r.destinoTipo,
      destinoFluxoId: r.destinoFluxoId == 0 ? null : r.destinoFluxoId,
      mensagem: r.mensagem,
      sensibilidade: r.sensibilidade,
      ativa: r.ativa,
      sugestao: r.sugestao,
    );

proto.RegraTransferencia regraParaProto(RegraDeTransferencia r) =>
    proto.RegraTransferencia(
      id: Int64(r.id),
      nome: r.nome.trim(),
      gatilhoTipo: r.gatilhoTipo,
      condicao: r.condicao.trim(),
      intencaoTag: r.intencaoTag,
      exemplosSim: r.exemplosSim,
      exemplosNao: r.exemplosNao,
      momento: r.momento,
      camposColeta: r.camposColeta,
      destinoTipo: r.destinoTipo,
      destinoFluxoId: r.destinoFluxoId ?? 0,
      mensagem: r.mensagem.trim(),
      sensibilidade: r.sensibilidade,
    );

ConfiguracaoDeTransferencia configDoProto(proto.ConfigTransferencia c) =>
    ConfiguracaoDeTransferencia(
      sinais: c.sinais
          .map(
            (s) => SinalAutomatico(
              nome: s.nome,
              ativo: s.ativo,
              sensibilidade: s.sensibilidade.isEmpty
                  ? 'media'
                  : s.sensibilidade,
            ),
          )
          .toList(),
      fluxoPadraoId: c.fluxoPadraoId == 0 ? null : c.fluxoPadraoId,
      msgTransferencia: c.msgTransferencia,
      motorAnalise: c.motorAnalise.isEmpty ? 'llm' : c.motorAnalise,
    );

/// Uma listagem auxiliar que a sessão pode não ter permissão de ler (fluxos
/// pedem `atendimentos:read`, intenções `treinamento:read`): falhar aqui não
/// pode impedir a tela de abrir — o campo correspondente só fica sem opções.
Future<List<T>> _talvez<T>(String o, Future<List<T>> Function() busca) async {
  try {
    return await busca();
  } catch (e) {
    developer.log('$o indisponível: $e', name: 'tenant_module.transferencia');
    return const [];
  }
}

final class CarregarTransferenciaDatasource
    implements Datasource<PainelTransferencia, NoParams> {
  final proto.AdminServiceClient _client;

  const CarregarTransferenciaDatasource({
    required proto.AdminServiceClient client,
  })
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<PainelTransferencia> call(NoParams parameters) async {
    final config = await _client.getMyConfigTransferencia(
      proto.GetMyConfigTransferenciaRequest(),
    );
    final regras = await _client.listMyRegrasTransferencia(
      proto.ListMyRegrasTransferenciaRequest(),
    );
    final transferencias = await _talvez(
      'transferências',
      () async =>
          (await _client.listMyTransferencias(
                proto.ListMyTransferenciasRequest(limite: 30),
              )).transferencias
              .map(
                (t) => TransferenciaFeita(
                  id: t.id.toInt(),
                  atendimentoId: t.atendimentoId,
                  motor: t.motor,
                  motivo: t.motivo,
                  fluxoNome: t.fluxoNome,
                  criadoEm: DateTime.fromMillisecondsSinceEpoch(
                    t.criadoEm.toInt(),
                  ),
                ),
              )
              .toList(),
    );
    final fluxos = await _talvez(
      'fluxos',
      () async => (await _client.listMyFluxos(proto.ListMyFluxosRequest()))
          .fluxos
          .where((f) => f.ativo)
          .map((f) => OpcaoDeFluxo(f.id, f.nome))
          .toList(),
    );
    final intencoes = await _talvez(
      'intenções',
      () async => (await _client.listMyIntents(
        proto.ListMyIntentsRequest(),
      )).intents.map((i) => i.tag).where((t) => t.isNotEmpty).toList(),
    );
    final campos = await _talvez(
      'campos',
      () async => (await _client.listMyCampos(
        proto.ListMyCamposRequest(),
      )).campos.map((c) => OpcaoDeCampo(c.slug, c.nome)).toList(),
    );
    return PainelTransferencia(
      config: configDoProto(config.config),
      regras: regras.regras.map(regraDoProto).toList(),
      transferencias: transferencias,
      fluxos: fluxos,
      intencoes: intencoes,
      campos: campos,
    );
  }
}

final class SalvarRegraDatasource
    implements Datasource<RegraDeTransferencia, SalvarRegraParameters> {
  final proto.AdminServiceClient _client;

  const SalvarRegraDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<RegraDeTransferencia> call(SalvarRegraParameters parameters) async {
    final resp = await _client.salvarMyRegraTransferencia(
      proto.SalvarMyRegraTransferenciaRequest(
        id: Int64(parameters.regra.id),
        regra: regraParaProto(parameters.regra),
      ),
    );
    return regraDoProto(resp.regra);
  }
}

final class DefinirRegraAtivaDatasource
    implements Datasource<RegraDeTransferencia, RegraAtivaParameters> {
  final proto.AdminServiceClient _client;

  const DefinirRegraAtivaDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<RegraDeTransferencia> call(RegraAtivaParameters parameters) async {
    final resp = await _client.setMyRegraTransferenciaAtiva(
      proto.SetMyRegraTransferenciaAtivaRequest(
        id: Int64(parameters.id),
        ativa: parameters.ativa,
        confirmar: parameters.confirmar,
      ),
    );
    return regraDoProto(resp.regra);
  }
}

final class DefinirSinaisDatasource
    implements Datasource<ConfiguracaoDeTransferencia, SinaisParameters> {
  final proto.AdminServiceClient _client;

  const DefinirSinaisDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<ConfiguracaoDeTransferencia> call(SinaisParameters parameters) async {
    final resp = await _client.setMySinaisTransferencia(
      proto.SetMySinaisTransferenciaRequest(
        sinais: parameters.sinais.map(
          (s) => proto.SinalTransferencia(
            nome: s.nome,
            ativo: s.ativo,
            sensibilidade: s.sensibilidade,
          ),
        ),
        alterarFluxoPadrao: parameters.alterarFluxoPadrao,
        fluxoPadraoId: parameters.fluxoPadraoId ?? 0,
      ),
    );
    return configDoProto(resp.config);
  }
}

final class TestarRegraDatasource
    implements Datasource<ResultadoTesteRegra, TestarRegraParameters> {
  final proto.AdminServiceClient _client;

  const TestarRegraDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<ResultadoTesteRegra> call(TestarRegraParameters parameters) async {
    final resp = await _client.testarMyRegraTransferencia(
      proto.TestarMyRegraTransferenciaRequest(
        frase: parameters.frase,
        regra: regraParaProto(parameters.regra),
      ),
    );
    return ResultadoTesteRegra(
      probabilidade: resp.probabilidade,
      limiar: resp.limiar,
      dispararia: resp.dispararia,
      modelo: resp.modelo,
    );
  }
}

final class GerarSugestoesDatasource implements Datasource<int, NoParams> {
  final proto.AdminServiceClient _client;

  const GerarSugestoesDatasource({required proto.AdminServiceClient client})
    // ignore: prefer_initializing_formals
    : _client = client;

  @override
  Future<int> call(NoParams parameters) async {
    final resp = await _client.gerarMySugestoesTransferencia(
      proto.GerarMySugestoesTransferenciaRequest(),
    );
    return resp.criadas;
  }
}
