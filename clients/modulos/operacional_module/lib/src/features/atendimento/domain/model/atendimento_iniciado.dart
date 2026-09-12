import 'package:flutter/foundation.dart';

/// O que volta de "iniciar atendimento".
///
/// [jaExistia] não é detalhe de implementação: vale a invariante de um
/// atendimento ativo por contato, e quando já há conversa aberta com aquela
/// pessoa o servidor devolve a que existe em vez de criar a segunda. A tela
/// precisa saber a diferença — dizer "atendimento criado" ao abrir um que já
/// estava lá faria o operador procurar um cartão novo que não existe.
@immutable
class AtendimentoIniciado {
  final int atendimentoId;
  final bool jaExistia;

  const AtendimentoIniciado({
    required this.atendimentoId,
    required this.jaExistia,
  });
}
