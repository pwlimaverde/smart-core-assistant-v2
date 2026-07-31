import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/cadastro_models.dart';
import '../../domain/services/cadastro_sessao.dart';
import '../controllers/cadastro_controllers.dart';
import '../widgets/cadastro_shell.dart';

/// Passo 4 — conclusão.
///
/// Duas situações chegam aqui: o pagamento já confirmado (voucher, imediato) ou
/// um pagamento em curso fora do app (gateway). A tela trata as duas com o mesmo
/// código: consulta o estado e, enquanto não estiver ativo, repete a consulta.
final class CadastroProntoPage extends StatefulWidget {
  const CadastroProntoPage({super.key});

  @override
  State<CadastroProntoPage> createState() => _CadastroProntoPageState();
}

class _CadastroProntoPageState extends State<CadastroProntoPage> {
  /// Espaçamento entre consultas enquanto o pagamento não confirma. Cinco
  /// segundos é curto o bastante para não parecer travado e longo o bastante
  /// para não martelar uma rota pública.
  static const _intervalo = Duration(seconds: 5);

  late final ConclusaoController _controller;
  Timer? _poll;
  bool _entrando = false;
  String? _erroLogin;

  @override
  void initState() {
    super.initState();
    _controller = inject<ConclusaoController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!inject<CadastroSessao>().iniciado) {
        if (mounted) context.go('/cadastro');
        return;
      }
      _controller.consultar();
      _poll = Timer.periodic(_intervalo, (_) => _consultarSePendente());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _consultarSePendente() {
    final state = _controller.state;
    if (state is SuccessState<StatusCadastro> && state.data.tenantAtivo) {
      _poll?.cancel();
      return;
    }
    _controller.consultar();
  }

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erroLogin = null;
    });
    final res = await _controller.entrar();
    if (!mounted) return;

    switch (res) {
      // A conta está criada, mas nada opera ainda: o roteiro continua na
      // configuração inicial. Ir direto ao workspace deixaria o tenant diante
      // de uma tela vazia, sem WhatsApp conectado.
      case Success():
        context.go('/configuracao/whatsapp');
      case Failure(:final error):
        setState(() {
          _entrando = false;
          _erroLogin = ErrorMessageMapper.map(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 4,
      titulo: 'Tudo pronto',
      subtitulo: 'Sua conta está sendo liberada.',
      child: BlocBuilder<ConclusaoController, ViewState<StatusCadastro>>(
        bloc: _controller,
        builder: (context, state) => switch (state) {
          SuccessState(:final data) when data.tenantAtivo => _Liberada(
              entrando: _entrando,
              erro: _erroLogin,
              onEntrar: _entrar,
            ),
          // Erro de consulta não é o fim: o pagamento pode ter sido confirmado
          // mesmo assim, e a próxima consulta vai descobrir.
          ErrorState() || SuccessState() || LoadingState() || InitialState() =>
            const _Aguardando(),
        },
      ),
    );
  }
}

class _Aguardando extends StatelessWidget {
  const _Aguardando();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
        Text(
          'Aguardando a confirmação do pagamento. Isto pode levar alguns '
          'instantes — deixe esta tela aberta.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.fgMuted),
        ),
      ],
    );
  }
}

class _Liberada extends StatelessWidget {
  final bool entrando;
  final String? erro;
  final VoidCallback onEntrar;

  const _Liberada({
    required this.entrando,
    required this.erro,
    required this.onEntrar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 56, color: colors.success),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Conta liberada. Vamos deixar seu atendimento funcionando — '
          'são mais quatro passos rápidos.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.fgMuted),
        ),
        if (erro case final msg?) ...[
          const SizedBox(height: AppSpacing.md),
          CadastroErrorBanner(message: msg),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Continuar',
          isLoading: entrando,
          onPressed: entrando ? null : onEntrar,
        ),
      ],
    );
  }
}
