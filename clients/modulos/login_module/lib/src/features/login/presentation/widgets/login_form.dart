import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/session.dart';
import '../controllers/login_controller.dart';

/// Formulário de login. Mantém-se visível em todos os estados; o estado de
/// `loading` desabilita o botão e o `error` resolve uma mensagem amigável via
/// [ErrorMessageMapper]. NÃO loga credenciais.
final class LoginForm extends StatefulWidget {
  final LoginController controller;

  /// Rota do autocadastro. Quando presente, a tela oferece "criar conta".
  ///
  /// Existe porque este módulo serve os **dois** apps: no do tenant, quem
  /// acabou de instalar o programa não tem conta e precisa de um caminho
  /// visível para criá-la — não há URL para digitar num app de desktop. No
  /// painel do superusuário não há autocadastro, e o link seria um beco sem
  /// saída.
  final String? rotaDeCadastro;

  const LoginForm({
    super.key,
    required this.controller,
    this.rotaDeCadastro,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() =>
      widget.controller.signIn(_email.text.trim(), _password.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return BlocBuilder<LoginController, ViewState<Session>>(
      bloc: widget.controller,
      builder: (context, state) {
        final loading = state is LoadingState<Session>;
        final erro = state is ErrorState<Session>
            ? ErrorMessageMapper.map(state.error)
            : null;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: AppLogo(height: 96)),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Painel administrativo',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.fgMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      label: 'E-mail ou Usuário',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.person_outline,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Senha',
                      controller: _password,
                      obscureText: true,
                      obscureToggle: true,
                      prefixIcon: Icons.lock_outline,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => loading ? null : _submit(),
                    ),
                    if (erro != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorBanner(message: erro),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Entrar',
                      isLoading: loading,
                      onPressed: loading ? null : _submit,
                    ),
                    if (widget.rotaDeCadastro case final rota?) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Divider(color: colors.divider),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Primeira vez por aqui?',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.fgMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: loading ? null : () => context.go(rota),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: colors.accent),
                          foregroundColor: colors.accent,
                        ),
                        child: const Text('Criar conta da minha empresa'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Banner de erro em superfície suave (token `dangerSoft`).
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.dangerSoft,
        borderRadius: AppRadius.md,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
