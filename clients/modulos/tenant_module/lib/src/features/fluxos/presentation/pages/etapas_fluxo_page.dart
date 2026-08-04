import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/fluxo.dart';
import '../controllers/fluxos_controllers.dart';
import '../widgets/dialogo_etapa.dart';

/// Colunas de um fluxo.
///
/// A ordem é a do quadro, e é ela que a pessoa vê no Kanban — por isso mover
/// para cima e para baixo está aqui, e não escondido numa edição.
final class EtapasFluxoPage extends StatefulWidget {
  final int fluxoId;

  const EtapasFluxoPage({required this.fluxoId, super.key});

  @override
  State<EtapasFluxoPage> createState() => _EtapasFluxoPageState();
}

class _EtapasFluxoPageState extends State<EtapasFluxoPage> {
  late final EtapasFluxoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<EtapasFluxoController>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.carregar(widget.fluxoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Colunas do fluxo',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => _controller.carregar(widget.fluxoId),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Voltar aos fluxos'),
                  onPressed: () => context.go('/tenant/fluxos'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nova coluna'),
                  onPressed: () => abrirCriacaoEtapa(context, _controller),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ViewStateBuilder<EtapasFluxoController, List<EtapaFluxo>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: () => _controller.carregar(widget.fluxoId),
                ),
                onSuccess: (context, etapas) => etapas.isEmpty
                    ? const AppEmptyView(
                        title: 'Nenhuma coluna',
                        subtitle: 'Sem uma coluna de entrada, conversa nova não '
                            'tem onde cair neste fluxo.',
                      )
                    : ListView.separated(
                        itemCount: etapas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _LinhaEtapa(
                          item: etapas[i],
                          primeira: i == 0,
                          ultima: i == etapas.length - 1,
                          controller: _controller,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaEtapa extends StatelessWidget {
  final EtapaFluxo item;
  final bool primeira;
  final bool ultima;
  final EtapasFluxoController controller;

  const _LinhaEtapa({
    required this.item,
    required this.primeira,
    required this.ultima,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: corDoHex(item.cor),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nome,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    item.tipo.rotulo,
                    if (item.descricao.isNotEmpty) item.descricao,
                  ].join(' · '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Mover para cima',
            onPressed: primeira
                ? null
                : () => controller.mover(id: item.id, paraCima: true),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward),
            tooltip: 'Mover para baixo',
            onPressed: ultima
                ? null
                : () => controller.mover(id: item.id, paraCima: false),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () => abrirEdicaoEtapa(context, item, controller),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover',
            onPressed: () => abrirRemocaoEtapa(context, item, controller),
          ),
        ],
      ),
    );
  }
}
