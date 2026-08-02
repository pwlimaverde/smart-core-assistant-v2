import 'package:dependencies_module/dependencies_module.dart'
    hide Plan, Subscription, PaymentRecord;

import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/payment_record.dart';
import '../controllers/billing_controller.dart';
import '../../../../shared/widgets/admin_drawer.dart';
import '../widgets/vouchers_tab.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage>
    with SingleTickerProviderStateMixin {
  late final BillingController _controller;
  late final TabController _tabController;
  String? _tenantIdFiltro;
  bool _rotaProcessada = false;

  @override
  void initState() {
    super.initState();
    _controller = inject<BillingController>();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchBillingData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Encadeamento lista→faturamento: quando a navegação vem de TenantsPage
    // ("Ver Pagamentos"), o tenant chega via query parameter `tenantId` —
    // filtra o histórico e já abre direto na aba de Pagamentos.
    if (!_rotaProcessada) {
      final tenantId = GoRouterState.of(
        context,
      ).uri.queryParameters['tenantId'];
      if (tenantId != null && tenantId.trim().isNotEmpty) {
        _rotaProcessada = true;
        _tenantIdFiltro = tenantId.trim();
        _tabController.index = 2; // aba "Histórico Financeiro"
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Faturamento & Planos',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar dados',
          onPressed: _controller.fetchBillingData,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Painel de Faturamento',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).hintColor,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.style), text: 'Planos'),
                Tab(icon: Icon(Icons.card_membership), text: 'Assinaturas'),
                Tab(
                  icon: Icon(Icons.history_edu),
                  text: 'Histórico Financeiro',
                ),
                Tab(
                  icon: Icon(Icons.confirmation_number_outlined),
                  text: 'Vouchers',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<BillingController, BillingState>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.fetchBillingData,
                ),
                onSuccess: (context, state) {
                  final payments = _tenantIdFiltro == null
                      ? state.payments
                      : state.payments
                            .where((p) => p.tenantId == _tenantIdFiltro)
                            .toList();
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPlansTab(state.plans),
                      _buildSubscriptionsTab(state.subscriptions),
                      _buildPaymentsTab(payments),
                      VouchersTab(
                        vouchers: state.vouchers,
                        planos: state.plans,
                        controller: _controller,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ABA PLANOS ---
  Widget _buildPlansTab(List<Plan> plans) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Planos Disponíveis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Novo Plano'),
              onPressed: () => _showPlanDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: plans.isEmpty
              ? const Center(child: Text('Nenhum plano cadastrado.'))
              : ListView.separated(
                  itemCount: plans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  // O context do item NÃO é usado para abrir diálogos: ele é
                  // desmontado quando a lista recarrega, e um `context.mounted`
                  // falso depois do await engoliria o fechamento da janela.
                  itemBuilder: (itemContext, index) {
                    final plan = plans[index];
                    return AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      plan.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: plan.active
                                            ? Colors.green.withValues(
                                                alpha: isDark ? 0.2 : 0.1,
                                              )
                                            : Colors.red.withValues(
                                                alpha: isDark ? 0.2 : 0.1,
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: plan.active
                                              ? Colors.green.withValues(
                                                  alpha: 0.5,
                                                )
                                              : Colors.red.withValues(
                                                  alpha: 0.5,
                                                ),
                                        ),
                                      ),
                                      child: Text(
                                        plan.active ? 'ATIVO' : 'INATIVO',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: plan.active
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  plan.description,
                                  style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _buildFeatureBadge(
                                      'Preço: R\$ ${plan.price}/mês',
                                      Icons.monetization_on_outlined,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildFeatureBadge(
                                      'Instâncias Max: ${plan.maxInstances}',
                                      Icons.cloud_queue,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildFeatureBadge(
                                      'Departamentos Max: ${plan.maxDepartments}',
                                      Icons.business,
                                    ),
                                    const SizedBox(width: 12),
                                    _buildFeatureBadge(
                                      'Fluxos Max: ${plan.maxFluxos}',
                                      Icons.account_tree_outlined,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showPlanDialog(context, plan),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFeatureBadge(String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // --- ABA ASSINATURAS ---
  Widget _buildSubscriptionsTab(List<Subscription> subscriptions) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assinaturas dos Tenants',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: subscriptions.isEmpty
              ? const Center(
                  child: Text('Nenhuma assinatura ativa encontrada.'),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 100,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? Colors.grey[900] : Colors.grey[100],
                          ),
                          columns: const [
                            DataColumn(
                              label: Text(
                                'ID Tenant',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Plano',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Status',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Período Atual',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Ações',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          rows: subscriptions.map((sub) {
                            return DataRow(
                              cells: [
                                DataCell(SelectableText(sub.tenantId)),
                                DataCell(Text('Plano ID: ${sub.planId}')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sub.status == 'active'
                                          ? Colors.green.withValues(alpha: 0.1)
                                          : Colors.amber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: sub.status == 'active'
                                            ? Colors.green
                                            : Colors.amber,
                                      ),
                                    ),
                                    child: Text(
                                      sub.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: sub.status == 'active'
                                            ? Colors.green
                                            : Colors.amber,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${_formatDate(sub.currentPeriodStart)} até ${_formatDate(sub.currentPeriodEnd)}',
                                  ),
                                ),
                                DataCell(
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add_card, size: 16),
                                    label: const Text('Registrar Pagamento'),
                                    onPressed: () => _showPaymentDialog(
                                      context,
                                      sub.tenantId,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // --- ABA PAGAMENTOS ---
  Widget _buildPaymentsTab(List<PaymentRecord> payments) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Histórico de Pagamentos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt),
              label: const Text('Registrar Pagamento Manual'),
              onPressed: () => _showPaymentDialog(context),
            ),
          ],
        ),
        if (_tenantIdFiltro != null) ...[
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.filter_alt, size: 16),
            label: Text('Filtrado pelo tenant: $_tenantIdFiltro'),
            onDeleted: () => setState(() => _tenantIdFiltro = null),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: payments.isEmpty
              ? const Center(child: Text('Nenhum pagamento registrado.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 100,
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? Colors.grey[900] : Colors.grey[100],
                          ),
                          columns: const [
                            DataColumn(
                              label: Text(
                                'ID Tenant',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Valor',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Método',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Data Pagamento',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Período de Cobertura',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Notas',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          rows: payments.map((payment) {
                            return DataRow(
                              cells: [
                                DataCell(SelectableText(payment.tenantId)),
                                DataCell(
                                  Text(
                                    'R\$ ${payment.amount}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(Text(payment.paymentMethod)),
                                DataCell(Text(payment.paymentDate)),
                                DataCell(
                                  Text(
                                    '${payment.periodStart} a ${payment.periodEnd}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    payment.notes.isNotEmpty
                                        ? payment.notes
                                        : '-',
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Diálogo de criação/edição de plano.
  ///
  /// Duas decisões vieram de um bug real (a janela de edição não fechava):
  ///
  ///  - o fechamento usa o `Navigator` do **próprio diálogo**, não um
  ///    `context.mounted` da árvore de fora — salvar recarrega a lista, e o
  ///    context que abriu a janela pode já ter sido desmontado quando o `await`
  ///    retorna;
  ///  - o erro é renderizado **dentro** do diálogo. Um `SnackBar` fica atrás do
  ///    barrier modal: o usuário via a janela travada e nenhuma explicação.
  void _showPlanDialog(BuildContext context, [Plan? plan]) {
    final nameController = TextEditingController(text: plan?.name);
    final descController = TextEditingController(text: plan?.description);
    final priceController = TextEditingController(text: plan?.price);
    final instancesController = TextEditingController(
      text: plan != null ? '${plan.maxInstances}' : '',
    );
    final departmentsController = TextEditingController(
      text: plan != null ? '${plan.maxDepartments}' : '',
    );
    final fluxosController = TextEditingController(
      text: plan != null ? '${plan.maxFluxos}' : '',
    );
    bool active = plan?.active ?? true;
    final isNew = plan == null;
    String? erro;
    bool salvando = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateCtx, setStateDialog) {
            return AlertDialog(
              title: Text(isNew ? 'Criar Novo Plano' : 'Editar Plano'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppTextField(
                        label: 'Nome do Plano',
                        hint: 'ex: Plano Pro',
                        controller: nameController,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Descrição',
                        hint: 'ex: Acesso total para equipes médias',
                        controller: descController,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Preço (R\$ / mês)',
                        hint: 'ex: 199.90',
                        controller: priceController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Instâncias Máximas',
                        hint: 'ex: 5',
                        controller: instancesController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Departamentos Máximos',
                        hint: 'ex: 10',
                        controller: departmentsController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Fluxos de Atendimento Máximos',
                        hint: 'ex: 5',
                        controller: fluxosController,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('Plano Ativo para Novas Assinaturas'),
                        value: active,
                        onChanged: (val) =>
                            setStateDialog(() => active = val ?? false),
                      ),
                      if (erro != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 18,
                              color: Theme.of(stateCtx).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                erro!,
                                style: TextStyle(
                                  color: Theme.of(stateCtx).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                PrimaryButton(
                  label: salvando ? 'Salvando...' : 'Salvar',
                  expand: false,
                  onPressed: salvando
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final desc = descController.text.trim();
                          final price = priceController.text.trim();
                          final instStr = instancesController.text.trim();
                          final deptStr = departmentsController.text.trim();
                          final fluxStr = fluxosController.text.trim();

                          if (name.isEmpty ||
                              desc.isEmpty ||
                              price.isEmpty ||
                              instStr.isEmpty ||
                              deptStr.isEmpty ||
                              fluxStr.isEmpty) {
                            setStateDialog(
                              () => erro = 'Preencha todos os campos.',
                            );
                            return;
                          }

                          final instances = int.tryParse(instStr);
                          final departments = int.tryParse(deptStr);
                          final fluxos = int.tryParse(fluxStr);

                          if (instances == null ||
                              departments == null ||
                              fluxos == null) {
                            setStateDialog(
                              () => erro =
                                  'Instâncias, departamentos e fluxos devem '
                                  'ser números inteiros.',
                            );
                            return;
                          }

                          // O Navigator é resolvido ANTES do await: depois dele
                          // a lista já recarregou e o context de origem pode
                          // não existir mais.
                          final navigator = Navigator.of(dialogContext);
                          setStateDialog(() {
                            salvando = true;
                            erro = null;
                          });

                          final ReturnSuccessOrError res;
                          if (isNew) {
                            res = await _controller.createPlan(
                              name: name,
                              description: desc,
                              price: price,
                              maxInstances: instances,
                              maxDepartments: departments,
                              maxFluxos: fluxos,
                            );
                          } else {
                            res = await _controller.updatePlan(
                              id: plan.id,
                              name: name,
                              description: desc,
                              price: price,
                              maxInstances: instances,
                              maxDepartments: departments,
                              maxFluxos: fluxos,
                              active: active,
                            );
                          }

                          if (res case Failure(:final error)) {
                            if (stateCtx.mounted) {
                              setStateDialog(() {
                                salvando = false;
                                erro =
                                    'Erro ao salvar: '
                                    '${ErrorMessageMapper.map(error)}';
                              });
                            }
                            return;
                          }
                          navigator.pop();
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPaymentDialog(BuildContext context, [String? prefilledTenantId]) {
    final tenantController = TextEditingController(text: prefilledTenantId);
    final amountController = TextEditingController();
    final methodController = TextEditingController(text: 'PIX');
    final dateController = TextEditingController(
      text: DateTime.now().toString().split(' ')[0],
    );
    final startController = TextEditingController(
      text: DateTime.now().toString().split(' ')[0],
    );
    final endController = TextEditingController(
      text: DateTime.now()
          .add(const Duration(days: 30))
          .toString()
          .split(' ')[0],
    );
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Registrar Pagamento Manual'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (prefilledTenantId != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tenant Destinatário',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            prefilledTenantId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    AppTextField(
                      label: 'ID do Tenant',
                      hint: 'ex: 9a781b1c-c760-4966-bf3a-cd4f1efb43cc',
                      controller: tenantController,
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppTextField(
                    label: 'Valor do Pagamento (R\$)',
                    hint: 'ex: 199.90',
                    controller: amountController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Método de Pagamento',
                    hint: 'ex: PIX, Cartão, Boleto, Depósito',
                    controller: methodController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Data do Pagamento (YYYY-MM-DD)',
                    hint: 'ex: 2026-06-19',
                    controller: dateController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Início da Cobertura (YYYY-MM-DD)',
                    hint: 'ex: 2026-06-19',
                    controller: startController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Fim da Cobertura (YYYY-MM-DD)',
                    hint: 'ex: 2026-07-19',
                    controller: endController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Notas / Observações',
                    hint: 'ex: Pagamento identificado por comprovante whatsapp',
                    controller: notesController,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              label: 'Registrar',
              expand: false,
              onPressed: () async {
                final tenantId = tenantController.text.trim();
                final amount = amountController.text.trim();
                final method = methodController.text.trim();
                final date = dateController.text.trim();
                final start = startController.text.trim();
                final end = endController.text.trim();
                final notes = notesController.text.trim();

                if (tenantId.isEmpty ||
                    amount.isEmpty ||
                    method.isEmpty ||
                    date.isEmpty ||
                    start.isEmpty ||
                    end.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Por favor, preencha todos os campos obrigatórios.',
                      ),
                    ),
                  );
                  return;
                }

                final res = await _controller.registerPayment(
                  tenantId: tenantId,
                  amount: amount,
                  paymentMethod: method,
                  paymentDate: date,
                  periodStart: start,
                  periodEnd: end,
                  notes: notes,
                );

                if (context.mounted) {
                  if (res case Failure(:final error)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Erro ao registrar: '
                          '${ErrorMessageMapper.map(error)}',
                        ),
                      ),
                    );
                  } else {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pagamento registrado com sucesso!'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}
