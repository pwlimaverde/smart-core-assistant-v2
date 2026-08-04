import 'package:meta/meta.dart';

/// Quem fala com o tenant pelo WhatsApp.
@immutable
class Contato {
  final int id;
  final String telefone;

  /// Nome cadastrado. Vazio quando o contato só existe porque mandou mensagem.
  final String nomeContato;

  /// Como a pessoa se identifica no WhatsApp — muitas vezes o único nome que
  /// se tem dela.
  final String nomePerfilWhatsapp;
  final String email;
  final bool ativo;
  final DateTime ultimaInteracao;
  final DateTime cadastradoEm;

  const Contato({
    required this.id,
    required this.telefone,
    required this.nomeContato,
    required this.nomePerfilWhatsapp,
    required this.email,
    required this.ativo,
    required this.ultimaInteracao,
    required this.cadastradoEm,
  });

  /// O melhor nome disponível, nesta ordem: cadastrado, perfil do WhatsApp,
  /// telefone. Nunca vazio — uma linha sem identificação nenhuma seria pior
  /// que o número cru.
  String get exibicao {
    if (nomeContato.trim().isNotEmpty) return nomeContato.trim();
    if (nomePerfilWhatsapp.trim().isNotEmpty) {
      return nomePerfilWhatsapp.trim();
    }
    return telefone.isEmpty ? 'Sem identificação' : telefone;
  }

  /// `true` quando só se conhece o número. Sinaliza o contato que entrou pelo
  /// WhatsApp e nunca foi cadastrado — é ele que o operador precisa completar.
  bool get semNome =>
      nomeContato.trim().isEmpty && nomePerfilWhatsapp.trim().isEmpty;
}
