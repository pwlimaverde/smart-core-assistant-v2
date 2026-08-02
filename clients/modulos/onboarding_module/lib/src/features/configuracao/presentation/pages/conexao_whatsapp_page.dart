import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dependencies_module/dependencies_module.dart';

import '../../../cadastro/presentation/widgets/cadastro_shell.dart';
import '../../domain/model/configuracao_models.dart';
import '../controllers/configuracao_controllers.dart';
import '../widgets/sair_do_roteiro.dart';

/// Passo 5 — conectar o WhatsApp.
///
/// É o único passo sem o qual o sistema não faz nada. Ainda assim dá para
/// adiar: parear exige o celular em mãos, e quem instala o programa nem sempre
/// é quem tem o telefone. Adiar registra o progresso do mesmo jeito, e o
/// roteiro volta aqui na próxima abertura.
final class ConexaoWhatsappPage extends StatefulWidget {
  const ConexaoWhatsappPage({super.key});

  @override
  State<ConexaoWhatsappPage> createState() => _ConexaoWhatsappPageState();
}

class _ConexaoWhatsappPageState extends State<ConexaoWhatsappPage> {
  /// Intervalo entre consultas do pareamento. O QR do Evolution costuma girar
  /// a cada ~20s; 3s dá a sensação de tempo real sem martelar o provedor.
  static const _intervalo = Duration(seconds: 3);

  late final ConexaoController _controller;
  final _nome = TextEditingController();

  Timer? _poll;
  bool _criando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = inject<ConexaoController>();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    setState(() {
      _criando = true;
      _erro = null;
    });

    final res = await _controller.criar(_nome.text.trim());
    if (!mounted) return;

    switch (res) {
      case Success():
        setState(() => _criando = false);
        await _controller.consultar();
        // A partir daqui a tela vive do polling: o QR aparece, o usuário lê
        // com o celular, e o estado vira `connected` sozinho.
        _poll = Timer.periodic(_intervalo, (_) => _tick());
      case Failure(:final error):
        setState(() {
          _criando = false;
          _erro = ErrorMessageMapper.map(error);
        });
    }
  }

  Future<void> _tick() async {
    await _controller.consultar();
    if (!mounted) return;
    if (_controller.conectado) {
      _poll?.cancel();
    }
  }

  Future<void> _avancar() async {
    await _controller.registrarAvanco();
    if (mounted) context.go('/configuracao/departamento');
  }

  @override
  Widget build(BuildContext context) {
    return CadastroShell(
      passo: 1,
      rotulos: rotulosConfiguracao,
      titulo: 'Conectar o WhatsApp',
      subtitulo: 'É por aqui que as mensagens dos seus clientes chegam.',
      aoSair: () => sairDoRoteiro(context),
      child: BlocBuilder<ConexaoController, ViewState<EstadoConexao>>(
        bloc: _controller,
        builder: (context, state) {
          // Antes de criar a conexão não há o que consultar: a tela pede o nome.
          if (_controller.instanciaId == null) {
            return _FormularioNome(
              controller: _nome,
              criando: _criando,
              erro: _erro,
              onCriar: _criar,
              onPular: _avancar,
            );
          }

          final conectado = state is SuccessState<EstadoConexao> &&
              state.data.conectado;
          if (conectado) {
            return _Conectado(onContinuar: _avancar);
          }

          final qr = state is SuccessState<EstadoConexao>
              ? state.data.qrCode
              : '';
          return _AguardandoPareamento(qrBase64: qr, onPular: _avancar);
        },
      ),
    );
  }
}

class _FormularioNome extends StatelessWidget {
  final TextEditingController controller;
  final bool criando;
  final String? erro;
  final VoidCallback onCriar;
  final VoidCallback onPular;

  const _FormularioNome({
    required this.controller,
    required this.criando,
    required this.erro,
    required this.onCriar,
    required this.onPular,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Nome desta conexão',
          controller: controller,
          prefixIcon: Icons.smartphone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => criando ? null : onCriar(),
        ),
        if (erro case final msg?) ...[
          const SizedBox(height: AppSpacing.md),
          CadastroErrorBanner(message: msg),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Gerar QR Code',
          isLoading: criando,
          onPressed: criando ? null : onCriar,
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          child: TextButton(
            onPressed: criando ? null : onPular,
            child: const Text('Fazer isso depois'),
          ),
        ),
      ],
    );
  }
}

class _AguardandoPareamento extends StatelessWidget {
  final String qrBase64;
  final VoidCallback onPular;

  const _AguardandoPareamento({required this.qrBase64, required this.onPular});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No celular, abra o WhatsApp › Aparelhos conectados › '
          'Conectar aparelho, e aponte para o código.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(child: _Qr(base64: qrBase64)),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Aguardando a leitura...',
              style: textTheme.bodySmall?.copyWith(color: colors.fgMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          child: TextButton(
            onPressed: onPular,
            child: const Text('Fazer isso depois'),
          ),
        ),
      ],
    );
  }
}

/// Desenha o QR que o provedor devolveu.
///
/// O Evolution manda uma imagem pronta em base64, às vezes com o prefixo
/// `data:image/png;base64,`. Não geramos o QR aqui — só exibimos.
class _Qr extends StatelessWidget {
  final String base64;

  const _Qr({required this.base64});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = _decodificar(base64);

    if (bytes == null) {
      // Nos primeiros segundos o provedor ainda não gerou o código.
      return Container(
        width: 240,
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.inputBg,
          borderRadius: AppRadius.md,
          border: Border.all(color: colors.border),
        ),
        child: const CircularProgressIndicator(),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.md,
        border: Border.all(color: colors.border),
      ),
      child: Image.memory(bytes, width: 240, height: 240, gaplessPlayback: true),
    );
  }

  /// `null` quando ainda não há QR ou o conteúdo não é decodificável — a tela
  /// mostra o indicador de espera em vez de quebrar.
  static Uint8List? _decodificar(String valor) {
    if (valor.isEmpty) return null;
    final limpo = valor.contains(',') ? valor.split(',').last : valor;
    try {
      return base64Decode(limpo);
    } on FormatException {
      return null;
    }
  }
}

class _Conectado extends StatelessWidget {
  final VoidCallback onContinuar;

  const _Conectado({required this.onContinuar});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 56, color: colors.success),
        const SizedBox(height: AppSpacing.md),
        Text(
          'WhatsApp conectado. As mensagens já chegam ao sistema.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.fgMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Continuar', onPressed: onContinuar),
      ],
    );
  }
}
