import 'package:meta/meta.dart';

/// P13 — quem está do outro lado da conversa, para o cabeçalho.
@immutable
final class ContatoDaConversa {
  final int contatoId;
  final String nome;
  final String telefone;

  /// URL do CDN do WhatsApp, assinada e com validade. Vazia = sem foto.
  final String fotoUrl;

  final String email;
  final String nomePerfilWhatsapp;
  final String cargo;
  final String segmento;
  final String observacoes;

  /// 0 = sem cliente vinculado.
  final int clienteId;
  final String clienteNome;

  const ContatoDaConversa({
    required this.contatoId,
    required this.nome,
    required this.telefone,
    required this.fotoUrl,
    this.email = '',
    this.nomePerfilWhatsapp = '',
    this.cargo = '',
    this.segmento = '',
    this.observacoes = '',
    this.clienteId = 0,
    this.clienteNome = '',
  });

  String get nomeParaExibir => nome.isNotEmpty
      ? nome
      : telefone.isNotEmpty
      ? telefone
      : 'Contato #$contatoId';
}

/// Cadastro completo do cliente (PF ou PJ), como a ficha do atendimento edita.
@immutable
final class ClienteDaConversa {
  final int id;
  final String nomeFantasia;
  final String razaoSocial;

  /// `pj`, `pf` ou vazio.
  final String tipo;
  final String cnpj;
  final String cpf;
  final String telefone;
  final String site;
  final String segmento;
  final String cargoResponsavel;
  final String observacoes;
  final String cep;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String uf;

  const ClienteDaConversa({
    required this.id,
    this.nomeFantasia = '',
    this.razaoSocial = '',
    this.tipo = '',
    this.cnpj = '',
    this.cpf = '',
    this.telefone = '',
    this.site = '',
    this.segmento = '',
    this.cargoResponsavel = '',
    this.observacoes = '',
    this.cep = '',
    this.logradouro = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
  });
}
