import 'package:dependencies_module/dependencies_module.dart';

/// Aba "Excluídos" — o que foi excluído definitivamente na conta
/// (doc_dev/planejamento/39).
///
/// **Somente leitura.** Excluir é definitivo: nada aqui volta, e por isso não
/// há botão de ação. É o registro de quem excluiu o quê e quando — se for
/// preciso de novo, cria-se outro.
class AbaExcluidos extends StatefulWidget {
  /// Substituível nos testes.
  final ExclusaoService? servico;

  const AbaExcluidos({super.key, this.servico});

  @override
  State<AbaExcluidos> createState() => _AbaExcluidosState();
}

class _AbaExcluidosState extends State<AbaExcluidos> {
  late final ExclusaoService _servico = widget.servico ?? ExclusaoService();
  late Future<List<ItemExcluidoDoPainel>> _itens = _servico.listarExcluidos();

  static const _nomes = <String, String>{
    'contato': 'Contato',
    'cliente': 'Cliente',
    'atendimento': 'Conversa',
    'departamento': 'Departamento',
    'fluxo': 'Fluxo',
    'etapa': 'Coluna',
    'atendente': 'Atendente',
    'campo': 'Campo',
    'etiqueta': 'Etiqueta',
    'nota': 'Anotação',
    'intencao': 'Intenção',
    'treinamento': 'Material de treinamento',
    'numero_ignorado': 'Número ignorado',
    'conexao': 'Conexão',
  };

  void _recarregar() {
    setState(() => _itens = _servico.listarExcluidos());
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    final formato = DateFormat('dd/MM/yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Itens excluídos definitivamente. Não podem ser restaurados: '
                'se precisar de novo, crie outro.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: muted),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar excluídos',
              onPressed: _recarregar,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<ItemExcluidoDoPainel>>(
            future: _itens,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return AppErrorView(
                  message: 'Não foi possível carregar os excluídos.',
                  onRetry: _recarregar,
                );
              }
              final itens = snap.data ?? const [];
              if (itens.isEmpty) {
                return const Center(child: Text('Nada foi excluído.'));
              }
              return ListView.separated(
                itemCount: itens.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = itens[i];
                  final quem = item.excluidoPor.isEmpty
                      ? 'pelo sistema'
                      : 'por ${item.excluidoPor}';
                  return ListTile(
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: Text(item.rotulo),
                    subtitle: Text(
                      '${_nomes[item.tipo] ?? item.tipo} · excluído em '
                      '${formato.format(item.excluidoEm)} $quem',
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
