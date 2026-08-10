import 'dart:convert';

import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:http/http.dart' as http;

import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/model/ficha.dart';
import '../../domain/model/midia_mensagem.dart';
import '../../domain/model/quadro.dart';

/// Adapter Web do [AtendimentoGateway] via gRPC-Web (`AdminServiceClient`).
///
/// Único ponto do módulo que fala com o transporte: nenhuma outra camada
/// (repositórios/usecases/controllers/telas) referencia `proto.*` (DIP). O
/// desktop usa `LocalEngineGateway` no lugar deste, sem mudar nada acima.
///
/// **Sem try/catch:** a exceção do transporte sobe crua para o `mapError` do
/// repositório. Antes, cada método traduzia por conta própria, e o `catch`
/// genérico interpolava a exceção na mensagem do erro — que terminava exibida na
/// tela.
final class AtendimentoRemoteGateway implements AtendimentoGateway {
  final proto.AdminServiceClient _client;

  /// Cliente HTTP do PUT no bucket. Injetável para o teste poder observar o
  /// header `Content-Type` — que é onde o upload quebra na prática, e é uma
  /// falha silenciosa (o R2 responde 403 sem dizer por quê).
  final http.Client _http;

  AtendimentoRemoteGateway({
    required proto.AdminServiceClient client,
    http.Client? httpClient,
  }) : _client = client, // ignore: prefer_initializing_formals
       _http = httpClient ?? http.Client();

