import 'package:dependencies_module/dependencies_module.dart' hide Plan, Subscription, PaymentRecord;

import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/payment_record.dart';
import '../controllers/billing_controller.dart';
import '../widgets/admin_drawer.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  late final BillingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<BillingController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchBillingData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AppScaffold(
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
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).hintColor,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.style), text: 'Planos'),
                  Tab(icon: Icon(Icons.card_membership), text: 'Assinaturas'),
                  Tab(icon: Icon(Icons.history_edu), text: 'Histórico Financeiro'),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ViewStateBuilder<BillingController, BillingState>(
                  controller: _controller,
                  onSuccess: (context, state) {
                    return TabBarView(
                      children: [
                        _buildPlansTab(state.plans),
                        _buildSubscriptionsTab(state.subscriptions),
                        _buildPaymentsTab(state.payments),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
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
                  itemBuilder: (context, index) {
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
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: plan.active
                                            ? Colors.green.withValues(alpha: isDark ? 0.2 : 0.1)
                                            : Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: plan.active ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Text(
                                        plan.active ? 'ATIVO' : 'INATIVO',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: plan.active ? Colors.green : Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  plan.description,
                                  style: TextStyle(color: Theme.of(context).hintColor),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _buildFeatureBadge('Preço: R\$ ${plan.price}/mês', Icons.monetization_on_outlined),
                                    const SizedBox(width: 12),
                                    _buildFeatureBadge('Instâncias Max: ${plan.maxInstances}', Icons.cloud_queue),
                                    const SizedBox(width: 12),
                                    _buildFeatureBadge('Departamentos Max: ${plan.maxDepartments}', Icons.business),
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
              ? const Center(child: Text('Nenhuma assinatura ativa encontrada.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 100),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? Colors.grey[900] : Colors.grey[100],
                          ),
                          columns: const [
                            DataColumn(label: Text('ID Tenant', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Plano', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Período Atual', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: subscriptions.map((sub) {
                            return DataRow(
                              cells: [
                                DataCell(SelectableText(sub.tenantId)),
                                DataCell(Text('Plano ID: ${sub.planId}')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sub.status == 'active'
                                          ? Colors.green.withValues(alpha: 0.1)
                                          : Colors.amber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: sub.status == 'active' ? Colors.green : Colors.amber,
                                      ),
                                    ),
                                    child: Text(
                                      sub.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: sub.status == 'active' ? Colors.green : Colors.amber,
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
                                    onPressed: () => _showPaymentDialog(context, sub.tenantId),
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
                        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 100),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            isDark ? Colors.grey[900] : Colors.grey[100],
                          ),
                          columns: const [
                            DataColumn(label: Text('ID Tenant', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Valor', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Método', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Data Pagamento', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Período de Cobertura', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Notas', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: payments.map((payment) {
                            return DataRow(
                              cells: [
                                DataCell(SelectableText(payment.tenantId)),
                                DataCell(Text('R\$ ${payment.amount}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(payment.paymentMethod)),
                                DataCell(Text(payment.paymentDate)),
                                DataCell(Text('${payment.periodStart} a ${payment.periodEnd}')),
                                DataCell(Text(payment.notes.isNotEmpty ? payment.notes : '-')),
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

  void _showPlanDialog(BuildContext context, [Plan? plan]) {
    final nameController = TextEditingController(text: plan?.name);
    final descController = TextEditingController(text: plan?.description);
    final priceController = TextEditingController(text: plan?.price);
    final instancesController = TextEditingController(text: plan != null ? '${plan.maxInstances}' : '');
    final departmentsController = TextEditingController(text: plan != null ? '${plan.maxDepartments}' : '');
    bool active = plan?.active ?? true;
    final isNew = plan == null;

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
                      CheckboxListTile(
                        title: const Text('Plano Ativo para Novas Assinaturas'),
                        value: active,
                        onChanged: (val) => setStateDialog(() => active = val ?? false),
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
                  label: 'Salvar',
                  expand: false,
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final desc = descController.text.trim();
                    final price = priceController.text.trim();
                    final instStr = instancesController.text.trim();
                    final deptStr = departmentsController.text.trim();

                    if (name.isEmpty || desc.isEmpty || price.isEmpty || instStr.isEmpty || deptStr.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Por favor, preencha todos os campos.')),
                      );
                      return;
                    }

                    final instances = int.tryParse(instStr);
                    final departments = int.tryParse(deptStr);

                    if (instances == null || departments == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Instâncias e Departamentos devem ser inteiros.')),
                      );
                      return;
                    }

                    final ReturnSuccessOrError res;
                    if (isNew) {
                      res = await _controller.createPlan(
                        name: name,
                        description: desc,
                        price: price,
                        maxInstances: instances,
                        maxDepartments: departments,
                      );
                    } else {
                      res = await _controller.updatePlan(
                        id: plan.id,
                        name: name,
                        description: desc,
                        price: price,
                        maxInstances: instances,
                        maxDepartments: departments,
                        active: active,
                      );
                    }

                    if (context.mounted) {
                      if (res is SuccessReturn) {
                        Navigator.pop(dialogContext);
                      } else {
                        final errorVal = (res as ErrorReturn).result;
                        final message = errorVal.message;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao salvar: $message')),
                        );
                      }
                    }
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
    final dateController = TextEditingController(text: DateTime.now().toString().split(' ')[0]);
    final startController = TextEditingController(text: DateTime.now().toString().split(' ')[0]);
    final endController = TextEditingController(
      text: DateTime.now().add(const Duration(days: 30)).toString().split(' ')[0],
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
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tenant Destinatário', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                          const SizedBox(height: 4),
                          SelectableText(
                            prefilledTenantId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
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

                if (tenantId.isEmpty || amount.isEmpty || method.isEmpty || date.isEmpty || start.isEmpty || end.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor, preencha todos os campos obrigatórios.')),
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
                  if (res is SuccessReturn) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pagamento registrado com sucesso!')),
                    );
                  } else {
                    final errorVal = (res as ErrorReturn).result;
                    final message = errorVal.message;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao registrar: $message')),
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
