import 'package:meta/meta.dart';

/// Como a conexão de um provedor nasce. Escolhe o FLUXO da tela, não o
/// provedor: a tela de Integrações não conhece nenhum provedor pelo nome.
enum ModoConexao {
  /// Ler um QR code no celular.
  qrPairing,

  /// Colar credenciais num formulário (id do número, token).
  token,

  /// Autorizar por redirecionamento (login da Meta).
  oauth,

  /// Cadastro embutido do provedor.
  embedded,

  /// Copiar um trecho de código para o site.
  copySnippet,

  /// Modo que esta versão do app ainda não conhece.
  desconhecido;

  static ModoConexao doServidor(String valor) => switch (valor) {
    'qr_pairing' => ModoConexao.qrPairing,
    'token' => ModoConexao.token,
    'oauth' => ModoConexao.oauth,
    'embedded' => ModoConexao.embedded,
    'copy_snippet' => ModoConexao.copySnippet,
    _ => ModoConexao.desconhecido,
  };

  /// Se esta versão do app sabe conduzir o fluxo.
  bool get suportadoNoApp =>
      this == ModoConexao.qrPairing || this == ModoConexao.token;
}

/// Tipo de um campo do formulário de configuração.
enum TipoCampoCanal {
  texto,

  /// Não é ecoado na tela.
  segredo,
  telefone,
  url;

  static TipoCampoCanal doServidor(String valor) => switch (valor) {
    'segredo' => TipoCampoCanal.segredo,
    'telefone' => TipoCampoCanal.telefone,
    'url' => TipoCampoCanal.url,
    _ => TipoCampoCanal.texto,
  };
}

/// Um campo que o provedor pede para conectar.
@immutable
class CampoCanal {
  final String chave;
  final String rotulo;
  final TipoCampoCanal tipo;
  final bool obrigatorio;
  final String ajuda;

  const CampoCanal({
    required this.chave,
    required this.rotulo,
    required this.tipo,
    required this.obrigatorio,
    this.ajuda = '',
  });
}

/// O que um provedor declara de si: a tela monta a configuração por isto.
@immutable
class ProvedorCanal {
  final String id;
  final String tipoCanal;
  final String nome;
  final String descricao;
  final ModoConexao modo;

  /// `estavel`, `experimental` ou `planejado`.
  final String estagio;
  final bool habilitado;
  final String motivoIndisponivel;
  final List<CampoCanal> campos;
  final Set<String> capacidades;

  const ProvedorCanal({
    required this.id,
    required this.tipoCanal,
    required this.nome,
    required this.descricao,
    required this.modo,
    required this.estagio,
    required this.habilitado,
    required this.campos,
    required this.capacidades,
    this.motivoIndisponivel = '',
  });

  /// Pode abrir o fluxo de conexão agora: habilitado no servidor E com um
  /// modo que este app sabe conduzir.
  bool get podeConectar => habilitado && modo.suportadoNoApp;

  /// Texto do motivo quando [podeConectar] é falso.
  String get motivoParaNaoConectar {
    if (!habilitado) {
      return motivoIndisponivel.isEmpty
          ? 'Indisponível neste ambiente.'
          : motivoIndisponivel;
    }
    if (!modo.suportadoNoApp) {
      return 'Esta versão do app ainda não conduz este tipo de conexão. '
          'Atualize o app.';
    }
    return '';
  }
}

/// O que volta de uma conexão por credenciais.
@immutable
class CanalConectado {
  final int id;
  final String nome;
  final String provedor;
  final String telefone;
  final String estado;
  final String webhookUrl;
  final String instrucoes;

  const CanalConectado({
    required this.id,
    required this.nome,
    required this.provedor,
    required this.telefone,
    required this.estado,
    this.webhookUrl = '',
    this.instrucoes = '',
  });
}
