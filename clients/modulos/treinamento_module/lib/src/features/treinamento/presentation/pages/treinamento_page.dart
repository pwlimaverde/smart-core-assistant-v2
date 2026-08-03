import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/treinamento.dart';
import '../controllers/treinamento_controllers.dart';
import '../widgets/dialogo_treinamento.dart';

/// Treinamento da IA — o material que o assistente usa para responder.
///
/// Uma tela só, e não as seis da v1: lá o fluxo estava espalhado entre cadastrar,
/// pré-processar e verificar. Aqui a lista é o centro — mostra os três estados
/// do ciclo (rascunho, processando, ativo) — e cadastrar e revisar são diálogos
/// sobre ela. Quem treina quer ver o que a IA já sabe, não navegar entre telas.
final class TreinamentoPage extends StatefulWidget {
  const TreinamentoPage({super.key});

  @override
  State<TreinamentoPage> createState() => _TreinamentoPageState();
}

class _TreinamentoPageState extends State<TreinamentoPage> {
  late final TreinamentoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<TreinamentoController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Treinamento da IA',
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'O que o assistente sabe',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ensinar algo novo'),
                  onPressed: () => abrirCriacao(context, _controller),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cada material vira contexto para as respostas. '
              'Depois de aceito, a IA leva alguns instantes para processá-lo.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.colors.fgMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ViewStateBuilder<TreinamentoController, List<Treinamento>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.carregar,
                ),
                onSuccess: (context, itens) => itens.isEmpty
                    ? const AppEmptyView(
                        title: 'A IA ainda não foi treinada',
                        subtitle: 'Comece ensinando algo que seus clientes '
                            'perguntam com frequência.',
                      )
                    : _Lista(itens: itens, controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  final List<Treinamento> itens;
  final TreinamentoController controller;

  const _Lista({required this.itens, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      // O context do item não abre diálogos: ele é desmontado quando a lista
      // recarrega. Ver `DialogoComCampos` e o histórico do billing.
      itemBuilder: (_, i) => _Linha(item: itens[i], controller: controller),
    );
  }
}

class _Linha extends StatelessWidget {
  final Treinamento item;
  final TreinamentoController controller;

  const _Linha({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final resumo = item.conteudo.length > 140
        ? '${item.conteudo.substring(0, 140)}…'
        : item.conteudo;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.tag,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '· ${item.grupo}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Selo(situacao: item.situacao),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  resumo,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.colors.fgMuted),
                ),
              ],
            ),
          ),
          if (!item.vetorizado)
            IconButton(
              icon: const Icon(Icons.rate_review_outlined),
              tooltip: 'Revisar e enviar para a IA',
              onPressed: () => abrirRevisao(context, item, controller),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover',
            onPressed: () => abrirRemocao(context, item, controller),
          ),
        ],
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  final SituacaoTreinamento situacao;

  const _Selo({required this.situacao});

  @override
  Widget build(BuildContext context) {
    final cor = switch (situacao) {
      SituacaoTreinamento.ativo => context.colors.success,
      SituacaoTreinamento.naFila => Colors.orange,
      SituacaoTreinamento.rascunho => context.colors.fgMuted,
    };

    return Tooltip(
      message: situacao.explicacao,
      child: Container(
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
      ),
    );
  }
}
