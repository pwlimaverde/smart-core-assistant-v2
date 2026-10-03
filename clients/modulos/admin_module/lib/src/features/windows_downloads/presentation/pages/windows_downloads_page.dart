import 'dart:html' as html;

import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/errors/windows_downloads_errors.dart';
import '../controllers/windows_downloads_controller.dart';
import '../../../../shared/widgets/admin_drawer.dart';

/// Tela para download seguro do instalador Windows (apenas superusuário).
class WindowsDownloadsPage extends StatefulWidget {
  const WindowsDownloadsPage({super.key});

  @override
  State<WindowsDownloadsPage> createState() => _WindowsDownloadsPageState();
}

class _WindowsDownloadsPageState extends State<WindowsDownloadsPage> {
  late final WindowsDownloadsController _controller;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _controller = inject<WindowsDownloadsController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchDownloadLink();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Abre a URL de download em uma nova aba do navegador.
  Future<void> _openDownloadLink() async {
    if (_controller.link == null) return;

    final link = _controller.link!;

    // Valida se o link ainda está válido
    if (!link.isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link expirou. Obtenha um novo link.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // Abre o link em nova aba
    html.window.open(link.url, '_blank');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download iniciado...'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Copia o SHA-256 para a área de transferência.
  Future<void> _copySha256() async {
    if (_controller.link == null) return;

    await Clipboard.setData(ClipboardData(text: _controller.link!.sha256));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SHA-256 copiado para a área de transferência'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  /// Reconecta o link de download.
  Future<void> _refresh() async {
    _controller.reset();
    await _controller.fetchDownloadLink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instalador Windows'),
        centerTitle: true,
      ),
      drawer: const AdminDrawer(),
      body: ValueListenableBuilder<DownloadLinkState>(
        valueListenable: _controller,
        builder: (context, state, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildContent(context, state),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, DownloadLinkState state) {
    switch (state) {
      case DownloadLinkState.initial:
      case DownloadLinkState.loading:
        return _buildLoading(context);
      case DownloadLinkState.success:
        return _buildSuccess(context);
      case DownloadLinkState.failure:
        return _buildError(context);
    }
  }

  Widget _buildLoading(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 48),
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Carregando informações de download...',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final link = _controller.link!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Aviso de beta
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Esta é uma versão BETA. Relate problemas ao suporte.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.amber[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Card principal com informações
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Versão
                _buildInfoRow(
                  context,
                  label: 'Versão',
                  value: link.version,
                ),
                const SizedBox(height: 16),

                // Nome do arquivo
                _buildInfoRow(
                  context,
                  label: 'Arquivo',
                  value: link.fileName,
                ),
                const SizedBox(height: 16),

                // Tamanho
                _buildInfoRow(
                  context,
                  label: 'Tamanho',
                  value: link.formattedSize,
                ),
                const SizedBox(height: 24),

                // SHA-256 com botão de copiar
                Text(
                  'SHA-256',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          link.sha256Short,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _copySha256,
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copiar SHA-256 completo',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Release notes
                if (link.releaseNotesMd.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Release Notes',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          link.releaseNotesMd,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Botões de ação
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isDownloading ? null : _openDownloadLink,
                      icon: const Icon(Icons.download),
                      label: const Text('Baixar Setup.exe'),
                    ),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Atualizar'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Aviso do SmartScreen
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Text(
                    'O Windows SmartScreen pode alertar ao abrir o arquivo. '
                    'Clique em "Mais informações" e depois "Executar assim mesmo".',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final error = _controller.error;
    final theme = Theme.of(context);

    String errorMessage = 'Erro ao carregar informações de download';
    if (error is NotSuperuserError) {
      errorMessage = 'Acesso negado. Apenas administradores podem baixar.';
    } else if (error is InvalidChannelError) {
      errorMessage = 'Canal de release inválido.';
    } else if (error is ReleasesNotConfiguredError) {
      errorMessage = 'Serviço de downloads não está configurado.';
    } else if (error is NoReleaseFoundError) {
      errorMessage = 'Nenhuma release encontrada.';
    } else if (error != null) {
      errorMessage = error.message;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red[400],
        ),
        const SizedBox(height: 24),
        Text(
          'Erro ao carregar download',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          errorMessage,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _refresh,
          child: const Text('Tentar Novamente'),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  /// Widget auxiliar para exibir pares chave-valor.
  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
