import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/permissoes.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/cliente.dart';
import '../controllers/clientes_controllers.dart';
import '../widgets/dialogo_cliente.dart';
import '../widgets/dialogo_contatos_do_cliente.dart';

/// B10 (N11 E5) — clientes do tenant (empresas e pessoas) e quem fala por eles.
///
/// Contato é quem manda mensagem; cliente é o cadastro de negócio por trás. Um
/// cliente pode ter vários contatos (a recepção e o financeiro da mesma empresa),
/// e é essa ligação que responde "de que empresa é este número?".
final class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  late final ClientesController _controller;
  final _busca = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = inject<ClientesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  void _aoDigitar(String texto) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _controller.carregar(busca: texto.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeAlterar = sessaoPodeAlterar('/tenant/clientes');
    return AppScaffold(
      title: 'Clientes',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => _controller.carregar(),
        ),
      ],
      floatingActionButton: podeAlterar
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Novo cliente'),
              onPressed: () => abrirCadastroDeCliente(context, _controller),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _busca,
              onChanged: _aoDigitar,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar por nome, razão social ou documento',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            StatefulBuilder(
              builder: (context, setLocal) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar inativos'),
                value: _controller.incluirInativos,
                onChanged: (v) {
                  setLocal(() {});
                  _controller.carregar(incluirInativos: v);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ViewStateBuilder<ClientesController, List<Cliente>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: () => _controller.carregar(),
                ),
                onSuccess: (context, clientes) {
                  if (clientes.isEmpty) {
                    return AppEmptyView(
                      title: _controller.busca.isEmpty
                          ? 'Nenhum cliente ainda'
                          : 'Nada encontrado',
                      subtitle: _controller.busca.isEmpty
                          ? 'Cadastre as empresas e pessoas que compram de você '
                                'e ligue a elas os contatos que falam no '
                                'WhatsApp.'
                          : 'Nenhum cliente casa com "${_controller.busca}".',
                    );
                  }
                  return ListView.separated(
                    itemCount: clientes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LinhaCliente(
                      item: clientes[i],
                      controller: _controller,
                      podeAlterar: podeAlterar,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaCliente extends StatelessWidget {
  final Cliente item;
  final ClientesController controller;
  final bool podeAlterar;

  const _LinhaCliente({
    required this.item,
    required this.controller,
    required this.podeAlterar,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    final d = item.dados;
    final detalhes = [
      if (d.documentoFormatado.isNotEmpty) d.documentoFormatado,
      if (d.localidade.isNotEmpty) d.localidade,
      item.contatos == 1 ? '1 contato' : '${item.contatos} contatos',
    ].join(' · ');

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            child: Icon(
              d.pessoaFisica ? Icons.person_outline : Icons.business_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        d.nomeFantasia,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!item.ativo) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Inativo',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
                if (d.razaoSocial.isNotEmpty && d.razaoSocial != d.nomeFantasia)
                  Text(
                    d.razaoSocial,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  detalhes,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.contacts_outlined),
            tooltip: 'Contatos do cliente',
            onPressed: () => abrirContatosDoCliente(
              context,
              item,
              controller,
              podeAlterar: podeAlterar,
            ),
          ),
          if (podeAlterar) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => abrirEdicaoDeCliente(context, item, controller),
            ),
            IconButton(
              icon: Icon(
                item.ativo
                    ? Icons.visibility_off_outlined
                    : Icons.restore_from_trash_outlined,
              ),
              tooltip: item.ativo ? 'Tirar da lista' : 'Devolver à lista',
              onPressed: () =>
                  controller.definirAtivo(id: item.id, ativo: !item.ativo),
            ),
          ],
        ],
      ),
    );
  }
}
