import 'package:return_success_or_error/return_success_or_error.dart';

/// P3 — a presença do atendente numa conversa ("digitando...", "gravando...").
///
/// [situacao] usa o vocabulário do provedor: `composing`, `recording` ou
/// `paused`. Traduzir para português aqui só criaria uma tabela a mais para
/// manter em duas pontas.
final class EnviarPresencaParameters extends Parameters {
  final int atendimentoId;
  final String situacao;

  const EnviarPresencaParameters({
    required this.atendimentoId,
    this.situacao = 'composing',
  });
}

/// P3 — os arquivos trocados numa conversa (galeria).
final class ListarMidiasParameters extends Parameters {
  final int atendimentoId;
  final int limit;
  final int offset;

  const ListarMidiasParameters({
    required this.atendimentoId,
    this.limit = 60,
    this.offset = 0,
  });
}

/// P3 — um anexo (arquivo escolhido ou áudio gravado) indo para a conversa.
///
/// Os bytes ficam aqui e em nenhum log: é conteúdo do cliente. O upload é PUT
/// direto ao R2 pelo gateway; este parâmetro só descreve o que enviar.
final class EnviarMidiaParameters extends Parameters {
  final int atendimentoId;
  final String nomeArquivo;
  final String mimetype;
  final List<int> bytes;
  final String legenda;

  /// `true` no áudio gravado na hora: no WhatsApp ele aparece como mensagem de
  /// voz, e não como um arquivo de áudio anexado.
  final bool ehPtt;

  const EnviarMidiaParameters({
    required this.atendimentoId,
    required this.nomeArquivo,
    required this.mimetype,
    required this.bytes,
    this.legenda = '',
    this.ehPtt = false,
  });
}
