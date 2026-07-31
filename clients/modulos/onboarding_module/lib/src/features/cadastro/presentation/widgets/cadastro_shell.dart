import 'package:dependencies_module/dependencies_module.dart';

/// Moldura das quatro telas do wizard: logo, stepper e o cartão de conteúdo.
///
/// Centralizar aqui garante que os passos não divirjam visualmente e que o
/// indicador de progresso seja o mesmo objeto em todos.
final class CadastroShell extends StatelessWidget {
  /// 1..4
  final int passo;
  final String titulo;
  final String subtitulo;
  final Widget child;

  /// Ação de voltar; `null` esconde o botão (passo 1 e passo final).
  final VoidCallback? aoVoltar;

  const CadastroShell({
    super.key,
    required this.passo,
    required this.titulo,
    required this.subtitulo,
    required this.child,
    this.aoVoltar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return AppScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(child: AppLogo(height: 72)),
                  const SizedBox(height: AppSpacing.lg),
                  _Stepper(passoAtual: passo),
                  const SizedBox(height: AppSpacing.lg),
                  Text(titulo, style: textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitulo,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.fgMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  child,
                  if (aoVoltar != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      child: TextButton.icon(
                        onPressed: aoVoltar,
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Voltar'),
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
}

/// Trilha de quatro pontos com o passo corrente destacado.
class _Stepper extends StatelessWidget {
  static const _rotulos = ['Empresa', 'Plano', 'Pagamento', 'Pronto'];

  final int passoAtual;

  const _Stepper({required this.passoAtual});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: List.generate(_rotulos.length * 2 - 1, (i) {
        // Índices ímpares são as linhas entre os pontos.
        if (i.isOdd) {
          final anterior = i ~/ 2 + 1;
          return Expanded(
            child: Container(
              height: 2,
              color: anterior < passoAtual ? colors.accent : colors.divider,
            ),
          );
        }
        final numero = i ~/ 2 + 1;
        final concluido = numero < passoAtual;
        final atual = numero == passoAtual;
        return Semantics(
          label: 'Passo $numero de 4: ${_rotulos[numero - 1]}',
          selected: atual,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: concluido || atual ? colors.accent : colors.inputBg,
              border: Border.all(
                color: concluido || atual ? colors.accent : colors.border,
              ),
            ),
            child: concluido
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : Text(
                    '$numero',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: atual ? Colors.white : colors.fgMuted,
                    ),
                  ),
          ),
        );
      }),
    );
  }
}

/// Banner de erro em superfície suave — mesmo desenho do formulário de login.
final class CadastroErrorBanner extends StatelessWidget {
  final String message;

  const CadastroErrorBanner({super.key, required this.message});

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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
