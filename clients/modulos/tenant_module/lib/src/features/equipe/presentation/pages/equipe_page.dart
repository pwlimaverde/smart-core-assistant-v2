import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/equipe.dart';
import '../controllers/equipe_controllers.dart';
import '../widgets/dialogo_departamento.dart';

/// Departamentos e atendentes.
///
/// As duas listas na mesma tela de propósito: departamento sem atendente e
/// atendente sem departamento são os dois problemas que fazem a fila parar, e
/// separá-los em telas esconderia justamente a relação entre eles.
final class EquipePage extends StatefulWidget {
  const EquipePage({super.key});

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage>
    with SingleTickerProviderStateMixin {
  late final EquipeController _controller;
  late final TabController _abas;

  @override
  void initState() {
    super.initState();
    _controller = inject<EquipeController>();
    _abas = TabController(length: 2, vsync: this);
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
      title: 'Equipe',
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
            TabBar(
              controller: _abas,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).hintColor,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.business_outlined), text: 'Departamentos'),
                Tab(icon: Icon(Icons.people_outline), text: 'Atendentes'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ViewStateBuilder<EquipeController, Equipe>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.carregar,
                ),
                onSuccess: (context, equipe) => TabBarView(
                  controller: _abas,
                  children: [
                    _AbaDepartamentos(
                      itens: equipe.departamentos,
                      controller: _controller,
                    ),
                    _AbaAtendentes(
                      itens: equipe.atendentes,
                      departamentos: equipe.departamentos,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AbaDepartamentos extends StatelessWidget {
  final List<Departamento> itens;
  final EquipeController controller;

  const _AbaDepartamentos({required this.itens, required this.controller});

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
                'Para onde as conversas vão quando chegam.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.colors.fgMuted),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Novo departamento'),
              onPressed: () => abrirCriacaoDepartamento(context, controller),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: itens.isEmpty
              ? const AppEmptyView(
                  title: 'Nenhum departamento',
                  subtitle: 'Sem departamento a fila não tem para onde mandar '
                      'as conversas que chegam.',
                )
              : ListView.separated(
                  itemCount: itens.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _LinhaDepartamento(item: itens[i], controller: controller),
                ),
        ),
      ],
    );
  }
}

class _LinhaDepartamento extends StatelessWidget {
  final Departamento item;
  final EquipeController controller;

  const _LinhaDepartamento({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
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
                      item.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (!item.ativo) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Etiqueta(
                        texto: 'Inativo',
                        cor: context.colors.fgMuted,
                      ),
                    ],
                  ],
                ),
                if (item.descricao.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.descricao,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.colors.fgMuted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () => abrirEdicaoDepartamento(context, item, controller),
          ),
          if (item.ativo)
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: 'Desativar',
              onPressed: () =>
                  abrirDesativacaoDepartamento(context, item, controller),
            ),
        ],
      ),
    );
  }
}

class _AbaAtendentes extends StatelessWidget {
  final List<Atendente> itens;
  final List<Departamento> departamentos;

  const _AbaAtendentes({required this.itens, required this.departamentos});

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return const AppEmptyView(
        title: 'Nenhum atendente',
        subtitle: 'Convide pessoas em "Usuários" — elas aparecem aqui quando '
            'forem vinculadas a um departamento.',
      );
    }

    // Nome do departamento por id, para não repetir a busca linha a linha.
    final nomePorId = {for (final d in departamentos) d.id: d.nome};

    return ListView.separated(
      itemCount: itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = itens[i];
        final depto = nomePorId[a.departamentoId];

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
                          a.nome,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Ativo é o cadastro; disponível é "aceitando conversa
                        // agora". Quem está de férias fica ativo e indisponível
                        // — por isso os dois estados aparecem.
                        if (!a.ativo)
                          _Etiqueta(
                            texto: 'Inativo',
                            cor: context.colors.fgMuted,
                          )
                        else if (!a.disponivel)
                          const _Etiqueta(
                            texto: 'Indisponível',
                            cor: Colors.orange,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        if (a.cargo.isNotEmpty) a.cargo,
                        depto ?? 'sem departamento',
                        'até ${a.maxSimultaneos} simultâneos',
                      ].join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.colors.fgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
