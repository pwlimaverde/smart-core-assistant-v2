import 'package:meta/meta.dart';

/// P13 — quem está do outro lado da conversa, para o cabeçalho.
@immutable
final class ContatoDaConversa {
  final int contatoId;
  final String nome;
  final String telefone;

  /// URL do CDN do WhatsApp, assinada e com validade. Vazia = sem foto.
  final String fotoUrl;

  const ContatoDaConversa({
    required this.contatoId,
    required this.nome,
    required this.telefone,
    required this.fotoUrl,
  });

  String get nomeParaExibir => nome.isNotEmpty
      ? nome
      : telefone.isNotEmpty
      ? telefone
      : 'Contato #$contatoId';
}
