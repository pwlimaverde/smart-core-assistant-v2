import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';
import 'package:onboarding_module/onboarding_module.dart'
    show PortaoConfiguracao;

import '../../domain/model/quitacao.dart';
import '../controllers/pagamento_controller.dart';

/// Tela de pagamento **depois do login** — a que faltava.
///
/// A do wizard (`/cadastro/pagamento`) é pública e depende de um `signup_token`
/// que morre com a sessão de cadastro. Quem teve a sessão expirada no meio do
/// cadastro entrava no app, esbarrava em "assinatura inadimplente" a cada
/// operação e não tinha onde resolver. Esta é a saída.
///
/// Visível só para o dono: o guard barra quem não tem `tenant:admin`, o RPC
/// exige o mesmo escopo e o `data_postgres` revalida.
class PagamentoPage extends StatefulWidget {
  const PagamentoPage({super.key});

  @override
  State<PagamentoPage> createState() => _PagamentoPageState();
}

class _PagamentoPageState extends State<PagamentoPage> {
  final _codigo = TextEditingController();

  /// Mensagem exibida **junto do campo**, não em snackbar.
  ///
  /// A recusa de um código é informação que a pessoa relê enquanto digita o
  /// próximo; um snackbar some em segundos e leva a mensagem junto.
  String? _erro;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _quitar() async {
    setState(() => _erro = null);
    final res = await inject<PagamentoController>().quitar(
      credencial: _codigo.text,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final value):
        final Quitacao q = value;
        if (q.confirmado) {
          // Atualiza o portão sem nova consulta: o servidor acabou de
          // responder, e esperar outra ida só atrasaria a navegação.
          inject<PortaoConfiguracao>().quitar();
          if (!mounted) return;
          // O guard reavalia e leva ao roteiro (se ainda houver) ou ao quadro.
          // O destino não se decide aqui.
          context.go('/atendimentos');
          return;
        }
        if (q.exigeSaidaDoApp) {
          setState(() => _erro = 'Conclua o pagamento em: ${q.urlExterna}');
          return;
        }
        setState(
          () => _erro = q.erroLegivel.isNotEmpty
              ? q.erroLegivel
              : 'Não foi possível validar o código.',
        );
      case Failure(:final error):
        setState(() => _erro = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portao = inject<PortaoConfiguracao>();
    final controller = inject<PagamentoController>();
    final plano = portao.planoNome;
    final suspensa = portao.assinaturaStatus == 'SUSPENDED';

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento da assinatura')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  suspensa
                      ? 'Sua assinatura está suspensa'
                      : 'Sua assinatura está pendente',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  // Dizer o que trava é mais útil que dizer que travou: o
                  // sintoma que a pessoa vê é "não consigo cadastrar nada".
                  'Enquanto não for regularizada, não é possível cadastrar '
                  'nem receber mensagens.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (plano.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(Icons.workspace_premium_outlined, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text('Plano: $plano'),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppTextField(
                  label: 'Código de ativação',
                  hint: 'Informe o código recebido',
                  controller: _codigo,
                  errorText: _erro,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _quitar(),
                ),
                const SizedBox(height: AppSpacing.lg),
                BlocBuilder<PagamentoController, ViewState<Quitacao>>(
                  bloc: controller,
                  builder: (context, _) => PrimaryButton(
                    label: 'Ativar assinatura',
                    isLoading: controller.enviando,
                    onPressed: controller.enviando ? null : _quitar,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => inject<AuthService>().logout(),
                  child: const Text('Sair da conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
