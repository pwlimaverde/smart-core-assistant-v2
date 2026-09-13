import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

/// O cartão centralizado das telas de recuperação — o mesmo desenho do login.
///
/// Quem chega aqui pelo link de um e-mail precisa reconhecer o produto antes de
/// digitar uma senha: uma tela com outra cara é exatamente o que se ensina a
/// desconfiar.
class MolduraDaRecuperacao extends StatelessWidget {
  final String titulo;
  final List<Widget> children;

  const MolduraDaRecuperacao({
    super.key,
    required this.titulo,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(
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
                  const Align(child: AppLogo(height: 72)),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa de erro em superfície suave, igual à do login.
class AvisoDeErro extends StatelessWidget {
  final String mensagem;

  const AvisoDeErro({super.key, required this.mensagem});

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
              mensagem,
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
