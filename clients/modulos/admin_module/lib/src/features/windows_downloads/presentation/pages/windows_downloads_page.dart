import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:web/web.dart' as web;

import '../../../../shared/widgets/admin_drawer.dart';
import '../../domain/model/windows_download_link.dart';
import '../controllers/windows_downloads_controller.dart';

/// Tela "Instalador Windows" do painel do superusuário (P11).
///
/// O link só é emitido quando a pessoa pede: cada pedido gera um ticket de 5
/// minutos e uma linha de auditoria (`release_download_link_issued`). Gerar na
/// abertura da tela auditaria visitas, não downloads.
class WindowsDownloadsPage extends StatefulWidget {
  const WindowsDownloadsPage({super.key});

  @override
  State<WindowsDownloadsPage> createState() => _WindowsDownloadsPageState();
}

class _WindowsDownloadsPageState extends State<WindowsDownloadsPage> {
  late final WindowsDownloadsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<WindowsDownloadsController>();
  }

  void _baixar(WindowsDownloadLink link) {
    if (!link.validoEm()) {
      // Ticket venceu com a tela aberta: pede outro em vez de levar a um 401.
      _controller.gerarLink();
      return;
    }
    if (kIsWeb) {
      web.window.open(link.url, '_blank');
    }
  }

  Future<void> _copiarSha(WindowsDownloadLink link) async {
    await Clipboard.setData(ClipboardData(text: link.sha256));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('SHA-256 copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Instalador Windows',
      drawer: const AdminDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child:
              ViewStateBuilder<WindowsDownloadsController, WindowsDownloadLink>(
                controller: _controller,
                onInitial: (context) =>
                    _Apresentacao(onGerar: _controller.gerarLink),
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.gerarLink,
                ),
                onSuccess: (context, link) => _Detalhes(
                  link: link,
                  onBaixar: () => _baixar(link),
                  onCopiarSha: () => _copiarSha(link),
                  onGerarOutro: _controller.gerarLink,
                ),
              ),
        ),
      ),
    );
  }
}

class _Apresentacao extends StatelessWidget {
  final VoidCallback onGerar;

  const _Apresentacao({required this.onGerar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Smart Core Tenant para Windows',
          style: tema.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Canal beta. O link gerado vale por 5 minutos e fica registrado na '
          'auditoria. O Windows pode exibir o aviso do SmartScreen: o instalador '
          'ainda não tem assinatura de código.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onGerar,
          icon: const Icon(Icons.link),
          label: const Text('Gerar link de download'),
        ),
      ],
    );
  }
}

class _Detalhes extends StatelessWidget {
  final WindowsDownloadLink link;
  final VoidCallback onBaixar;
  final VoidCallback onCopiarSha;
  final VoidCallback onGerarOutro;

  const _Detalhes({
    required this.link,
    required this.onBaixar,
    required this.onCopiarSha,
    required this.onGerarOutro,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final expira = DateTime.fromMillisecondsSinceEpoch(link.expiresAtMs);
    final hora =
        '${expira.hour.toString().padLeft(2, '0')}:'
        '${expira.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Versão ${link.version}', style: tema.textTheme.headlineSmall),
        const SizedBox(height: 16),
        _Linha(rotulo: 'Arquivo', valor: link.fileName),
        _Linha(rotulo: 'Tamanho', valor: link.tamanhoFormatado),
        Row(
          children: [
            Expanded(
              child: _Linha(rotulo: 'SHA-256', valor: link.sha256Curto),
            ),
            IconButton(
              tooltip: 'Copiar SHA-256 completo',
              icon: const Icon(Icons.copy),
              onPressed: onCopiarSha,
            ),
          ],
        ),
        _Linha(rotulo: 'Link válido até', valor: hora),
        if (link.releaseNotesMd.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Notas da versão', style: tema.textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(link.releaseNotesMd),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onBaixar,
              icon: const Icon(Icons.download),
              label: const Text('Baixar instalador'),
            ),
            OutlinedButton.icon(
              onPressed: onGerarOutro,
              icon: const Icon(Icons.refresh),
              label: const Text('Gerar novo link'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  final String rotulo;
  final String valor;

  const _Linha({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              rotulo,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(valor)),
        ],
      ),
    );
  }
}
