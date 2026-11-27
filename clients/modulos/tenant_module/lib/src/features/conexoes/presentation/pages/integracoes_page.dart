import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/provedor_canal.dart';
import '../controllers/integracoes_controller.dart';
import '../widgets/formulario_do_provedor_dialog.dart';

/// Integrações: os provedores de canal que o servidor declara, cada um com o
/// fluxo de conexão que o PRÓPRIO DESCRITOR pede.
///
/// Nada aqui é escrito para um provedor: o cartão mostra nome, descrição,
/// estágio e capacidades vindos do servidor, e o botão abre o fluxo do
/// `modo` — QR (o pareamento que a tela de conexões já conduz) ou
/// credenciais (o formulário gerado pelos campos do descritor). Um provedor
/// novo no servidor aparece aqui sem mudar o app; um modo novo (OAuth, trecho
/// de código) aparece como "atualize o app" até o app aprender o fluxo.
///
/// Abre por cima da tela de conexões e devolve:
/// - o provedor, quando o fluxo é QR: quem chamou conduz o pareamento, porque a
///   caixa do QR vive na página de conexões;
/// - `null` nos demais casos (cancelou, ou já conectou por credenciais).
Future<ProvedorCanal?> abrirIntegracoes(BuildContext context) =>
    Navigator.of(context).push<ProvedorCanal>(
      MaterialPageRoute(builder: (_) => const IntegracoesPage()),
    );

final class IntegracoesPage extends StatefulWidget {
  const IntegracoesPage({super.key});

  @override
  State<IntegracoesPage> createState() => _IntegracoesPageState();
}

class _IntegracoesPageState extends State<IntegracoesPage> {
  late final IntegracoesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<IntegracoesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  Future<void> _conectar(ProvedorCanal provedor) async {
    switch (provedor.modo) {
      case ModoConexao.qrPairing:
        Navigator.of(context).pop(provedor);
      case ModoConexao.token:
        final conectado = await mostrarFormularioDoProvedor(
          context,
          controller: _controller,
          provedor: provedor,
        );
        if (conectado == null || !mounted) return;
        await _mostrarConectado(conectado);
        if (mounted) Navigator.of(context).pop();
      case ModoConexao.oauth ||
          ModoConexao.embedded ||
          ModoConexao.copySnippet ||
          ModoConexao.desconhecido:
        // O botão já fica desabilitado; a guarda cobre quem chamar direto.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(provedor.motivoParaNaoConectar)));
    }
  }

  Future<void> _mostrarConectado(CanalConectado c) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Conexão criada'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.telefone.isEmpty
                  ? '"${c.nome}" foi conectada.'
                  : '"${c.nome}" foi conectada ao número ${c.telefone}.',
            ),
            if (c.instrucoes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(c.instrucoes),
            ],
            if (c.webhookUrl.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SelectableText(c.webhookUrl),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Integrações',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ViewStateBuilder<IntegracoesController, List<ProvedorCanal>>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.carregar,
          ),
          onSuccess: (context, provedores) => provedores.isEmpty
              ? const AppEmptyView(
                  title: 'Nenhum provedor disponível',
                  subtitle: 'O servidor não declarou nenhum canal.',
                )
              : ListView.separated(
                  itemCount: provedores.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => CartaoDoProvedor(
                    provedor: provedores[i],
                    onConectar: () => _conectar(provedores[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Rótulos das capacidades que valem mostrar ao tenant. Vocabulário fechado do
/// contrato; capacidade sem rótulo aqui simplesmente não aparece.
const _rotulosDeCapacidade = <String, String>{
  'qr_pairing': 'QR code',
  'token_connect': 'Token de acesso',
  'envio_texto': 'Texto',
  'envio_midia': 'Mídia',
  'recibos': 'Confirmação de leitura',
  'reacoes': 'Reações',
  'presenca': 'Digitando…',
  'download_midia': 'Recebe mídia',
  'templates': 'Modelos de mensagem',
  'reconexao': 'Religa sozinho',
};

String _rotuloDoEstagio(String estagio) => switch (estagio) {
  'estavel' => 'Disponível',
  'experimental' => 'Em desenvolvimento',
  'planejado' => 'Em breve',
  _ => estagio,
};

String _rotuloDoModo(ModoConexao modo) => switch (modo) {
  ModoConexao.qrPairing => 'Conectar com QR code',
  ModoConexao.token => 'Conectar com credenciais',
  ModoConexao.oauth => 'Conectar com login',
  ModoConexao.embedded => 'Conectar',
  ModoConexao.copySnippet => 'Gerar código',
  ModoConexao.desconhecido => 'Conectar',
};

/// Um provedor do catálogo.
final class CartaoDoProvedor extends StatelessWidget {
  final ProvedorCanal provedor;
  final VoidCallback onConectar;

  const CartaoDoProvedor({
    super.key,
    required this.provedor,
    required this.onConectar,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted);
    final capacidades = [
      for (final e in _rotulosDeCapacidade.entries)
        if (provedor.capacidades.contains(e.key)) e.value,
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provedor.nome,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(label: Text(_rotuloDoEstagio(provedor.estagio))),
            ],
          ),
          const SizedBox(height: 4),
          Text(provedor.descricao, style: muted),
          if (capacidades.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in capacidades)
                  Chip(label: Text(c), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: provedor.podeConectar
                    ? const SizedBox.shrink()
                    : Text(provedor.motivoParaNaoConectar, style: muted),
              ),
              FilledButton(
                key: ValueKey('conectar-${provedor.id}'),
                onPressed: provedor.podeConectar ? onConectar : null,
                child: Text(_rotuloDoModo(provedor.modo)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
