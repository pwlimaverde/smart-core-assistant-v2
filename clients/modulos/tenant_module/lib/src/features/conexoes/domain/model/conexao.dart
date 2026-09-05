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

  /// Mesma conexão com o estado trocado — usado para substituir o valor
  /// guardado no banco pelo que o provedor respondeu agora.
  Conexao comEstado(String novoEstado) => Conexao(
        id: id,
        nome: nome,
        telefone: telefone,
        estado: novoEstado,
        ativa: ativa,
        criadaEm: criadaEm,
      );

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

/// Resultado da criação de uma conexão — o `id` é o que a tela precisa para
/// acompanhar o pareamento logo em seguida.
@immutable
class ConexaoCriada {
  final int id;
  final String nome;

  const ConexaoCriada({required this.id, required this.nome});
}

/// Fotografia do pareamento: o estado do provedor e, enquanto ele não conectou,
/// o QR que o celular precisa ler.
///
/// O QR chega como imagem pronta em base64 (a evolution-go devolve a imagem, não
/// o payload do código) — a tela só desenha, não gera.
@immutable
class EstadoPareamento {
  final String estado;
  final String qrCode;

  const EstadoPareamento({required this.estado, required this.qrCode});

  bool get conectado => estado == 'connected';

  bool get temQr => qrCode.isNotEmpty;
}
