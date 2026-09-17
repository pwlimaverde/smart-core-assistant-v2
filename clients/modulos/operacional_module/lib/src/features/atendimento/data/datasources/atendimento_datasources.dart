import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/definir_valor_campo_parameters.dart';
import '../../domain/parameters/iniciar_atendimento_parameters.dart';
import '../../domain/model/atendimento_iniciado.dart';
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
import '../../domain/model/midia_mensagem.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/parameters/quadro_operacao_parameters.dart';
import '../../domain/model/evento_timeline.dart';

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
        busca: parameters.busca,
        somenteMeus: parameters.somenteMeus,
        somenteNaoLidos: parameters.somenteNaoLidos,
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
        beforeId: parameters.beforeId,
      );
}

/// Movimento de etapa no Kanban. Devolve [Unit]: o gateway não produz dado, e
/// `Unit` é como a lib representa "concluiu, sem valor".
/// C3 — abre um atendimento a partir de um cliente já cadastrado.
final class IniciarAtendimentoDatasource
    implements Datasource<AtendimentoIniciado, IniciarAtendimentoParameters> {
  final AtendimentoGateway _gateway;

  const IniciarAtendimentoDatasource({required this._gateway});

  @override
  Future<AtendimentoIniciado> call(
    IniciarAtendimentoParameters parameters,
  ) async {
    return _gateway.iniciarAtendimento(
      contatoId: parameters.contatoId,
      fluxoId: parameters.fluxoId,
      etapaInicialId: parameters.etapaInicialId,
      departamentoId: parameters.departamentoId,
      assunto: parameters.assunto,
    );
  }
}

/// N9 E13 — preenche um campo do cartão nesta conversa.
final class DefinirValorCampoDatasource
    implements Datasource<Unit, DefinirValorCampoParameters> {
  final AtendimentoGateway _gateway;

  const DefinirValorCampoDatasource({required this._gateway});

  @override
  Future<Unit> call(DefinirValorCampoParameters parameters) async {
    await _gateway.definirValorCampo(
      atendimentoId: parameters.atendimentoId,
      campoId: parameters.campoId,
      valorJson: parameters.valorJson,
    );
    return unit;
  }
}

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
        mensagemCitadaId: parameters.mensagemCitadaId,
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

final class DefinirBotDaConversaDatasource
    implements Datasource<Unit, DefinirBotDaConversaParameters> {
  final AtendimentoGateway _gateway;

  const DefinirBotDaConversaDatasource({required this._gateway});

  @override
  Future<Unit> call(DefinirBotDaConversaParameters parameters) async {
    await _gateway.definirBotDaConversa(
      atendimentoId: parameters.atendimentoId,
      habilitado: parameters.habilitado,
    );
    return unit;
  }
}

final class MarcarAtendimentoLidoDatasource
    implements Datasource<int, MarcarAtendimentoLidoParameters> {
  final AtendimentoGateway _gateway;

  const MarcarAtendimentoLidoDatasource({required this._gateway});

  @override
  Future<int> call(MarcarAtendimentoLidoParameters parameters) =>
      _gateway.marcarAtendimentoLido(parameters.atendimentoId);
}

