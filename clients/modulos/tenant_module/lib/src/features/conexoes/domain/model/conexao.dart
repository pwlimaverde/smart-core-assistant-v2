import 'package:meta/meta.dart';

/// Uma conexão de WhatsApp do tenant.
@immutable
class Conexao {
  final int id;
  final String nome;

  /// Número pareado; vazio enquanto o QR não foi lido.
  final String telefone;
  final String estado;
  final bool ativa;
  final DateTime criadaEm;

  const Conexao({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.estado,
    required this.ativa,
    required this.criadaEm,
  });

  /// Vocabulário de `whatsapp_instance.connection_state`. `unknown` existe
  /// porque o provedor pode não responder — e não saber é diferente de estar
  /// desconectado: um pede espera, o outro pede ação.
  SituacaoConexao get situacao => switch (estado) {
        'connected' => SituacaoConexao.conectada,
        'connecting' => SituacaoConexao.conectando,
        'disconnected' => SituacaoConexao.desconectada,
        _ => SituacaoConexao.desconhecida,
      };
}

enum SituacaoConexao {
  conectada('Conectada', 'Recebendo e enviando mensagens.'),
  conectando('Conectando', 'Aguardando a leitura do QR code.'),
  desconectada('Desconectada', 'Não recebe mensagens. Reconecte para voltar.'),
  desconhecida('Sem resposta', 'O provedor não respondeu. Tente atualizar.');

  final String rotulo;
  final String explicacao;

  const SituacaoConexao(this.rotulo, this.explicacao);
}
