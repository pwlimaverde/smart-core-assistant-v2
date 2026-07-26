import 'package:dependencies_module/dependencies_module.dart'
    hide AcceptedTenantUser;

import '../../domain/model/accepted_tenant_user.dart';
import '../controllers/accept_invite_controller.dart';

/// Tela PÚBLICA (sem sessão) de aceite de convite. Recebe o `token` via query
/// param da URL (`/aceitar-convite?token=...`). Após aceitar, o usuário ainda
/// precisa fazer login normalmente (`AcceptInvite` não retorna tokens de
/// sessão) — só cria a conta/vínculo.
class AcceptInvitePage extends StatefulWidget {
  const AcceptInvitePage({super.key});

  @override
  State<AcceptInvitePage> createState() => _AcceptInvitePageState();
}

class _AcceptInvitePageState extends State<AcceptInvitePage> {
  late final AcceptInviteController _controller;
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = inject<AcceptInviteController>();
  }

  @override
  Widget build(BuildContext context) {
    final token = GoRouterState.of(context).uri.queryParameters['token'] ?? '';

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Aceitar convite',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (token.isEmpty)
                    const Text(
                      'Link de convite inválido: token ausente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red),
                    )
                  else ...[
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Nome de usuário',
                      hint: 'ex: maria.silva',
                      controller: _usernameController,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'E-mail',
                      hint: 'ex: maria@empresa.com',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Senha',
                      hint: 'mínimo 8 caracteres',
                      controller: _passwordController,
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    ViewStateBuilder<
                      AcceptInviteController,
                      AcceptedTenantUser
                    >(
                      controller: _controller,
                      onInitial: (_) => _buildSubmitButton(token),
                      onLoading: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      onError: (context, error) => Column(
                        children: [
                          Text(
                            error.message,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          _buildSubmitButton(token),
                        ],
                      ),
                      onSuccess: (context, _) => Column(
                        children: [
                          const Text(
                            'Conta criada! Agora faça login com sua senha.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.green),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Ir para o login',
                            onPressed: () => context.go('/login'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(String token) {
    return PrimaryButton(
      label: 'Criar conta',
      onPressed: () {
        final username = _usernameController.text.trim();
        final email = _emailController.text.trim();
        final password = _passwordController.text;
        if (username.isEmpty || email.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preencha todos os campos.')),
          );
          return;
        }
        _controller.accept(
          token: token,
          username: username,
          email: email,
          password: password,
        );
      },
    );
  }
}