final class CriarNotaDatasource
    implements Datasource<Unit, CriarNotaParameters> {
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

/// P3 — avisa o contato que o atendente está digitando/gravando.
final class EnviarPresencaDatasource
    implements Datasource<bool, EnviarPresencaParameters> {
  final AtendimentoGateway _gateway;

  const EnviarPresencaDatasource({required this._gateway});

  @override
  Future<bool> call(EnviarPresencaParameters parameters) =>
      _gateway.enviarPresenca(
        atendimentoId: parameters.atendimentoId,
        situacao: parameters.situacao,
      );
}

/// P3 — os arquivos trocados na conversa (galeria).
final class ListarMidiasDatasource
    implements Datasource<List<MidiaMensagem>, ListarMidiasParameters> {
  final AtendimentoGateway _gateway;

  const ListarMidiasDatasource({required this._gateway});

  @override
  Future<List<MidiaMensagem>> call(ListarMidiasParameters parameters) =>
      _gateway.listarMidias(
        atendimentoId: parameters.atendimentoId,
        limit: parameters.limit,
        offset: parameters.offset,
      );
}

/// P3 — sobe o anexo e o põe na conversa. Devolve o id da mensagem criada.
final class EnviarMidiaDatasource
    implements Datasource<int, EnviarMidiaParameters> {
  final AtendimentoGateway _gateway;

  const EnviarMidiaDatasource({required this._gateway});

  @override
  Future<int> call(EnviarMidiaParameters parameters) => _gateway.enviarMidia(
    atendimentoId: parameters.atendimentoId,
    nomeArquivo: parameters.nomeArquivo,
    mimetype: parameters.mimetype,
    bytes: parameters.bytes,
    legenda: parameters.legenda,
    ehPtt: parameters.ehPtt,
  );
}

/// P4 — dono da conversa.
final class AtribuirAtendimentoDatasource
    implements Datasource<bool, AtribuirAtendimentoParameters> {
  final AtendimentoGateway _gateway;

  const AtribuirAtendimentoDatasource({required this._gateway});

  @override
  Future<bool> call(AtribuirAtendimentoParameters parameters) =>
      _gateway.atribuirAtendimento(
        atendimentoId: parameters.atendimentoId,
        atendenteId: parameters.atendenteId,
        devolverParaFila: parameters.devolverParaFila,
      );
}

/// P4 — urgência do cartão.
final class DefinirPrioridadeDatasource
    implements Datasource<Unit, DefinirPrioridadeParameters> {
  final AtendimentoGateway _gateway;

  const DefinirPrioridadeDatasource({required this._gateway});

  @override
  Future<Unit> call(DefinirPrioridadeParameters parameters) async {
    await _gateway.definirPrioridade(
      atendimentoId: parameters.atendimentoId,
      prioridade: parameters.prioridade,
    );
    return unit;
  }
}

/// P4 — transferência de fluxo. Devolve o nome do fluxo de destino.
final class TransferirParaFluxoDatasource
    implements Datasource<String, TransferirParaFluxoParameters> {
  final AtendimentoGateway _gateway;

  const TransferirParaFluxoDatasource({required this._gateway});

  @override
  Future<String> call(TransferirParaFluxoParameters parameters) =>
      _gateway.transferirParaFluxo(
        atendimentoId: parameters.atendimentoId,
        fluxoId: parameters.fluxoId,
      );
}

/// P4 — o quadro em CSV.
final class ExportarQuadroDatasource
    implements Datasource<List<int>, ExportarQuadroParameters> {
  final AtendimentoGateway _gateway;

  const ExportarQuadroDatasource({required this._gateway});

  @override
  Future<List<int>> call(ExportarQuadroParameters parameters) =>
      _gateway.exportarQuadro(
        status: parameters.status,
        departamentoId: parameters.departamentoId,
        busca: parameters.busca,
        somenteMeus: parameters.somenteMeus,
        somenteNaoLidos: parameters.somenteNaoLidos,
      );
}

/// P5 — a linha do tempo do atendimento.
final class ListarTimelineDatasource
    implements Datasource<List<EventoDaTimeline>, ListarTimelineParameters> {
  final AtendimentoGateway _gateway;

  const ListarTimelineDatasource({required this._gateway});

  @override
  Future<List<EventoDaTimeline>> call(ListarTimelineParameters parameters) =>
      _gateway.listarTimeline(atendimentoId: parameters.atendimentoId);
}

/// P5 — as outras conversas do mesmo contato.
final class AtendimentosDoContatoDatasource
    implements
        Datasource<List<AtendimentoResumo>, AtendimentosDoContatoParameters> {
  final AtendimentoGateway _gateway;

  const AtendimentosDoContatoDatasource({required this._gateway});

  @override
  Future<List<AtendimentoResumo>> call(
    AtendimentosDoContatoParameters parameters,
  ) => _gateway.listarAtendimentosDoContato(
    contatoId: parameters.contatoId,
    limit: parameters.limit,
  );
}

/// P5 — apaga uma nota interna.
final class RemoverNotaDatasource
    implements Datasource<Unit, RemoverNotaParameters> {
  final AtendimentoGateway _gateway;

  const RemoverNotaDatasource({required this._gateway});

  @override
  Future<Unit> call(RemoverNotaParameters parameters) async {
    await _gateway.removerNota(
      notaId: parameters.notaId,
      atendimentoId: parameters.atendimentoId,
    );
    return unit;
  }
}

/// P5 — renomeia/recolore uma etiqueta do catálogo.
final class AtualizarEtiquetaDatasource
    implements Datasource<Etiqueta, AtualizarEtiquetaParameters> {
  final AtendimentoGateway _gateway;

  const AtualizarEtiquetaDatasource({required this._gateway});

  @override
  Future<Etiqueta> call(AtualizarEtiquetaParameters parameters) =>
      _gateway.atualizarEtiqueta(
        id: parameters.id,
        nome: parameters.nome,
        cor: parameters.cor,
        descricao: parameters.descricao,
      );
}

/// P5 — tira a etiqueta do catálogo.
final class DesativarEtiquetaDatasource
    implements Datasource<Unit, DesativarEtiquetaParameters> {
  final AtendimentoGateway _gateway;

  const DesativarEtiquetaDatasource({required this._gateway});

  @override
  Future<Unit> call(DesativarEtiquetaParameters parameters) async {
    await _gateway.desativarEtiqueta(id: parameters.id);
    return unit;
  }
}
