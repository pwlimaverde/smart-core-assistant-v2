import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../domain/model/atividade.dart';
import '../../domain/model/mcp_grant.dart';
import '../controllers/atividade_controller.dart';
import '../controllers/integracoes_controller.dart';

/// Aba "Atividade" — o que os agentes fizeram na conta (B3).
///
/// Mora dentro de Aplicativos conectados, e não num item de menu próprio: a
/// pergunta "o que esse agente fez?" nasce olhando a lista de agentes.
class AbaAtividade extends StatefulWidget {
  const AbaAtividade({super.key});

  @override
  State<AbaAtividade> createState() => _AbaAtividadeState();
}

class _AbaAtividadeState extends State<AbaAtividade> {
  late final AtividadeController _controller;

  static const _periodos = <int, String>{
    7: 'Últimos 7 dias',
    30: 'Últimos 30 dias',
    90: 'Últimos 90 dias',
  };

  @override
  void initState() {
    super.initState();
    _controller = inject<AtividadeController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BlocBuilder<IntegracoesController, ViewState<List<McpGrant>>>(
              bloc: inject<IntegracoesController>(),
              builder: (context, estado) {
                final grants = estado is SuccessState<List<McpGrant>>
                    ? estado.data
                    : const <McpGrant>[];
                return DropdownButton<String?>(
                  value: _controller.grantId,
                  hint: const Text('Todos os aplicativos'),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('Todos os aplicativos'),
                    ),
                    for (final g in grants)
                      DropdownMenuItem<String?>(
                        value: g.id,
                        // Texto de terceiro: `Text` não interpreta marcação,
                        // e o host ao lado é o que a pessoa reconhece.
                        child: Text('${g.clientName} (${g.redirectHost})'),
                      ),
                  ],
                  onChanged: (id) {
                    setState(() {});
                    _controller.definirAplicativo(id);
                  },
                );
              },
            ),
            DropdownButton<int>(
              value: _controller.dias,
              items: [
                for (final p in _periodos.entries)
                  DropdownMenuItem(value: p.key, child: Text(p.value)),
              ],
              onChanged: (dias) {
                if (dias == null) return;
                setState(() {});
                _controller.definirPeriodo(dias);
              },
            ),
            // Um controle só, e só para o admin: quem não é admin vê sempre e
            // apenas os próprios agentes — o servidor impõe isso, e oferecer
            // "tudo" seria prometer o que ele não entrega.
            if (sessaoEhAdmin())
              FilterChip(
                label: const Text('Só agentes'),
                selected: _controller.soAgentes,
                onSelected: (valor) {
                  setState(() {});
                  _controller.definirSoAgentes(valor);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ViewStateBuilder<AtividadeController, List<Atividade>>(
            controller: _controller,
            onError: (context, error) => AppErrorView(
              message: error.message,
              onRetry: _controller.carregar,
            ),
            onSuccess: (context, itens) {
              if (itens.isEmpty) {
                // Vazio não é erro: é a resposta boa para quem acabou de
                // conectar um agente ou nunca conectou nenhum.
                return AppEmptyView(
                  icon: Icons.history_toggle_off,
                  title: _controller.soAgentes
                      ? 'Nenhum agente agiu neste período'
                      : 'Nada aconteceu neste período',
                  subtitle:
                      'Quando um aplicativo conectado fizer algo na sua conta, '
                      'aparece aqui — o quê, quando e em nome de quem.',
                );
              }
              return ListView.separated(
                itemCount: itens.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _Linha(item: itens[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  final Atividade item;

  const _Linha({required this.item});

  @override
  Widget build(BuildContext context) {
    final quando = item.quando;
    final data =
        '${quando.day.toString().padLeft(2, '0')}/'
        '${quando.month.toString().padLeft(2, '0')}/${quando.year} '
        '${quando.hour.toString().padLeft(2, '0')}:'
        '${quando.minute.toString().padLeft(2, '0')}';

    final origem = item.porAgente
        ? (item.aplicativo.isEmpty ? 'Aplicativo conectado' : item.aplicativo)
        : 'Pelo painel';
    final pessoa = item.quem.isEmpty
        ? ''
        : item.porAgente
        ? ' · autorizado por ${item.quem}'
        : ' · ${item.quem}';

    return ListTile(
      leading: Icon(
        item.porAgente ? Icons.smart_toy_outlined : Icons.person_outline,
      ),
      title: Text(item.descricao),
      subtitle: Text('$origem$pessoa · $data'),
    );
  }
}
