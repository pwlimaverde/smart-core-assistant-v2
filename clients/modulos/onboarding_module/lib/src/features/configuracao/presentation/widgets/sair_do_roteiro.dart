import 'package:dependencies_module/dependencies_module.dart';
import 'package:login_module/login_module.dart' as login;

import '../../domain/services/portao_configuracao.dart';

/// Encerra a sessão e volta ao login, de dentro da configuração guiada.
///
/// Existe para que ninguém fique preso numa etapa que não consegue concluir —
/// um provedor fora do ar, um código que não chega. Não desfaz nada: o
/// progresso está gravado no servidor e o roteiro recomeça de onde parou no
/// próximo login.
///
/// O portão é limpo junto porque a próxima sessão pode ser de outro tenant,
/// com outro progresso.
Future<void> sairDoRoteiro(BuildContext context) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sair da configuração?'),
      content: const Text(
        'Sua conta continua criada e o que você já configurou fica salvo. '
        'Da próxima vez que entrar, o roteiro recomeça deste ponto.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Continuar aqui'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sair'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  // Resolvidos antes do await: o logout reconstrói a árvore.
  final router = GoRouter.of(context);
  inject<PortaoConfiguracao>().limpar();
  await inject<login.AuthService>().logout();
  router.go('/login');
}
