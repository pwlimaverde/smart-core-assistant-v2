import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/get_thread_parameters.dart';
import '../../domain/parameters/list_atendimentos_parameters.dart';
import '../../domain/parameters/move_atendimento_etapa_parameters.dart';
import '../../domain/model/ficha.dart';
import '../../domain/model/quadro.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/quadro_parameters.dart';
import '../../domain/parameters/send_outbound_message_parameters.dart';

/// Os quatro `Datasource` da feature: adaptadores finos entre o `Parameters` de
/// uma operação e o [AtendimentoGateway] da plataforma ativa.
///
/// Ficam juntos num arquivo porque são a **mesma costura** repetida quatro vezes
/// — separá-los em quatro arquivos de dez linhas só espalharia a leitura. Cada um
/// é burro: nenhum `try/catch`, nenhuma regra; a exceção do gateway sobe para o
/// `mapError` do repositório correspondente.

/// Fila de atendimentos (Kanban).
final class ListAtendimentosDatasource
    implements Datasource<List<AtendimentoResumo>, ListAtendimentosParameters> {
  final AtendimentoGateway _gateway;

  const ListAtendimentosDatasource({required this._gateway});

  @override
  Future<List<AtendimentoResumo>> call(ListAtendimentosParameters parameters) =>
      _gateway.listAtendimentos(
        status: parameters.status,
        departamentoId: parameters.departamentoId,
        limit: parameters.limit,
      );
}

/// Histórico de mensagens de um atendimento.
final class GetThreadDatasource
    implements Datasource<List<MensagemThread>, GetThreadParameters> {
  final AtendimentoGateway _gateway;

  const GetThreadDatasource({required this._gateway});

  @override
  Future<List<MensagemThread>> call(GetThreadParameters parameters) =>
      _gateway.getThread(
        atendimentoId: parameters.atendimentoId,
        limit: parameters.limit,
        offset: parameters.offset,
      );
}

/// Movimento de etapa no Kanban. Devolve [Unit]: o gateway não produz dado, e
/// `Unit` é como a lib representa "concluiu, sem valor".
final class MoveAtendimentoEtapaDatasource
    implements Datasource<Unit, MoveAtendimentoEtapaParameters> {
  final AtendimentoGateway _gateway;

  const MoveAtendimentoEtapaDatasource({required this._gateway});

  @override
  Future<Unit> call(MoveAtendimentoEtapaParameters parameters) async {
    await _gateway.moveAtendimentoEtapa(
      atendimentoId: parameters.atendimentoId,
      etapaDestinoId: parameters.etapaDestinoId,
      motivo: parameters.motivo,
    );
    return unit;
  }
}

/// Envio de mensagem do atendente; devolve o id persistido (no desktop, um id
/// negativo provisório até o sync promover ao definitivo).
final class SendOutboundMessageDatasource
    implements Datasource<int, SendOutboundMessageParameters> {
  final AtendimentoGateway _gateway;

  const SendOutboundMessageDatasource({required this._gateway});

  @override
  Future<int> call(SendOutboundMessageParameters parameters) =>
      // `conteudo` é PII: não é logado aqui nem em nenhuma camada acima.
      _gateway.sendOutboundMessage(
        atendimentoId: parameters.atendimentoId,
        conteudo: parameters.conteudo,
        tipo: parameters.tipo,
      );
}

/// Quadros que o atendente pode abrir.
final class ListFluxosDatasource
    implements Datasource<List<FluxoDoQuadro>, NoParams> {
  final AtendimentoGateway _gateway;

  const ListFluxosDatasource({required this._gateway});

  @override
  Future<List<FluxoDoQuadro>> call(NoParams parameters) =>
      _gateway.listFluxos();
}

/// Colunas de um quadro.
final class ListColunasDatasource
    implements Datasource<List<ColunaDoQuadro>, ListColunasParameters> {
  final AtendimentoGateway _gateway;

  const ListColunasDatasource({required this._gateway});

  @override
  Future<List<ColunaDoQuadro>> call(ListColunasParameters parameters) =>
      _gateway.listColunas(parameters.fluxoId);
}

/// Estado do atendimento; o cartão acompanha, do lado do servidor.
final class SetAtendimentoStatusDatasource
    implements Datasource<Unit, SetAtendimentoStatusParameters> {
  final AtendimentoGateway _gateway;

  const SetAtendimentoStatusDatasource({required this._gateway});

  @override
  Future<Unit> call(SetAtendimentoStatusParameters parameters) async {
    await _gateway.setAtendimentoStatus(
      atendimentoId: parameters.atendimentoId,
      status: parameters.status,
      motivo: parameters.motivo,
    );
    return unit;
  }
}

/// A ficha do atendimento (etiquetas e notas).
final class GetFichaDatasource
    implements Datasource<FichaAtendimento, AtendimentoIdParameters> {
  final AtendimentoGateway _gateway;

  const GetFichaDatasource({required this._gateway});

  @override
  Future<FichaAtendimento> call(AtendimentoIdParameters parameters) =>
      _gateway.getFicha(parameters.atendimentoId);
}

final class CriarEtiquetaDatasource
    implements Datasource<Unit, CriarEtiquetaParameters> {
  final AtendimentoGateway _gateway;

  const CriarEtiquetaDatasource({required this._gateway});

  @override
  Future<Unit> call(CriarEtiquetaParameters parameters) async {
    await _gateway.criarEtiqueta(nome: parameters.nome, cor: parameters.cor);
    return unit;
  }
}

final class AlternarEtiquetaDatasource
    implements Datasource<Unit, AlternarEtiquetaParameters> {
  final AtendimentoGateway _gateway;

  const AlternarEtiquetaDatasource({required this._gateway});

  @override
  Future<Unit> call(AlternarEtiquetaParameters parameters) async {
    await _gateway.alternarEtiqueta(
      atendimentoId: parameters.atendimentoId,
      etiquetaId: parameters.etiquetaId,
      aplicar: parameters.aplicar,
    );
    return unit;
  }
}

final class CriarNotaDatasource implements Datasource<Unit, CriarNotaParameters> {
  final AtendimentoGateway _gateway;

  const CriarNotaDatasource({required this._gateway});

  @override
  Future<Unit> call(CriarNotaParameters parameters) async {
    await _gateway.criarNota(
      atendimentoId: parameters.atendimentoId,
      texto: parameters.texto,
    );
    return unit;
  }
}
