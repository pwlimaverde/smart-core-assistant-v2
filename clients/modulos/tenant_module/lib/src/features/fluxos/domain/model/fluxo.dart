import 'package:meta/meta.dart';

/// O quadro por onde uma conversa anda dentro de um departamento.
@immutable
class Fluxo {
  final int id;
  final int departamentoId;
  final String departamentoNome;
  final String nome;
  final String descricao;
  final bool ativo;

  /// Quantas colunas o quadro tem hoje.
  final int etapas;

  /// Conversas que ainda não terminaram neste fluxo.
  final int atendimentosAbertos;

  const Fluxo({
    required this.id,
    required this.departamentoId,
    required this.departamentoNome,
    required this.nome,
    required this.descricao,
    required this.ativo,
    required this.etapas,
    required this.atendimentosAbertos,
  });

  /// Um fluxo sem coluna nenhuma não recebe conversa: o roteamento procura a
  /// etapa de entrada e não acha. Vale avisar antes que alguém descubra pelo
  /// atendimento que sumiu.
  bool get semEtapas => etapas == 0;

  /// Desativar por baixo de conversas abertas as deixaria num quadro que
  /// ninguém mais abre — o servidor recusa, e a tela avisa antes de tentar.
  bool get podeDesativar => ativo && atendimentosAbertos == 0;
}

/// O que cada coluna significa para o roteamento.
///
/// Vocabulário fechado, herdado da v1: não é rótulo livre. `fila` é onde a
/// conversa entra, e um fluxo sem ela não recebe nada.
enum TipoEtapa {
  fila('fila', 'Fila de entrada', 'Onde as conversas novas caem'),
  trabalho('trabalho', 'Em atendimento', 'Alguém está cuidando agora'),
  espera('espera', 'Aguardando', 'Parado esperando algo de fora'),
  finalizacao('finalizacao', 'Finalização', 'Fim de linha do atendimento');

  final String codigo;
  final String rotulo;
  final String explicacao;

  const TipoEtapa(this.codigo, this.rotulo, this.explicacao);

  /// Tipo desconhecido cai em `trabalho` em vez de estourar: o banco aceita
  /// qualquer texto de 20 caracteres, e uma tela que quebra por causa de uma
  /// linha antiga é pior que uma coluna com o rótulo genérico.
  static TipoEtapa doCodigo(String codigo) => TipoEtapa.values.firstWhere(
        (t) => t.codigo == codigo,
        orElse: () => TipoEtapa.trabalho,
      );
}

/// Uma coluna do quadro.
@immutable
class EtapaFluxo {
  final int id;
  final int fluxoId;
  final String nome;
  final String descricao;
  final int ordem;
  final String cor;
  final TipoEtapa tipo;
  final bool ativo;

  const EtapaFluxo({
    required this.id,
    required this.fluxoId,
    required this.nome,
    required this.descricao,
    required this.ordem,
    required this.cor,
    required this.tipo,
    required this.ativo,
  });
}
