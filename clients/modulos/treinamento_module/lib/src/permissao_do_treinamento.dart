/// Se a sessão pode alterar o treinamento (B2).
///
/// Este módulo não conhece a sessão — quem sabe dela é o `login_module`, e o
/// treinamento não pode depender do painel do tenant. Quem compõe o app entrega
/// a pergunta pronta pelo [TreinamentoModule]. Sem ninguém entregar (os testes
/// deste módulo), tudo fica liberado: a barreira de verdade é o servidor.
abstract final class PermissaoDoTreinamento {
  static bool Function() podeAlterar = _sempre;

  static bool _sempre() => true;

  /// Volta ao padrão. Só para teste.
  static void restaurar() => podeAlterar = _sempre;
}
