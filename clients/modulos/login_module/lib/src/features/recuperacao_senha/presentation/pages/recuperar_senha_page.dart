// `hide AuthService`: o dependencies_module reexporta o AuthService fino.
import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

import '../../domain/parameters/recuperacao_parameters.dart';
import '../../domain/usecases/recuperacao_usecases.dart';
import 'moldura_da_recuperacao.dart';

/// Tela pública "Esqueci minha senha" — `/recuperar-senha` (N11 E8).
///
/// Depois de enviar, a tela diz a mesma coisa exista a conta ou não. Parece
/// menos útil do que "e-mail não encontrado", e é de propósito: essa frase
/// entregaria a qualquer um a lista de quem tem conta aqui.
class RecuperarSenhaPage extends StatefulWidget {
  const RecuperarSenhaPage({super.key});

  @override
  State<RecuperarSenhaPage> createState() => _RecuperarSenhaPageState();
}

class _RecuperarSenhaPageState extends State<RecuperarSenhaPage> {
  final _login = TextEditingController();
  bool _enviando = false;
  bool _enviado = false;
  String? _erro;

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(() => _erro = 'Informe o e-mail ou o usuário da sua conta.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });

    final resultado = await inject<SolicitarRedefinicaoUsecase>()(
      SolicitarRedefinicaoParameters(login: login),
    );
    if (!mounted) return;

    setState(() {
      _enviando = false;
      switch (resultado) {
        case Success():
          _enviado = true;
        case Failure(:final error):
          _erro = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return MolduraDaRecuperacao(
      titulo: 'Esqueci minha senha',
      children: [
        if (_enviado) ...[
          Icon(Icons.mark_email_read_outlined, size: 48, color: colors.accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Se houver uma conta com esse e-mail ou usuário, enviamos um link '
            'para escolher uma senha nova. Ele vale por 1 hora.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Não chegou? Confira a caixa de spam antes de pedir de novo.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colors.fgMuted),
          ),
        ] else ...[
          Text(
            'Informe o e-mail ou o usuário da sua conta. Mandaremos um link '
            'para você escolher uma senha nova.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'E-mail ou Usuário',
            controller: _login,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.person_outline,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _enviando ? null : _enviar(),
          ),
          if (_erro case final erro?) ...[
            const SizedBox(height: AppSpacing.md),
            AvisoDeErro(mensagem: erro),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Enviar link',
            isLoading: _enviando,
            onPressed: _enviando ? null : _enviar,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _enviando ? null : () => context.go('/login'),
          child: const Text('Voltar ao login'),
        ),
      ],
    );
  }
}
