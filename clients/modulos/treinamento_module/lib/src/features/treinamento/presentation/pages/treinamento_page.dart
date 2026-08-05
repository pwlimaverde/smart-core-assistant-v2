import 'package:dependencies_module/dependencies_module.dart';

import '../../../ensaio/presentation/widgets/aba_ensaio.dart';
import '../../../intents/presentation/widgets/aba_intents.dart';
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
  /// Menu lateral do app hospedeiro. Sem ele esta tela também era um beco sem
  /// saída — o mesmo defeito do quadro de atendimento.
  final Widget? drawer;

  const TreinamentoPage({this.drawer, super.key});

  @override
  State<TreinamentoPage> createState() => _TreinamentoPageState();
}

class _TreinamentoPageState extends State<TreinamentoPage>
    with SingleTickerProviderStateMixin {
  late final TreinamentoController _controller;
  late final TabController _abas;

  @override
  void initState() {
    super.initState();
    _controller = inject<TreinamentoController>();
    _abas = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  void dispose() {
    _abas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Treinamento da IA',
      drawer: widget.drawer,
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
            // Duas faces do mesmo trabalho: o material diz o que a IA SABE, a
            // intenção diz o que ela FAZ. Separá-las em telas esconderia que
            // uma resposta ruim pode vir de qualquer uma das duas.
            TabBar(
              controller: _abas,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).hintColor,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.menu_book_outlined), text: 'Material'),
                Tab(icon: Icon(Icons.alt_route), text: 'Intenções'),
                // A terceira responde a pergunta que as duas primeiras deixam
                // no ar: "isso que eu cadastrei funcionou?".
                Tab(icon: Icon(Icons.science_outlined), text: 'Testar'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: TabBarView(
                controller: _abas,
                children: [
                  _AbaMaterial(controller: _controller),
                  const AbaIntents(),
                  const AbaEnsaio(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AbaMaterial extends StatelessWidget {
  final TreinamentoController controller;

  const _AbaMaterial({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  onPressed: () => abrirCriacao(context, controller),
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
                controller: controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: controller.carregar,
                ),
                onSuccess: (context, itens) => itens.isEmpty
                    ? const AppEmptyView(
                        title: 'A IA ainda não foi treinada',
                        subtitle: 'Comece ensinando algo que seus clientes '
                            'perguntam com frequência.',
                      )
                    : _Lista(itens: itens, controller: controller),
              ),
            ),
      ],
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
