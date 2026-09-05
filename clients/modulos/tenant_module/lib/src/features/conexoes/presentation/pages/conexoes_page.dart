import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/conexao.dart';
import '../controllers/conexoes_controllers.dart';
import '../widgets/pareamento_dialog.dart';

/// Conexões de WhatsApp do tenant.
///
/// Existe porque o onboarding cria a primeira conexão e depois disso não havia
/// mais nada: uma conexão que caísse deixava o tenant sem saída — sem ver o
/// estado, sem reconectar, sem trocar de aparelho.
final class ConexoesPage extends StatefulWidget {
  const ConexoesPage({super.key});

  @override
  State<ConexoesPage> createState() => _ConexoesPageState();
}

class _ConexoesPageState extends State<ConexoesPage> {
  late final ConexoesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<ConexoesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Conexões de WhatsApp',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_link),
          tooltip: 'Nova conexão',
          onPressed: () => _novaConexao(context),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ViewStateBuilder<ConexoesController, List<Conexao>>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.carregar,
          ),
          onSuccess: (context, itens) => itens.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppEmptyView(
                      title: 'Nenhuma conexão',
                      subtitle: 'Conecte um WhatsApp para começar a receber '
                          'mensagens dos seus clientes.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Sem este botão o tenant que remove a última conexão fica
                    // sem saída: o roteiro inicial, que criava a primeira, só
                    // roda uma vez.
                    SizedBox(
                      width: 260,
                      child: PrimaryButton(
                        label: 'Conectar WhatsApp',
                        onPressed: () => _novaConexao(context),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: itens.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  // O context do item não abre diálogos: ele é desmontado
                  // quando a lista recarrega.
                  itemBuilder: (_, i) => _Linha(
                    conexao: itens[i],
                    controller: _controller,
                    abrirPareamento: _abrirPareamento,
                  ),
                ),
        ),
      ),
    );
  }

  /// A caixa de pareamento é aberta a partir da PÁGINA, não da linha da lista:
  /// a linha é desmontada assim que a lista recarrega, e o `context` dela morre
  /// junto — a página sobrevive à volta toda.
  Future<void> _abrirPareamento(int id, String nome) async {
    if (!mounted) return;
    await mostrarPareamento(
      context,
      controller: _controller,
      id: id,
      nome: nome,
    );
  }

  /// Cria a conexão e emenda direto no pareamento: o nome sozinho não serve de
  /// nada — sem ler o QR em seguida a instância nasce e fica pendurada.
  Future<void> _novaConexao(BuildContext context) async {
    final nome = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => DialogoComCampos(
        campos: [nome],
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nova conexão'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Dê um nome para identificar este aparelho — por exemplo, '
                  '"atendimento" ou "vendas".',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: nome,
                  label: 'Nome da conexão',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final texto = nome.text.trim();
    if (texto.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await _controller.criar(texto);
    if (!context.mounted) return;

    switch (res) {
      case Success(:final value):
        await _abrirPareamento(value.id, value.nome);
      case Failure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _Linha extends StatelessWidget {
  final Conexao conexao;
  final ConexoesController controller;

  /// Aberta pela página: ver `_abrirPareamento`.
  final Future<void> Function(int id, String nome) abrirPareamento;

  const _Linha({
    required this.conexao,
    required this.controller,
    required this.abrirPareamento,
  });

  @override
  Widget build(BuildContext context) {
    final situacao = conexao.situacao;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      conexao.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Selo(situacao: situacao),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  conexao.telefone.isEmpty
                      ? situacao.explicacao
                      : '${conexao.telefone} · ${situacao.explicacao}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.colors.fgMuted),
                ),
              ],
            ),
          ),
          // Reconectar só faz sentido quando não está conectada — oferecer no
          // estado bom convidaria a derrubar uma conexão que funciona.
          if (situacao != SituacaoConexao.conectada)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconectar',
              onPressed: () => _reconectar(context),
            ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Remover conexão',
            onPressed: () => _remover(context),
          ),
        ],
      ),
    );
  }

  Future<void> _reconectar(BuildContext context) async {
    // Resolvido antes do await: reconectar recarrega a lista e desmonta esta
    // linha antes de a resposta chegar — inclusive o `context` dela.
    final messenger = ScaffoldMessenger.of(context);
    final res = await controller.reconectar(conexao.id);

    switch (res) {
      // A sessão pode voltar sozinha (o aparelho ainda está pareado) ou exigir
      // um QR novo. Como não dá para saber antes, abre a caixa de pareamento:
      // se o provedor reconectar sem código, ela mesma anuncia e fecha.
      case Success():
        await abrirPareamento(conexao.id, conexao.nome);
      case Failure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _remover(BuildContext context) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remover "${conexao.nome}"?'),
        content: const Text(
          'As mensagens já recebidas continuam no histórico, mas esta conexão '
          'para de receber novas. Isto não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await controller.remover(conexao.id);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          switch (res) {
            Success() => 'Conexão removida.',
            Failure(:final error) => error.message,
          },
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final SituacaoConexao situacao;

  const _Selo({required this.situacao});

  @override
  Widget build(BuildContext context) {
    final cor = switch (situacao) {
      SituacaoConexao.conectada => context.colors.success,
      SituacaoConexao.conectando => Colors.orange,
      SituacaoConexao.desconectada => Theme.of(context).colorScheme.error,
      SituacaoConexao.desconhecida => context.colors.fgMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        situacao.rotulo,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cor,
        ),
      ),
    );
  }
}
