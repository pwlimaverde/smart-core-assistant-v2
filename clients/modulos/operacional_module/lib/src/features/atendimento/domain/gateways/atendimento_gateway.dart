import '../model/atendimento_evento.dart';
import '../model/atendimento_resumo.dart';
import '../model/mensagem_thread.dart';
import '../model/ficha.dart';
import '../model/midia_mensagem.dart';
import '../model/quadro.dart';

/// Fronteira de infraestrutura do atendimento, **escolhida por plataforma**:
/// gRPC-Web no browser, motor local Rust (SQLite + fila offline) no desktop.
///
/// **Por que um gateway agregado e não um `Datasource` por operação:** o que
/// varia aqui é a *plataforma*, não a operação. Um único objeto trocado no boot
/// (por import condicional) mantém as quatro operações e o stream coerentes entre
/// si — no desktop, `listAtendimentos` e `sendOutboundMessage` compartilham o
/// mesmo índice SQLite e a mesma fila. Quebrar isso em oito classes (4 operações
/// × 2 plataformas) espalharia essa coerência por uma matriz.
///
/// Os `Datasource<TData, TParams>` da `return_success_or_error` ficam **em cima**
/// deste port: são adaptadores finos, um por operação, que traduzem
/// `Parameters` → chamada do gateway. É a costura entre o eixo "plataforma"
/// (aqui) e o eixo "operação" (a lib).
///
/// Como todo datasource na v3, este port é **burro**: devolve o dado ou deixa a
/// exceção técnica subir crua (`GrpcError` no Web, [LocalEngineFalha] no
/// desktop). Traduzir para erro de domínio é trabalho do `mapError` de cada
/// repositório — antes, cada adapter fazia isso por conta própria e o resultado
/// era `ErrorNetwork(message: '$e')` chegando à tela.
abstract interface class AtendimentoGateway {
  /// Lista a fila de atendimentos por status/departamento (Kanban — WS-6.2).
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status,
    int? departamentoId,
    int limit,
  });

  /// Carrega o thread (histórico de mensagens) de um atendimento.
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit,
    int offset,
  });

  /// Move um atendimento para outra etapa do Kanban (drag-and-drop).
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo,
  });

  /// Muda o status do atendimento; o servidor move o cartão junto.
  ///
  /// O par simétrico do arrasto: lá a coluna manda no status, aqui o status
  /// manda na coluna. Encerrar pelo chat sem isto deixaria o cartão parado na
  /// coluna de trabalho, e o quadro passaria a mentir sobre o que está aberto.
  Future<void> setAtendimentoStatus({
    required int atendimentoId,
    required String status,
    String motivo,
  });

  /// Quadros que o atendente pode abrir.
  ///
  /// Configuração, não dado operacional: vai direto ao servidor mesmo no
  /// desktop. Guardá-la no índice offline arriscaria montar o quadro com
  /// colunas que já não existem.
  Future<List<FluxoDoQuadro>> listFluxos();

  /// Colunas de um quadro, na ordem em que aparecem.
  Future<List<ColunaDoQuadro>> listColunas(int fluxoId);

  /// A ficha do atendimento: catálogo de etiquetas, as aplicadas e as notas.
  ///
  /// Uma chamada só para os três: são consultas pequenas sobre o mesmo
  /// atendimento, e três idas ao servidor a cada cartão aberto seriam três
  /// esperas para montar um painel.
  Future<FichaAtendimento> getFicha(int atendimentoId);

  /// Cria uma etiqueta no catálogo do tenant.
  Future<void> criarEtiqueta({required String nome, required String cor});

  /// Cola ou tira uma etiqueta desta conversa.
  Future<void> alternarEtiqueta({
    required int atendimentoId,
    required int etiquetaId,
    required bool aplicar,
  });

  /// Anota algo na conversa. A nota é interna: o contato nunca a vê.
  Future<void> criarNota({required int atendimentoId, required String texto});

  /// Persiste uma mensagem outbound do atendente; devolve o id da mensagem.
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo,
  });

  /// N9/E1 — sobe um anexo e o põe na conversa.
  ///
  /// **Uma operação só, e não três**, apesar de o servidor expor o upload em
  /// duas etapas (`SolicitarUploadMidia` → PUT no bucket →
  /// `EnviarMidiaAtendimento`). O protocolo de duas etapas existe para tirar o
  /// binário do gRPC-Web; a tela não tem nada a decidir no meio dele. Expor as
  /// três chamadas separadas obrigaria cada chamador a repetir a coreografia —
  /// e a errá-la (o PUT precisa mandar EXATAMENTE o `Content-Type` assinado, ou
  /// o R2 recusa).
  ///
  /// [aoProgredir] recebe de 0 a 1 durante o envio dos bytes, para a barra.
  ///
  /// Devolve o id da mensagem criada.
  Future<int> enviarMidia({
    required int atendimentoId,
    required String nomeArquivo,
    required String mimetype,
    required List<int> bytes,
    String legenda,
    bool ehPtt,
    void Function(double progresso)? aoProgredir,
  });

  /// N9/E2 — mídias do atendimento, para a galeria da ficha.
  ///
  /// As URLs vêm assinadas com TTL curto: a lista é para exibir agora, não para
  /// guardar.
  Future<List<MidiaMensagem>> listarMidias({
    required int atendimentoId,
    int limit,
    int offset,
  });

  /// Abre o stream realtime de eventos do tenant (fila/Kanban/chat).
  ///
  /// Cada reconexão chama este método novamente — a política de backoff mora na
  /// apresentação (WS-6.3). Erros e o encerramento chegam como erro/fim do
  /// próprio `Stream`: não há `ReturnSuccessOrError` aqui porque a lib é
  /// request/response, e embrulhar um fluxo contínuo nela esconderia justamente
  /// o que a UI precisa observar.
  Stream<AtendimentoEvento> streamAtendimentos();
}

/// N9/E1 — o PUT do anexo no bucket falhou.
///
/// Exceção técnica separada porque o upload é o **único** passo do sistema que
/// não passa pelo gRPC: um erro aqui não é `GrpcError` nem falha do motor local,
/// e o `mapError` do repositório precisa distingui-lo para dizer "o arquivo não
/// subiu" em vez de "a conversa não carregou".
///
/// A mensagem nunca carrega a URL assinada.
final class FalhaUploadMidia implements Exception {
  final String message;

  const FalhaUploadMidia(this.message);

  @override
  String toString() => 'FalhaUploadMidia - $message';
}

/// Falha do motor local (FFI/`local_engine`): índice SQLite, fila offline, cache
/// de mídia ou sincronização.
///
/// É uma **exceção técnica**, não um erro de domínio: existe para que o
/// `mapError` de cada repositório consiga distinguir "o armazenamento local
/// falhou" de "a rede falhou" — desfechos com ações diferentes para o usuário
/// (reiniciar o app vs. tentar de novo). A mensagem do motor descreve
/// storage/sync/io/mídia e não carrega PII.
final class LocalEngineFalha implements Exception {
  final String message;
  final Object causa;

  const LocalEngineFalha(this.message, this.causa);

  @override
  String toString() => 'LocalEngineFalha - $message';
}
