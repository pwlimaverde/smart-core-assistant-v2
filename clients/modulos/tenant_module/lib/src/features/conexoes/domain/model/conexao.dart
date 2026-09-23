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

  /// Quando `false`, a IA não responde NENHUMA conversa desta conexão.
  ///
  /// É a barreira mais externa do bot: precede o desligamento por conversa e o
  /// bloqueio por atendente humano ativo. Equivale ao `resposta_bot` da v1, que
  /// a v2 tinha perdido.
  final bool respostaBot;

  /// P7 — para onde as conversas deste número vão. 0 = sem departamento, e aí
  /// elas caem no primeiro fluxo ativo do tenant, como era antes.
  ///
  /// Era assim na v1: quem tem um número de vendas e outro de suporte precisa
  /// que cada um entre na fila certa.
  final int departamentoId;
  final String departamentoNome;

  final DateTime criadaEm;

  const Conexao({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.estado,
    required this.ativa,
    required this.criadaEm,
    this.respostaBot = true,
    this.departamentoId = 0,
    this.departamentoNome = '',
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
    respostaBot: respostaBot,
    departamentoId: departamentoId,
    departamentoNome: departamentoNome,
  );

  /// Mesma conexão com o bot ligado/desligado — para a tela refletir o toggle
  /// sem recarregar a lista inteira do servidor.
  Conexao comRespostaBot(bool valor) => Conexao(
    id: id,
    nome: nome,
    telefone: telefone,
    estado: estado,
    ativa: ativa,
    criadaEm: criadaEm,
    respostaBot: valor,
    departamentoId: departamentoId,
    departamentoNome: departamentoNome,
  );

  /// P7 — mesma conexão roteando para outro departamento, para a tela refletir
  /// a troca sem reconsultar o provedor conexão por conexão.
  Conexao comDepartamento(int id, String nome) => Conexao(
    id: this.id,
    nome: this.nome,
    telefone: telefone,
    estado: estado,
    ativa: ativa,
    criadaEm: criadaEm,
    respostaBot: respostaBot,
    departamentoId: id,
    departamentoNome: nome,
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
  // "Aguardando QR", e não "Conectando": o provedor não está tentando nada —
  // ele espera alguém ler o código com o celular. "Conectando" fazia parecer
  // que o sistema estava trabalhando, e a conexão ficava assim indefinidamente
  // enquanto ninguém entendia que a ação era humana.
  conectando('Aguardando QR', 'Leia o QR code com o celular para conectar.'),
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

/// P7 — o detalhe da conexão: o que não cabe na lista e quem investiga precisa.
@immutable
class DetalheConexao {
  final Conexao conexao;

  /// Quando o estado foi conferido com o provedor pela última vez.
  /// `null` = nunca — a conexão nasceu e ninguém abriu a tela desde então.
  final DateTime? ultimaChecagem;

  /// O identificador da instância NO PROVEDOR. É o que aparece no log da
  /// evolution-go e o que se manda para o suporte.
  final String instanciaNoProvedor;

  /// Do TENANT, não desta conexão: o atendimento não guarda por qual conexão
  /// entrou. Vale como "desligar agora deixa gente no meio do caminho?".
  final int atendimentosAbertos;
  final int mensagens24h;

  const DetalheConexao({
    required this.conexao,
    required this.instanciaNoProvedor,
    required this.atendimentosAbertos,
    required this.mensagens24h,
    this.ultimaChecagem,
  });
}

/// P9 — uma mensagem do atendente que não tinha para onde ir.
///
/// Acontece quando o contato não tem conexão ativa no momento do envio. O
/// reprocessamento existia desde a N7.2 e nenhuma tela o alcançava: a mensagem
/// ficava parada sem ninguém saber que não chegou.
@immutable
class MensagemParada {
  final int id;
  final int atendimentoId;
  final String motivo;
  final DateTime criadaEm;

  /// Início do texto. PII — nunca em log.
  final String trecho;
  final String contato;

  const MensagemParada({
    required this.id,
    required this.atendimentoId,
    required this.motivo,
    required this.criadaEm,
    required this.trecho,
    required this.contato,
  });
}

/// P9 — o desfecho de uma tentativa de reenvio.
enum DesfechoReenvio {
  /// Voltou ao outbox; o worker tenta de novo.
  reenviada('Mensagem reenviada.'),

  /// O contato continua sem conexão ativa. Não é erro — é a resposta honesta
  /// de que ainda não há para onde mandar.
  semDestino('O contato ainda não tem conexão ativa. Tente depois.'),

  /// Alguém já tratou, ou o registro sumiu.
  naoEncontrada('Esta mensagem já foi tratada.');

  final String texto;

  const DesfechoReenvio(this.texto);

  static DesfechoReenvio doServidor(String status) => switch (status) {
    'reprocessada' => DesfechoReenvio.reenviada,
    'ainda_sem_destino' => DesfechoReenvio.semDestino,
    _ => DesfechoReenvio.naoEncontrada,
  };
}
