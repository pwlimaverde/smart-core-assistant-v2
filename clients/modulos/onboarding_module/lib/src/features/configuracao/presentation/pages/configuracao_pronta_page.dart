import 'package:dependencies_module/dependencies_module.dart';

import '../../../cadastro/presentation/widgets/cadastro_shell.dart';
import '../controllers/configuracao_controllers.dart';

/// Passo 8 — fim do roteiro.
///
/// É aqui que `setup_completed` é gravado no servidor: pagar cria a conta, mas
/// quem coloca o sistema para operar é este roteiro. Enquanto o tenant não
/// chegar nesta tela, ele volta para onde parou ao reabrir o app.
final class ConfiguracaoProntaPage extends StatefulWidget {
  const ConfiguracaoProntaPage({super.key});

  @override
  State<ConfiguracaoProntaPage> createState() => _ConfiguracaoProntaPageState();
}

class _ConfiguracaoProntaPageState extends State<ConfiguracaoProntaPage> {
  late final ConclusaoConfiguracaoController _controller;

  bool _concluindo = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = inject<ConclusaoConfiguracaoController>();
  }

  Future<void> _entrar() async {
    setState(() {
      _concluindo = true;
      _erro = null;
    });

    final res = await _controller.concluir();
    if (!mounted) return;

    switch (res) {
      case Success():
        context.go('/atendimentos');
      case Failure(:final error):
        // Falhar aqui não pode prender o tenant na tela: a conta está ativa e o
        // workspace funciona. O roteiro apenas volta na próxima abertura.
        setState(() {
          _concluindo = false;
          _erro = ErrorMessageMapper.map(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return CadastroShell(
      passo: 4,
      rotulos: rotulosConfiguracao,
      titulo: 'Tudo pronto',
      subtitulo: 'Seu atendimento já pode começar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.rocket_launch_outlined, size: 56, color: colors.accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            'O que ficou para depois pode ser feito a qualquer momento pelas '
            'configurações — inclusive conectar outro número.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
          ),
          if (_erro case final msg?) ...[
            const SizedBox(height: AppSpacing.md),
            CadastroErrorBanner(message: msg),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Ir para os atendimentos',
            isLoading: _concluindo,
            onPressed: _concluindo ? null : _entrar,
          ),
        ],
      ),
    );
  }
}
