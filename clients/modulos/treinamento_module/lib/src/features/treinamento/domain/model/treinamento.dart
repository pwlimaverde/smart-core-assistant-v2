import 'package:meta/meta.dart';

/// Um material de treinamento do assistente.
///
/// O ciclo tem três estados, e a tela mostra os três porque quem treinou
/// precisa ver o que ficou pelo caminho:
///
///  - **rascunho** — criado, texto ainda em revisão;
///  - **na fila** — aceito, esperando o worker vetorizar;
///  - **ativo** — vetorizado; a partir daqui o assistente usa este material.
@immutable
class Treinamento {
  final int id;

  /// Assunto. Com o [grupo], identifica o treinamento dentro do tenant.
  final String tag;
  final String grupo;
  final String conteudo;
  final bool finalizado;
  final bool vetorizado;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  /// B9 (N10 E5) — vazio quando o material é texto colado.
  final String arquivoNome;

  /// `pendente` | `extraido` | `falhou` | vazio.
  final String extracaoStatus;

  /// Motivo da falha da extração, pronto para ler.
  final String extracaoErro;

  const Treinamento({
    required this.id,
    required this.tag,
    required this.grupo,
    required this.conteudo,
    required this.finalizado,
    required this.vetorizado,
    required this.criadoEm,
    required this.atualizadoEm,
    this.arquivoNome = '',
    this.extracaoStatus = '',
    this.extracaoErro = '',
  });

  bool get veioDeArquivo => arquivoNome.isNotEmpty;

  /// O texto do arquivo ainda está sendo lido: não há o que revisar.
  bool get extraindo => extracaoStatus == 'pendente';

  bool get extracaoFalhou => extracaoStatus == 'falhou';

  SituacaoTreinamento get situacao {
    if (vetorizado) return SituacaoTreinamento.ativo;
    if (finalizado) return SituacaoTreinamento.naFila;
    return SituacaoTreinamento.rascunho;
  }
}

enum SituacaoTreinamento {
  rascunho('Rascunho', 'Ainda não enviado para a IA.'),
  naFila('Processando', 'Aceito; a IA está processando o material.'),
  ativo('Ativo', 'O assistente já usa este material nas respostas.');

  final String rotulo;
  final String explicacao;

  const SituacaoTreinamento(this.rotulo, this.explicacao);
}
