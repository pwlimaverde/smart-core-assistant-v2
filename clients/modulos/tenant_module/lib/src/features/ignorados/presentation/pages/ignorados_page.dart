import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/numero_ignorado.dart';
import '../controllers/ignorados_controller.dart';

/// Os números que o sistema ignora — a "whitelist" da v1.
///
/// A regra já era aplicada na ingestão desde o começo; o que não existia era
/// meio de ver ou mexer na lista sem abrir o banco. Sem ela, um número que
/// entrou errado ficava ignorado para sempre e ninguém sabia por quê.
final class IgnoradosPage extends StatefulWidget {
  const IgnoradosPage({super.key});

  @override
  State<IgnoradosPage> createState() => _IgnoradosPageState();
}

class _IgnoradosPageState extends State<IgnoradosPage> {
  late final IgnoradosController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<IgnoradosController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  bool get _podeAlterar => sessaoPodeAlterar('/tenant/ignorados');

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Números ignorados',
      drawer: const TenantDrawer(),
      actions: [
        if (_podeAlterar)
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ignorar um número',
            onPressed: () => _editar(context),
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A lista não libera ninguém, ela ignora — e o nome herdado da v1
            // ("whitelist") dizia o contrário. Sem esta linha, alguém acaba
            // cadastrando o melhor cliente aqui achando que o privilegia.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Mensagem destes números não abre atendimento, não aciona a IA '
                'e não recebe pesquisa de satisfação. Serve para o número da '
                'equipe, do contador, do fornecedor — quem escreve mas não é '
                'atendimento.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.fgMuted,
                ),
              ),
            ),
            Expanded(
              child: ViewStateBuilder<IgnoradosController, List<NumeroIgnorado>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.carregar,
                ),
                onSuccess: (context, itens) => itens.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.block,
                        title: 'Nenhum número ignorado',
                        subtitle: 'Todas as mensagens abrem atendimento.',
                      )
                    : ListView.separated(
                        itemCount: itens.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _Linha(
                          item: itens[i],
                          podeAlterar: _podeAlterar,
                          onEditar: () => _editar(context, item: itens[i]),
                          onAlternar: (v) => _alternar(itens[i], v),
                          onRemover: () => _remover(context, itens[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A caixa é aberta a partir da PÁGINA: a linha é desmontada assim que a
  /// lista recarrega, e o `context` dela morre junto.
  Future<void> _editar(BuildContext context, {NumeroIgnorado? item}) async {
    final nome = TextEditingController(text: item?.nome ?? '');
    final telefone = TextEditingController(text: item?.telefone ?? '');
    final messenger = ScaffoldMessenger.of(context);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(item == null ? 'Ignorar um número' : 'Editar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: telefone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Número (com DDD)',
                hintText: '5511999999999',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: nome,
              decoration: const InputDecoration(
                labelText: 'Quem é (opcional)',
                hintText: 'Contador, fornecedor, equipe…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    final numero = telefone.text.trim();
    if (numero.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe o número.')),
      );
      return;
    }

    final erro = item == null
        ? await _controller.criar(nome: nome.text.trim(), telefone: numero)
        : await _controller.atualizar(
            id: item.id,
            nome: nome.text.trim(),
            telefone: numero,
            ativo: item.ativo,
          );
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }

  Future<void> _alternar(NumeroIgnorado item, bool ativo) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await _controller.atualizar(
      id: item.id,
      nome: item.nome,
      telefone: item.telefone,
      ativo: ativo,
    );
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }

  Future<void> _remover(BuildContext context, NumeroIgnorado item) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Remover ${item.telefone}?'),
        // Desligar e remover fazem coisas diferentes, e a caixa é o lugar de
        // dizer isso: quem só quer voltar a atender a pessoa não precisa
        // apagar o registro.
        content: const Text(
          'O número volta a ser atendido e some da lista. Para voltar a '
          'atendê-lo sem perder o registro, desligue em vez de remover.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogo).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    final erro = await _controller.remover(item.id);
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

class _Linha extends StatelessWidget {
  final NumeroIgnorado item;
  final bool podeAlterar;
  final VoidCallback onEditar;
  final ValueChanged<bool> onAlternar;
  final VoidCallback onRemover;

  const _Linha({
    required this.item,
    required this.podeAlterar,
    required this.onEditar,
    required this.onAlternar,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    return ListTile(
      leading: Icon(
        item.ativo ? Icons.block : Icons.check_circle_outline,
        color: item.ativo ? Theme.of(context).colorScheme.error : muted,
      ),
      title: Text(item.telefone),
      subtitle: Text(
        item.nome.isEmpty ? 'Sem identificação' : item.nome,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: item.ativo
                ? 'Ignorando este número'
                : 'Este número é atendido normalmente',
            child: Switch(
              value: item.ativo,
              onChanged: podeAlterar ? onAlternar : null,
            ),
          ),
          if (podeAlterar) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: onEditar,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover da lista',
              onPressed: onRemover,
            ),
          ],
        ],
      ),
    );
  }
}
