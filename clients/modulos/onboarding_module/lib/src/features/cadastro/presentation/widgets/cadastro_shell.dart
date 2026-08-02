import 'package:dependencies_module/dependencies_module.dart';

/// Rótulos do stepper do CADASTRO (criar a conta).
const rotulosCadastro = ['Empresa', 'Plano', 'Pagamento', 'Pronto'];

/// Rótulos do stepper da CONFIGURAÇÃO inicial (colocar para operar).
///
/// Duas trilhas de quatro em vez de uma de oito: "passo 7 de 8" não diz nada a
/// quem acabou de criar a conta, enquanto "Configuração — WhatsApp, Setor,
/// Assistente, Pronto" mostra o que falta e que é pouco.
const rotulosConfiguracao = ['WhatsApp', 'Setor', 'Assistente', 'Pronto'];

/// Moldura das telas do wizard: logo, stepper e o cartão de conteúdo.
///
/// Centralizar aqui garante que os passos não divirjam visualmente e que o
/// indicador de progresso seja o mesmo objeto em todos.
final class CadastroShell extends StatelessWidget {
  /// Posição na trilha, começando em 1.
  final int passo;
  final String titulo;
  final String subtitulo;
  final Widget child;

  /// Rótulos da trilha. Default: os do cadastro.
  final List<String> rotulos;

  /// Ação de voltar; `null` esconde o botão (primeiro e último passo).
  final VoidCallback? aoVoltar;

  /// Saída do roteiro; `null` esconde o botão.
  ///
  /// Existe para que ninguém fique preso numa etapa que não consegue concluir
  /// — um provedor fora do ar, um código que não chega. Sair não desfaz o que
  /// já foi feito: o progresso está gravado no servidor e o roteiro recomeça de
  /// onde parou no próximo login.
  final VoidCallback? aoSair;

  const CadastroShell({
    super.key,
    required this.passo,
    required this.titulo,
    required this.subtitulo,
    required this.child,
    this.rotulos = rotulosCadastro,
    this.aoVoltar,
    this.aoSair,
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
                  _Stepper(passoAtual: passo, rotulos: rotulos),
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
                  if (aoSair != null) ...[
                    SizedBox(height: aoVoltar == null ? AppSpacing.md : 0),
                    Align(
                      child: TextButton.icon(
                        onPressed: aoSair,
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Sair e continuar depois'),
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

/// Trilha de pontos com o passo corrente destacado.
class _Stepper extends StatelessWidget {
  final int passoAtual;
  final List<String> rotulos;

  const _Stepper({required this.passoAtual, required this.rotulos});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: List.generate(rotulos.length * 2 - 1, (i) {
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
          label: 'Passo $numero de ${rotulos.length}: ${rotulos[numero - 1]}',
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
