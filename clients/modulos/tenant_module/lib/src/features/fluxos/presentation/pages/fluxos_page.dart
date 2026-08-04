import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/fluxo.dart';
import '../controllers/fluxos_controllers.dart';
import '../widgets/dialogo_fluxo.dart';

/// Fluxos de atendimento.
///
/// O fluxo é o quadro por onde a conversa anda; cada departamento pode ter os
/// seus. A camada de banco existia desde o começo — o roteamento já procurava a
/// etapa de entrada —, mas nada criava fluxo nenhum: todo tenant dependia de um
/// registro semeado à mão.
final class FluxosPage extends StatefulWidget {
  const FluxosPage({super.key});

  @override
  State<FluxosPage> createState() => _FluxosPageState();
}

class _FluxosPageState extends State<FluxosPage> {
  late final FluxosController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<FluxosController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Fluxos de atendimento',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cada fluxo é um quadro de colunas por onde as conversas '
                    'de um departamento andam.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.colors.fgMuted),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo fluxo'),
                  onPressed: () => abrirCriacaoFluxo(context, _controller),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ViewStateBuilder<FluxosController, List<Fluxo>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.carregar,
                ),
                onSuccess: (context, fluxos) => fluxos.isEmpty
                    ? const AppEmptyView(
                        title: 'Nenhum fluxo ainda',
                        subtitle: 'Sem fluxo, as conversas que chegam não têm '
                            'quadro onde entrar.',
                      )
                    : ListView.separated(
                        itemCount: fluxos.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _LinhaFluxo(
                          item: fluxos[i],
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

class _LinhaFluxo extends StatelessWidget {
  final Fluxo item;
  final FluxosController controller;

  const _LinhaFluxo({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

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
                    Flexible(
                      child: Text(
                        item.nome,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (!item.ativo)
                      _Etiqueta(texto: 'Inativo', cor: muted)
                    else if (item.semEtapas)
                      // Quadro sem coluna não recebe conversa: o roteamento
                      // procura a etapa de entrada e não acha.
                      const _Etiqueta(texto: 'Sem colunas', cor: Colors.orange),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    item.departamentoNome,
                    '${item.etapas} coluna(s)',
                    if (item.atendimentosAbertos > 0)
                      '${item.atendimentosAbertos} em aberto',
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
          TextButton.icon(
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: const Text('Colunas'),
            onPressed: () => context.go('/tenant/fluxos/${item.id}/etapas'),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () => abrirEdicaoFluxo(context, item, controller),
          ),
          if (item.ativo)
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: item.podeDesativar
                  ? 'Desativar'
                  : 'Tem conversa em aberto neste fluxo',
              // Desabilitar e explicar no tooltip, em vez de deixar clicar para
              // o servidor recusar: o motivo já é conhecido aqui.
              onPressed: item.podeDesativar
                  ? () => abrirDesativacaoFluxo(context, item, controller)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color cor;

  const _Etiqueta({required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cor,
        ),
      ),
    );
  }
}
