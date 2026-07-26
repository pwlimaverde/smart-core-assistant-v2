import '../model/atendimento_evento.dart';

/// Fonte de eventos realtime do atendimento, consumida pelos controllers.
///
/// **Por que isto não é um usecase:** a `return_success_or_error` modela
/// request/response — um `ReturnSuccessOrError` descreve *um* desfecho. Um fluxo
/// contínuo tem N desfechos e um ciclo de vida (abre, cai, reconecta), e
/// embrulhá-lo em `Success`/`Failure` esconderia exatamente o que a UI precisa
/// observar: o momento da queda. Então o stream é um port de domínio próprio, e
/// erro/encerramento chegam como erro/fim do próprio `Stream`.
///
/// A política de reconexão (backoff exponencial + jitter) vive na apresentação,
/// onde está o ciclo de vida da tela. Cada reconexão chama [abrir] novamente.
abstract interface class AtendimentoEventoStream {
  /// Abre uma nova assinatura de eventos do tenant da sessão.
  Stream<AtendimentoEvento> abrir();
}
