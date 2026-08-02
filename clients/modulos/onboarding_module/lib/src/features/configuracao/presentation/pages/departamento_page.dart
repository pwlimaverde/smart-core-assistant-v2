import 'package:dependencies_module/dependencies_module.dart';

import '../../../cadastro/presentation/widgets/cadastro_shell.dart';
import '../controllers/configuracao_controllers.dart';
import '../widgets/sair_do_roteiro.dart';

/// Passo 6 — o primeiro setor de atendimento.
///
/// Um departamento é para onde as conversas vão. Sem nenhum, tudo cai numa fila
/// única — funciona, mas o tenant perde a triagem. Daí o roteiro sugerir um
/// nome pronto: aceitar o padrão é um clique.
final class DepartamentoPage extends StatefulWidget {
  const DepartamentoPage({super.key});

  @override
  State<DepartamentoPage> createState() => _DepartamentoPageState();
}

class _DepartamentoPageState extends State<DepartamentoPage> {
  late final DepartamentoController _controller;
  final _nome = TextEditingController(text: 'Atendimento');

  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = inject<DepartamentoController>();
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });

    final res = await _controller.criar(nome: _nome.text.trim());
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
    if (mounted) context.go('/configuracao/assistente');
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 2,
      rotulos: rotulosConfiguracao,
      titulo: 'Primeiro setor',
      subtitulo: 'Para onde as conversas vão quando chegam.',
      aoVoltar: () => context.go('/configuracao/whatsapp'),
      aoSair: () => sairDoRoteiro(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Nome do setor',
            controller: _nome,
            prefixIcon: Icons.groups_outlined,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _salvando ? null : _salvar(),
          ),
          if (_erro case final msg?) ...[
            const SizedBox(height: AppSpacing.md),
            CadastroErrorBanner(message: msg),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Criar setor',
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
