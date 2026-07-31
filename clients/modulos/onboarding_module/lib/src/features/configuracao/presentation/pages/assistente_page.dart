import 'package:dependencies_module/dependencies_module.dart';

import '../../../cadastro/presentation/widgets/cadastro_shell.dart';
import '../controllers/configuracao_controllers.dart';

/// Passo 7 — como o assistente se apresenta.
///
/// É o passo que mais muda a percepção do cliente final: a persona é o que
/// define o tom das respostas. Vem com um texto pronto porque partir de uma
/// página em branco trava — e ajustar depois é fácil, pelo painel.
final class AssistentePage extends StatefulWidget {
  const AssistentePage({super.key});

  @override
  State<AssistentePage> createState() => _AssistentePageState();
}

class _AssistentePageState extends State<AssistentePage> {
  static const _personaSugerida =
      'Você é um assistente cordial e objetivo. Responda em português do '
      'Brasil, com frases curtas. Quando não souber algo com certeza, diga que '
      'vai verificar e transfira para um atendente humano.';

  late final PersonaController _controller;
  final _nome = TextEditingController(text: 'Assistente');
  final _persona = TextEditingController(text: _personaSugerida);

  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = inject<PersonaController>();
  }

  @override
  void dispose() {
    _nome.dispose();
    _persona.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });

    final res = await _controller.definir(
      persona: _persona.text.trim(),
      nomeDoAgente: _nome.text.trim(),
    );
    if (!mounted) return;

    switch (res) {
      case Success():
        await _avancar();
      case Failure(:final error):
        setState(() {
          _salvando = false;
          _erro = ErrorMessageMapper.map(error);
        });
    }
  }

  Future<void> _avancar() async {
    await _controller.registrarAvanco();
    if (mounted) context.go('/configuracao/pronto');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CadastroShell(
      passo: 3,
      rotulos: rotulosConfiguracao,
      titulo: 'Seu assistente',
      subtitulo: 'Como ele se apresenta e responde aos seus clientes.',
      aoVoltar: () => context.go('/configuracao/departamento'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Nome do assistente',
            controller: _nome,
            prefixIcon: Icons.smart_toy_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _persona,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Como ele deve se comportar',
              alignLabelWithHint: true,
              helperText: 'Dá para ajustar quando quiser, pelas configurações.',
              helperStyle: TextStyle(color: colors.fgSubtle),
            ),
          ),
          if (_erro case final msg?) ...[
            const SizedBox(height: AppSpacing.md),
            CadastroErrorBanner(message: msg),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Salvar',
            isLoading: _salvando,
            onPressed: _salvando ? null : _salvar,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            child: TextButton(
              onPressed: _salvando ? null : _avancar,
              child: const Text('Fazer isso depois'),
            ),
          ),
        ],
      ),
    );
  }
}