  @override
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    final resp = await _client.listAtendimentos(
      proto.ListAtendimentosRequest(
        status: status,
        departamentoId: departamentoId ?? 0,
        limit: limit,
      ),
    );
    return resp.atendimentos.map(_paraAtendimentoResumo).toList();
  }

  @override
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _client.getThread(
      proto.GetThreadRequest(
        atendimentoId: atendimentoId,
        limit: limit,
        offset: offset,
      ),
    );
    return resp.mensagens.map(_paraMensagemThread).toList();
  }

  @override
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    await _client.moveAtendimentoEtapa(
      proto.MoveAtendimentoEtapaRequest(
        atendimentoId: atendimentoId,
        etapaDestinoId: etapaDestinoId,
        motivo: motivo,
      ),
    );
  }

  @override
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    // NUNCA logar `conteudo` (PII) — só trafega no corpo da chamada RPC.
    final resp = await _client.sendOutboundMessage(
      proto.SendOutboundMessageRequest(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
        tipo: tipo,
      ),
    );
    return resp.messageId;
  }

  @override
  Future<int> enviarMidia({
    required int atendimentoId,
    required String nomeArquivo,
    required String mimetype,
    required List<int> bytes,
    String legenda = '',
    bool ehPtt = false,
    void Function(double progresso)? aoProgredir,
  }) async {
    // 1. Onde subir. O servidor valida tipo, tamanho e quota ANTES de assinar —
    // se o arquivo não pode entrar, o atendente descobre agora, não depois de
    // esperar a barra encher.
    final autorizacao = await _client.solicitarUploadMidia(
      proto.SolicitarUploadMidiaRequest(
        atendimentoId: atendimentoId,
        nomeArquivo: nomeArquivo,
        mimetype: mimetype,
        bytes: Int64(bytes.length),
      ),
    );
    aoProgredir?.call(0);

    // 2. PUT direto no bucket.
    //
    // O `Content-Type` TEM de ser exatamente o que foi assinado — vem no
    // `content_type` da resposta, e não do que escolhemos aqui. Divergir faz o
    // R2 responder 403 sem explicar, e o sintoma na tela é "falhou" sem motivo.
    final resposta = await _http.put(
      Uri.parse(autorizacao.urlUpload),
      headers: {'Content-Type': autorizacao.contentType},
      body: bytes,
    );
    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      // Sem a URL na mensagem: é credencial de escrita no bucket.
      throw FalhaUploadMidia(
        'o envio do arquivo falhou (HTTP ${resposta.statusCode})',
      );
    }
    aoProgredir?.call(1);

    // 3. Confirmar. É aqui que o servidor confere o CONTEÚDO do que subiu e põe
    // a mensagem na conversa.
    final confirmacao = await _client.enviarMidiaAtendimento(
      proto.EnviarMidiaAtendimentoRequest(
        atendimentoId: atendimentoId,
        chave: autorizacao.chave,
        mimetype: mimetype,
        nomeArquivo: nomeArquivo,
        legenda: legenda,
        isPtt: ehPtt,
      ),
    );
    return confirmacao.messageId;
  }

  @override
  Future<List<MidiaMensagem>> listarMidias({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _client.listarMidiasAtendimento(
      proto.ListarMidiasAtendimentoRequest(
        atendimentoId: atendimentoId,
        limit: limit,
        offset: offset,
      ),
    );
    return resp.midias.map(_paraMidia).toList();
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() {
    // O erro do stream sobe cru: quem trata queda de conexão é a apresentação
    // (backoff exponencial + jitter), e ela decide com base no erro original.
    return _client
        .streamAtendimentos(proto.StreamAtendimentosRequest())
        .map(_paraAtendimentoEvento);
  }

  static AtendimentoResumo _paraAtendimentoResumo(proto.AtendimentoResumo a) =>
      AtendimentoResumo(
        id: a.id,
        contatoId: a.contatoId,
        status: a.status,
        departamentoId: a.departamentoId > 0 ? a.departamentoId : null,
        fluxoAtendimentoId: a.fluxoAtendimentoId > 0
            ? a.fluxoAtendimentoId
            : null,
        etapaAtualId: a.etapaAtualId > 0 ? a.etapaAtualId : null,
        assunto: a.assunto,
        prioridade: a.prioridade,
        atendenteHumanoId: a.atendenteHumanoId > 0 ? a.atendenteHumanoId : null,
        dataInicio: DateTime.fromMillisecondsSinceEpoch(a.dataInicio.toInt()),
        dataUltimaMensagem: a.dataUltimaMensagem.toInt() > 0
            ? DateTime.fromMillisecondsSinceEpoch(a.dataUltimaMensagem.toInt())
            : null,
        sentimentoNota: a.hasSentimentoNota() ? a.sentimentoNota : null,
        sentimentoLabel: a.hasSentimentoLabel() ? a.sentimentoLabel : null,
      );

  static MensagemThread _paraMensagemThread(proto.MensagemThread m) =>
      MensagemThread(
        id: m.id,
        atendimentoId: m.atendimentoId,
        tipo: m.tipo,
        conteudo: m.conteudo,
        remetente: m.remetente,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp.toInt()),
        statusEnvio: m.statusEnvio,
        geradoPorIa: m.geradoPorIa,
        resumoMidia: m.hasResumoMidia() ? m.resumoMidia : null,
        midia: m.hasMidia() ? _paraMidia(m.midia) : null,
        entregueEm: m.hasDataEntregue()
            ? DateTime.fromMillisecondsSinceEpoch(m.dataEntregue.toInt())
            : null,
        lidaEm: m.hasDataLida()
            ? DateTime.fromMillisecondsSinceEpoch(m.dataLida.toInt())
            : null,
        // A citação só existe completa: sem o id não há para onde rolar, e sem
        // preview não há o que desenhar. Meia citação é pior que nenhuma.
        citacao: m.hasMensagemCitadaId() && m.hasCitadaPreview()
            ? CitacaoMensagem(
                mensagemId: m.mensagemCitadaId,
                remetente: m.hasCitadaRemetente() ? m.citadaRemetente : '',
                preview: m.citadaPreview,
              )
            : null,
      );

  static MidiaMensagem _paraMidia(proto.MidiaMensagem m) => MidiaMensagem(
    tipo: TipoMidia.doServidor(m.kind),
    urlAssinada: m.urlAssinada,
    mimetype: m.mimetype,
    nomeArquivo: m.filename,
    tamanhoBytes: m.sizeBytes.toInt(),
    segundos: m.hasSeconds() ? m.seconds : null,
    ehPtt: m.hasIsPtt() && m.isPtt,
  );

  static AtendimentoEvento _paraAtendimentoEvento(proto.AtendimentoEvent e) {
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(e.payload);
      payload = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } catch (_) {
      payload = <String, Object?>{};
    }
    return AtendimentoEvento(
      tipo: e.eventType,
      tenantId: e.tenantId,
      payload: payload,
    );
  }

  @override
  Future<void> setAtendimentoStatus({
    required int atendimentoId,
    required String status,
    String motivo = '',
  }) async {
    await _client.setAtendimentoStatus(
      proto.SetAtendimentoStatusRequest(
        atendimentoId: atendimentoId,
        status: status,
        motivo: motivo,
      ),
    );
  }

  @override
  Future<List<FluxoDoQuadro>> listFluxos() async {
    final resp = await _client.listMyFluxos(proto.ListMyFluxosRequest());
    return resp.fluxos
        .where((f) => f.ativo)
        .map(
          (f) => FluxoDoQuadro(
            id: f.id,
            nome: f.nome,
            departamentoNome: f.departamentoNome,
          ),
        )
        .toList();
  }

  @override
  Future<List<ColunaDoQuadro>> listColunas(int fluxoId) async {
    final resp = await _client.listMyEtapasFluxo(
      proto.MyFluxoIdRequest(id: fluxoId),
    );
    return resp.etapas
        .map(
          (e) => ColunaDoQuadro(
            id: e.id,
            nome: e.nome,
            cor: e.cor,
            ordem: e.ordem,
            tipo: e.tipoEtapa,
          ),
        )
        .toList();
  }

  @override
  Future<FichaAtendimento> getFicha(int atendimentoId) async {
    final resp = await _client.getDetalheAtendimento(
      proto.AtendimentoIdRequest(atendimentoId: atendimentoId),
    );
    return FichaAtendimento(
      catalogo: resp.catalogo.map(_etiquetaDoProto).toList(),
      aplicadas: resp.etiquetas.map(_etiquetaDoProto).toList(),
      notas: resp.notas
          .map(
            (n) => Nota(
              id: n.id.toInt(),
              texto: n.texto,
              criadoEm: DateTime.fromMillisecondsSinceEpoch(n.criadoEm.toInt()),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> criarEtiqueta({
    required String nome,
    required String cor,
  }) async {
    await _client.createEtiqueta(
      proto.CreateEtiquetaRequest(nome: nome, cor: cor),
    );
  }

  @override
  Future<void> alternarEtiqueta({
    required int atendimentoId,
    required int etiquetaId,
    required bool aplicar,
  }) async {
    await _client.alternarEtiqueta(
      proto.AlternarEtiquetaRequest(
        atendimentoId: atendimentoId,
        etiquetaId: Int64(etiquetaId),
        aplicar: aplicar,
      ),
    );
  }

  @override
  Future<void> criarNota({
    required int atendimentoId,
    required String texto,
  }) async {
    // NUNCA logar `texto` (PII) — só trafega no corpo da chamada.
    await _client.createNota(
      proto.CreateNotaRequest(atendimentoId: atendimentoId, texto: texto),
    );
  }
}

/// Converte a etiqueta do contrato no modelo de domínio.
Etiqueta _etiquetaDoProto(proto.Etiqueta e) => Etiqueta(
      id: e.id.toInt(),
      nome: e.nome,
      cor: e.cor,
      descricao: e.descricao,
      ativo: e.ativo,
    );
