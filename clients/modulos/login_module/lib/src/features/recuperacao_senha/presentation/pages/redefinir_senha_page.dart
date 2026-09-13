// `hide AuthService`: o dependencies_module reexporta o AuthService fino.
import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

import '../../domain/parameters/recuperacao_parameters.dart';
import '../../domain/usecases/recuperacao_usecases.dart';
import 'moldura_da_recuperacao.dart';

/// Tela pública do link do e-mail — `/redefinir-senha?token=…` (N11 E8).
class RedefinirSenhaPage extends StatefulWidget {
  const RedefinirSenhaPage({super.key});

  @override
  State<RedefinirSenhaPage> createState() => _RedefinirSenhaPageState();
}

class _RedefinirSenhaPageState extends State<RedefinirSenhaPage> {
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _enviando = false;
  bool _trocada = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _trocar(String token) async {
    final senha = _senha.text;
    // As duas regras que a tela consegue conferir sozinha ficam aqui: gastar
    // uma ida ao servidor — e uma tentativa do limite por IP — para descobrir
    // que as senhas não batem seria só atrasar a pessoa.
    if (senha.length < 8) {
      setState(() => _erro = 'A senha precisa ter ao menos 8 caracteres.');
      return;
    }
    if (senha != _confirmacao.text) {
      setState(() => _erro = 'As duas senhas não são iguais.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });

    final resultado = await inject<RedefinirSenhaUsecase>()(
      RedefinirSenhaParameters(token: token, novaSenha: senha),
    );
    if (!mounted) return;

    setState(() {
      _enviando = false;
      switch (resultado) {
        case Success():
          _trocada = true;
        case Failure(:final error):
          _erro = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final token = GoRouterState.of(context).uri.queryParameters['token'] ?? '';
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;

    if (token.isEmpty) {
      return MolduraDaRecuperacao(
        titulo: 'Link incompleto',
        children: [
          Text(
            'Este endereço chegou sem o código do e-mail. Abra de novo o link '
            'que enviamos, ou peça outro.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Pedir um link novo',
            onPressed: () => context.go('/recuperar-senha'),
          ),
        ],
      );
    }

    if (_trocada) {
      return MolduraDaRecuperacao(
        titulo: 'Senha trocada',
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: colors.success),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pronto. Entre com a senha nova. Por segurança, as sessões abertas '
            'em outros aparelhos foram encerradas.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Ir para o login',
            onPressed: () => context.go('/login'),
          ),
        ],
      );
    }

    return MolduraDaRecuperacao(
      titulo: 'Escolha uma senha nova',
      children: [
        AppTextField(
          label: 'Senha nova',
          hint: 'mínimo 8 caracteres',
          controller: _senha,
          obscureText: true,
          obscureToggle: true,
          prefixIcon: Icons.lock_outline,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Repita a senha nova',
          controller: _confirmacao,
          obscureText: true,
          obscureToggle: true,
          prefixIcon: Icons.lock_outline,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _enviando ? null : _trocar(token),
        ),
        if (_erro case final erro?) ...[
          const SizedBox(height: AppSpacing.md),
          AvisoDeErro(mensagem: erro),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Trocar senha',
          isLoading: _enviando,
          onPressed: _enviando ? null : () => _trocar(token),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _enviando ? null : () => context.go('/login'),
          child: const Text('Voltar ao login'),
        ),
      ],
    );
  }
}
