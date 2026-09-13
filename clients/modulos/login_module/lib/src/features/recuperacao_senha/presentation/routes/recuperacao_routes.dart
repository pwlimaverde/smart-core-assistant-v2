import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

import '../pages/recuperar_senha_page.dart';
import '../pages/redefinir_senha_page.dart';

/// Rotas PÚBLICAS da recuperação de senha (N11 E8). Os dois apps as recebem
/// pelo `LoginModule`, e os dois guards precisam deixá-las passar sem sessão —
/// quem esqueceu a senha, por definição, não está logado.
///
/// Sem `binds`: os usecases são globais (ver `LoginModule.globalBinds`), e as
/// telas não têm controller próprio.
final class RecuperarSenhaRoute extends GetItModule {
  @override
  String get path => '/recuperar-senha';

  @override
  Widget get page => const RecuperarSenhaPage();

  @override
  void binds(Injector i) {}
}

final class RedefinirSenhaRoute extends GetItModule {
  @override
  String get path => '/redefinir-senha';

  @override
  Widget get page => const RedefinirSenhaPage();

  @override
  void binds(Injector i) {}
}
