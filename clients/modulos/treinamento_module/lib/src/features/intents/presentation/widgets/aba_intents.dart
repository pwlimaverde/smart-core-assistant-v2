import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/intent.dart';
import '../controllers/intents_controllers.dart';
import 'dialogo_intent.dart';

/// Intenções cadastradas — o que a IA **faz** quando a pergunta se parece com
/// um exemplo.
///
/// Vive numa aba da tela de treinamento, ao lado do material: uma resposta ruim
/// pode vir de qualquer um dos dois, e separá-los em telas esconderia isso de
/// quem está tentando corrigir.
class AbaIntents extends StatefulWidget {
  const AbaIntents({super.key});

  @override
  State<AbaIntents> createState() => _AbaIntentsState();
}

class _AbaIntentsState extends State<AbaIntents> {
  late final IntentsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<IntentsController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Quando a pergunta se parecer com o exemplo, a IA passa a '
                'seguir o comportamento descrito.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.colors.fgMuted),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Nova intenção'),
              onPressed: () => abrirCriacaoIntent(context, _controller),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ViewStateBuilder<IntentsController, List<IntentIa>>(
            controller: _controller,
            onError: (context, error) => AppErrorView(
              message: error.message,
              onRetry: _controller.carregar,
            ),
            onSuccess: (context, itens) => itens.isEmpty
                ? const AppEmptyView(
                    title: 'Nenhuma intenção cadastrada',
                    subtitle: 'Use uma intenção quando a IA precisar AGIR de '
                        'um jeito específico — transferir, pedir um dado, '
                        'recusar — e não apenas saber uma informação.',
                  )
                : ListView.separated(
                    itemCount: itens.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    // O context do item não abre diálogos: ele é desmontado
                    // quando a lista recarrega.
                    itemBuilder: (_, i) =>
                        _Linha(item: itens[i], controller: _controller),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  final IntentIa item;
  final IntentsController controller;

  const _Linha({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

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
                    Flexible(
                      child: Text(
                        item.tag,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Enquanto não está vetorizada, a intenção existe no
                    // cadastro e não existe para a IA. Sem dizer isso, alguém
                    // cadastra, testa e conclui que o sistema não funciona.
                    if (item.vetorizada)
                      const _Etiqueta(texto: 'Ativa', cor: Colors.green)
                    else
                      const _Etiqueta(
                        texto: 'Processando',
                        cor: Colors.orange,
                      ),
                    if (item.grupo.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Etiqueta(texto: item.grupo, cor: muted),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.descricao,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (item.exemplo.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'ex: "${item.exemplo}"',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: muted, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () => abrirEdicaoIntent(context, item, controller),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover',
            onPressed: () => abrirRemocaoIntent(context, item, controller),
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
