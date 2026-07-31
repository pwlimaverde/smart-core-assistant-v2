import 'package:meta/meta.dart';

/// Modelos do wizard de cadastro — dados puros, sem protobuf.
///
/// O módulo inteiro conversa nestes tipos; os stubs gerados param no
/// datasource. É o que permite testar o wizard sem transporte.

/// Resposta da checagem de endereço (slug).
@immutable
final class SlugDisponibilidade {
  final bool disponivel;

  /// Vazia quando disponível. Vem pronta do servidor — a autoridade sobre o que
  /// é um endereço válido é dele, não da tela.
  final String mensagem;

  const SlugDisponibilidade({required this.disponivel, required this.mensagem});
}

/// Um plano oferecido no cadastro.
@immutable
final class PlanoPublico {
  final int id;
  final String nome;
  final String descricao;

  /// Vazio = preço ainda não definido (distinto de "gratuito").
  final String preco;
  final int maxInstancias;
  final int maxDepartamentos;
  final int maxFluxos;

  const PlanoPublico({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.preco,
    required this.maxInstancias,
    required this.maxDepartamentos,
    required this.maxFluxos,
  });
}

/// Como a confirmação chega para um provedor de pagamento.
enum ModoConfirmacaoPagamento {
  /// O provedor decide na própria chamada (voucher).
  imediata,

  /// O usuário sai para pagar e a confirmação chega depois (gateway/webhook).
  assincrona,
}

/// Uma forma de pagamento oferecida, descrita **pelo servidor**.
///
/// A tela não conhece provedor algum por nome: desenha o que vier nesta lista.
/// É o que faz a tela de pagamento sobreviver à entrada de um gateway.
@immutable
final class ProvedorPagamento {
  final String id;
  final String rotulo;
  final String instrucao;
  final bool requerCredencial;
  final String rotuloCredencial;
  final ModoConfirmacaoPagamento modo;

  const ProvedorPagamento({
    required this.id,
    required this.rotulo,
    required this.instrucao,
    required this.requerCredencial,
    required this.rotuloCredencial,
    required this.modo,
  });
}

/// O que o passo 1 devolve: a identidade do cadastro em andamento.
@immutable
final class CadastroIniciado {
  final String tenantId;

  /// Autoriza os passos seguintes. Some quando o cadastro conclui.
  final String signupToken;
  final int proximoPasso;

  const CadastroIniciado({
    required this.tenantId,
    required this.signupToken,
    required this.proximoPasso,
  });
}

/// Desfecho da tentativa de pagamento.
@immutable
final class ResultadoPagamento {
  /// `true` = assinatura ativa; pode seguir para o login.
  final bool confirmado;

  /// Preenchida quando é preciso concluir o pagamento fora do app.
  final String urlRedirecionamento;

  /// Texto a mostrar quando não confirmou (código inválido, expirado...).
  final String mensagem;

  const ResultadoPagamento({
    required this.confirmado,
    required this.urlRedirecionamento,
    required this.mensagem,
  });

  /// `true` quando o provedor mandou o usuário concluir fora do app.
  bool get exigeRedirecionamento => urlRedirecionamento.isNotEmpty;
}

/// Estado corrente do cadastro, para a tela de acompanhamento.
@immutable
final class StatusCadastro {
  final int passo;
  final int planoId;
  final String statusAssinatura;
  final bool tenantAtivo;

  const StatusCadastro({
    required this.passo,
    required this.planoId,
    required this.statusAssinatura,
    required this.tenantAtivo,
  });
}
