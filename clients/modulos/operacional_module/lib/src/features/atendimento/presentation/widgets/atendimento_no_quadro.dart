import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/quadro.dart';

/// Resultado de uma ação do workspace: `null` deu certo; senão, a mensagem a
/// mostrar para quem clicou.
typedef AcaoDoAtendimento<T> = Future<String?> Function(T valor);

/// O atendimento aberto, como o quadro o conhece, e o que dá para fazer com
/// ele.
///
/// A conversa e o painel de informações moram fora do quadro, mas é o quadro
/// que sabe o estado do cartão (status, prioridade, dono, coluna) e fala com
/// o servidor para mudá-lo. Sem isto, o painel da direita só mostraria a ficha
/// — e mudar o status ou assumir a conversa exigiria voltar ao cartão.
class AtendimentoNoQuadro {
  final AtendimentoResumo resumo;

  /// Nome da coluna em que o cartão está; vazio quando está fora do quadro.
  final String etapaNome;

  /// Quadros para onde a conversa pode ser transferida (inclui o atual).
  final List<FluxoDoQuadro> fluxos;

  final AcaoDoAtendimento<String> definirStatus;
  final AcaoDoAtendimento<String> definirPrioridade;
  final AcaoDoAtendimento<int> transferirParaFluxo;

  /// `true` põe a conversa com quem está logado; `false` devolve para a fila.
  final AcaoDoAtendimento<bool> assumir;
  final Future<String?> Function() marcarRevisado;

  const AtendimentoNoQuadro({
    required this.resumo,
    required this.etapaNome,
    required this.fluxos,
    required this.definirStatus,
    required this.definirPrioridade,
    required this.transferirParaFluxo,
    required this.assumir,
    required this.marcarRevisado,
  });

  /// O quadro em que a conversa está, como a pessoa o reconhece.
  String get fluxoRotulo {
    for (final f in fluxos) {
      if (f.id == resumo.fluxoAtendimentoId) return f.rotulo;
    }
    return '';
  }

  /// Para onde dá para transferir.
  List<FluxoDoQuadro> get outrosFluxos => [
    for (final f in fluxos)
      if (f.id != resumo.fluxoAtendimentoId) f,
  ];
}

/// Os estados como a pessoa os lê.
const rotulosDeStatus = <String, String>{
  'fila': 'Na fila',
  'em_atendimento': 'Em atendimento',
  'pendencia': 'Pendente',
  'resolvido': 'Resolvido',
  'cancelado': 'Cancelado',
  'arquivado': 'Arquivado',
};

String rotuloDoStatus(String status) => rotulosDeStatus[status] ?? status;

/// As prioridades que o cartão aceita, na ordem em que fazem sentido.
const prioridadesOferecidas = <(String, String)>[
  ('urgente', 'Urgente'),
  ('alta', 'Alta'),
  ('normal', 'Normal'),
  ('baixa', 'Baixa'),
];
