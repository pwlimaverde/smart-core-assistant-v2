import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/conexoes_controllers.dart';

/// Diálogo de pareamento: mostra o QR e espera o celular lê-lo.
///
/// Existe porque a tela de conexões prometia "leia o QR code se ele aparecer" e
/// não havia onde ele aparecesse — uma conexão que caía não tinha como voltar
/// sem refazer o onboarding, que só roda uma vez.
///
/// O ciclo é o mesmo do passo 5 do roteiro inicial: consulta o estado de tempos
/// em tempos, desenha o QR que o provedor devolveu e fecha sozinho quando o
/// pareamento conclui.
Future<void> mostrarPareamento(
  BuildContext context, {
  required ConexoesController controller,
  required int id,
  required String nome,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PareamentoDialog(
        controller: controller,
        id: id,
        nome: nome,
      ),
    );

class _PareamentoDialog extends StatefulWidget {
  final ConexoesController controller;
  final int id;
  final String nome;

  const _PareamentoDialog({
    required this.controller,
    required this.id,
    required this.nome,
  });

  @override
  State<_PareamentoDialog> createState() => _PareamentoDialogState();
}

class _PareamentoDialogState extends State<_PareamentoDialog> {
  /// O QR do provedor gira a cada ~20s; 3s dá sensação de tempo real sem
  /// martelar a API.
  static const _intervalo = Duration(seconds: 3);

  Timer? _poll;
  String _qr = '';
  bool _conectado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    // A primeira consulta sai já: esperar 3s para desenhar o primeiro quadro
    // faria a caixa nascer vazia sem motivo.
    unawaited(_consultar());
    _poll = Timer.periodic(_intervalo, (_) => _consultar());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _consultar() async {
    final res = await widget.controller.consultarPareamento(widget.id);
    if (!mounted) return;

    switch (res) {
      case Success(:final value):
        setState(() {
          _qr = value.qrCode;
          _conectado = value.conectado;
          _erro = null;
        });
        if (value.conectado) {
          _poll?.cancel();
          // A lista atrás do diálogo ainda mostra "desconectada"; recarregar
          // aqui evita que o usuário feche e veja o estado velho.
          unawaited(widget.controller.carregar());
        }
      // Uma consulta que falha não derruba a espera: o provedor pode estar
      // subindo a sessão. Mostra o motivo e continua tentando.
      case Failure(:final error):
        setState(() => _erro = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text('Conectar "${widget.nome}"'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _conectado
              ? [
                  Icon(Icons.check_circle_outline, size: 56,
                      color: colors.success),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'WhatsApp conectado. As mensagens já chegam ao sistema.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
                  ),
                ]
              : [
                  Text(
                    'No celular, abra o WhatsApp › Aparelhos conectados › '
                    'Conectar aparelho, e aponte para o código.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: colors.fgMuted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Qr(base64: _qr),
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
                      Flexible(
                        child: Text(
                          _erro ?? 'Aguardando a leitura...',
                          style: textTheme.bodySmall?.copyWith(
                            color: _erro == null ? colors.fgMuted : colors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_conectado ? 'Fechar' : 'Cancelar'),
        ),
      ],
    );
  }
}

/// Desenha o QR que o provedor devolveu.
///
/// A evolution-go manda a imagem pronta em base64, às vezes com o prefixo
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

  /// `null` quando ainda não há QR ou o conteúdo não é decodificável — a caixa
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
