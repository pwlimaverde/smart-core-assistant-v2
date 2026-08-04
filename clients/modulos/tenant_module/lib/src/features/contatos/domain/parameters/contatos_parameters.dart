import 'package:return_success_or_error/return_success_or_error.dart';

final class ListarContatosParameters extends Parameters {
  /// Vazio = sem filtro. O servidor casa contra nome, telefone e nome de
  /// perfil do WhatsApp.
  final String busca;

  const ListarContatosParameters({this.busca = ''});
}
