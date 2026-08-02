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
///
/// A espera é **limitada**. A versão anterior consultava para sempre e tratava
/// qualquer erro como "ainda não confirmou": quando a consulta passou a falhar
/// de verdade, a tela ficou em "aguardando" indefinidamente com a conta já
/// ativa, e o cliente não tinha como saber se o dinheiro dele tinha virado
/// alguma coisa. Passado o limite, a tela para de girar e oferece as duas
/// saídas: tentar entrar na conta (o cadastro pode estar pronto mesmo com a
/// consulta falhando) ou cancelar.
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

  /// Quantas consultas antes de assumir que algo está errado. Com voucher a
  /// primeira já responde ativo; com gateway, dois minutos cobrem folgadamente
  /// o webhook. Passar disso não é lentidão, é problema.
  static const _maxTentativas = 24;

  late final ConclusaoController _controller;
  Timer? _poll;
  int _tentativas = 0;
  bool _desistiu = false;
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
      _consultar();
      _poll = Timer.periodic(_intervalo, (_) => _consultarSePendente());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _consultar() {
    _tentativas++;
    _controller.consultar();
  }

  void _consultarSePendente() {
    final state = _controller.state;
    if (state is SuccessState<StatusCadastro> && state.data.tenantAtivo) {
      _poll?.cancel();
      return;
    }
    if (_tentativas >= _maxTentativas) {
      _poll?.cancel();
      if (mounted) setState(() => _desistiu = true);
      return;
    }
    _consultar();
  }

  /// Retoma a espera do ponto em que parou — a sessão do wizard continua na
  /// memória, então não há nada a refazer.
  void _tentarDeNovo() {
    setState(() {
      _desistiu = false;
      _tentativas = 0;
      _erroLogin = null;
    });
    _consultar();
    _poll?.cancel();
    _poll = Timer.periodic(_intervalo, (_) => _consultarSePendente());
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
        _poll?.cancel();
        context.go('/configuracao/whatsapp');
      case Failure(:final error):
        setState(() {
          _entrando = false;
          _erroLogin = ErrorMessageMapper.map(error);
        });
    }
  }

  /// Abandona o cadastro. A conta criada continua existindo no servidor — se o
  /// pagamento passou, dá para entrar por `/login` depois. Por isso o texto
  /// fala em "sair", e não em "apagar".
  void _cancelar() {
    _poll?.cancel();
    inject<CadastroSessao>().encerrar();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 4,
      titulo: 'Tudo pronto',
      subtitulo: 'Sua conta está sendo liberada.',
      child: BlocBuilder<ConclusaoController, ViewState<StatusCadastro>>(
        bloc: _controller,
        builder: (context, state) {
          if (state case SuccessState(:final data) when data.tenantAtivo) {
            return _Liberada(
              entrando: _entrando,
              erro: _erroLogin,
              onEntrar: _entrar,
            );
          }
          // Enquanto há tentativas pela frente, um erro isolado não é notícia:
          // com gateway, a confirmação chega por webhook e a próxima consulta
          // encontra. O que não pode é isso durar para sempre.
          if (!_desistiu) return const _Aguardando();

          return _Impasse(
            detalhe: switch (state) {
              ErrorState(:final error) => ErrorMessageMapper.map(error),
              _ => 'O pagamento ainda não aparece como confirmado.',
            },
            erroLogin: _erroLogin,
            entrando: _entrando,
            onTentarDeNovo: _tentarDeNovo,
            onEntrar: _entrar,
            onCancelar: _cancelar,
          );
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

/// A espera estourou. Diz o que se sabe e oferece as três saídas — nenhuma
/// delas é ficar olhando para a tela.
class _Impasse extends StatelessWidget {
  final String detalhe;
  final String? erroLogin;
  final bool entrando;
  final VoidCallback onTentarDeNovo;
  final VoidCallback onEntrar;
  final VoidCallback onCancelar;

  const _Impasse({
    required this.detalhe,
    required this.erroLogin,
    required this.entrando,
    required this.onTentarDeNovo,
    required this.onEntrar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline, size: 48, color: colors.danger),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Não conseguimos confirmar o estado da sua conta.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          detalhe,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.fgMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Se o pagamento já foi aceito, sua conta pode estar pronta mesmo '
          'assim — vale tentar entrar.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.fgMuted),
        ),
        if (erroLogin case final msg?) ...[
          const SizedBox(height: AppSpacing.md),
          CadastroErrorBanner(message: msg),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Continuar de onde parei',
          isLoading: entrando,
          onPressed: entrando ? null : onEntrar,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: entrando ? null : onTentarDeNovo,
          child: const Text('Verificar de novo'),
        ),
        TextButton(
          onPressed: entrando ? null : onCancelar,
          child: const Text('Cancelar e sair'),
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
