import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/session.dart';
import '../controllers/login_controller.dart';

/// Formulário de login. Mantém-se visível em todos os estados; o estado de
/// `loading` desabilita o botão e o `error` resolve uma mensagem amigável via
/// [ErrorMessageMapper]. NÃO loga credenciais.
final class LoginForm extends StatefulWidget {
  final LoginController controller;

  const LoginForm({super.key, required this.controller});

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
    return BlocBuilder<LoginController, ViewState<Session>>(
      bloc: widget.controller,
      builder: (context, state) {
        final loading = state is LoadingState<Session>;
        final erro =
            state is ErrorState<Session> ? ErrorMessageMapper.map(state.error) : null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Smart Core Admin',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                AppTextField(
                  label: 'E-mail ou Usuário',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Senha',
                  controller: _password,
                  obscureText: true,
                ),
                if (erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    erro,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Entrar',
                  isLoading: loading,
                  onPressed: loading ? null : _submit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
