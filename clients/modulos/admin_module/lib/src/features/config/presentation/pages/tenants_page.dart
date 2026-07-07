import 'package:dependencies_module/dependencies_module.dart' hide Tenant;

import '../../domain/model/tenant.dart';
import '../controllers/tenants_controller.dart';
import '../widgets/admin_drawer.dart';

class TenantsPage extends StatefulWidget {
  const TenantsPage({super.key});

  @override
  State<TenantsPage> createState() => _TenantsPageState();
}

class _TenantsPageState extends State<TenantsPage> {
  late final TenantsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<TenantsController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchTenants();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Gerenciamento de Tenants',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchTenants,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tenants Cadastrados',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo Tenant'),
                  onPressed: () => _showEditDialog(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<TenantsController, List<Tenant>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.fetchTenants,
                ),
                onSuccess: (context, tenants) {
                  if (tenants.isEmpty) {
                    return const Center(
                      child: Text('Nenhum tenant cadastrado.'),
                    );
                  }
                  return _buildTenantsTable(tenants);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantsTable(List<Tenant> tenants) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
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
                DataColumn(label: Text('Nome / Slug', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Contato (Email / Fone)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Dono (Owner ID)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Código de Acesso', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: tenants.map((tenant) {
                return DataRow(
                  cells: [
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tenant.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(tenant.slug, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tenant.email),
                          Text(tenant.phone, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    DataCell(Text('${tenant.ownerId}')),
                    DataCell(
                      Switch(
                        value: tenant.active,
                        onChanged: (active) => _toggleActive(tenant.id, active),
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          if (tenant.accessCode.isNotEmpty) ...[
                            SelectableText(
                              tenant.accessCode,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            icon: const Icon(Icons.vpn_key_outlined, size: 20),
                            tooltip: 'Gerar Novo Código',
                            onPressed: () => _generateAccessCode(tenant.id),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: 'Editar',
                            onPressed: () => _showEditDialog(context, tenant),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.amber),
                            tooltip: 'Ver Configurações',
                            onPressed: () => context.go('/admin/tenant-config?id=${tenant.id}'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.payment, color: Colors.green),
                            tooltip: 'Ver Pagamentos',
                            onPressed: () => context.go('/admin/billing?tenantId=${tenant.id}'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.security, color: Colors.deepPurple),
                            tooltip: 'Ver Auditoria',
                            onPressed: () => context.go('/admin/audit?tenantId=${tenant.id}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleActive(String id, bool active) async {
    final res = await _controller.setTenantActive(id: id, active: active);
    if (mounted && res is ErrorReturn<Unit>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao alterar status: ${res.result.message}')),
      );
    }
  }

  void _generateAccessCode(String id) async {
    final res = await _controller.generateAccessCode(id);
    if (mounted) {
      if (res is SuccessReturn<String>) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Código de Acesso Gerado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Utilize este código para autenticação de suporte ou onboarding:'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Center(
                    child: SelectableText(
                      res.result,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        _controller.fetchTenants(); // recarrega para mostrar o código atualizado
      } else if (res is ErrorReturn<String>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar código: ${res.result.message}')),
        );
      }
    }
  }

  void _showEditDialog(BuildContext context, [Tenant? tenant]) {
    final nameController = TextEditingController(text: tenant?.name);
    final slugController = TextEditingController(text: tenant?.slug);
    final ownerController = TextEditingController(text: tenant != null ? '${tenant.ownerId}' : '');
    final emailController = TextEditingController(text: tenant?.email);
    final phoneController = TextEditingController(text: tenant?.phone);
    final isNew = tenant == null;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isNew ? 'Novo Tenant' : 'Editar Tenant'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    label: 'Nome da Empresa',
                    hint: 'ex: Minha Empresa LTDA',
                    controller: nameController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Slug (identificador único)',
                    hint: 'ex: minha-empresa',
                    controller: slugController,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'ID do Dono (Owner ID)',
                    hint: 'ex: 123',
                    controller: ownerController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'E-mail de Contato',
                    hint: 'ex: contato@empresa.com',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Telefone',
                    hint: 'ex: +5511999999999',
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
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
                final slug = slugController.text.trim();
                final ownerStr = ownerController.text.trim();
                final email = emailController.text.trim();
                final phone = phoneController.text.trim();

                if (name.isEmpty || slug.isEmpty || ownerStr.isEmpty || email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor, preencha os campos obrigatórios.')),
                  );
                  return;
                }

                final ownerId = int.tryParse(ownerStr);
                if (ownerId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('O ID do Dono deve ser um número inteiro válido.')),
                  );
                  return;
                }

                final ReturnSuccessOrError res;
                if (isNew) {
                  res = await _controller.createTenant(
                    name: name,
                    slug: slug,
                    ownerId: ownerId,
                    email: email,
                    phone: phone,
                  );
                } else {
                  res = await _controller.updateTenant(
                    id: tenant.id,
                    name: name,
                    slug: slug,
                    ownerId: ownerId,
                    email: email,
                    phone: phone,
                  );
                }

                if (context.mounted) {
                  if (res is SuccessReturn) {
                    Navigator.pop(dialogContext);
                  } else if (res is ErrorReturn) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao salvar: ${res.result.message}')),
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

