import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';
import 'package:onboarding_module/onboarding_module.dart'
    show PortaoConfiguracao;

/// Faixa que avisa que a assinatura está pendente ou suspensa.
///
/// Sem ela o sintoma é "não consigo cadastrar nada", com uma mensagem de erro de
/// banco ("assinatura inadimplente") que não diz o que fazer. A faixa troca isso
/// pela causa e pelo caminho.
///
/// **Dois textos, um por papel.** O dono ganha o botão que leva à tela de
/// pagamento; o colaborador, não — cobrança é assunto de quem responde pela
/// conta, e oferecer a ele um botão que o guard devolve seria pior que não
/// oferecer nada.
///
/// Não consulta o servidor: lê o [PortaoConfiguracao], que já respondeu uma vez
/// por sessão. Um `ListenableBuilder` basta — quando a quitação acontece, o
/// portão notifica e a faixa some sozinha.
final class AvisoAssinatura extends StatelessWidget {
  const AvisoAssinatura({super.key});

  @override
  Widget build(BuildContext context) {
    final portao = inject<PortaoConfiguracao>();

    return ListenableBuilder(
      listenable: portao,
      builder: (context, _) {
        // `null` = ainda não se sabe. Não avisa por suposição.
        if (portao.pagamentoPendente != true) return const SizedBox.shrink();

        final colors = context.colors;
        final suspensa = portao.assinaturaStatus == 'SUSPENDED';
        final ehDono =
            inject<AuthService>().currentSession?.isTenantAdmin ?? false;

        return Material(
          color: colors.warningSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colors.warning),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    suspensa
                        ? 'Assinatura suspensa. Nada será recebido nem enviado '
                              'até regularizar.'
                        : 'Assinatura pendente. Nada será recebido nem enviado '
                              'até regularizar.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (ehDono)
                  FilledButton(
                    onPressed: () => context.go('/conta/pagamento'),
                    child: const Text('Regularizar'),
                  )
                else
                  Text(
                    'Fale com o responsável pela conta.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
