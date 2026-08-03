import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/tenant_user.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../controllers/tenant_users_controller.dart';

const _escoposConhecidos = [
  'tenant:admin',
  'atendimentos:read',
  'atendimentos:write',
  'clientes:write',
  'kanban:admin',
];

class TenantUsersPage extends StatefulWidget {
  const TenantUsersPage({super.key});

  @override
  State<TenantUsersPage> createState() => _TenantUsersPageState();
}

class _TenantUsersPageState extends State<TenantUsersPage> {
  late final TenantUsersController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<TenantUsersController>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.fetchUsers(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Usuários do Tenant',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchUsers,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ViewStateBuilder<TenantUsersController, List<TenantUser>>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.fetchUsers,
          ),
          onSuccess: (context, users) {
            if (users.isEmpty) {
              return const AppEmptyView(
                icon: Icons.people_outline,
                title: 'Nenhum usuario neste tenant',
                subtitle: 'Convidados que aceitarem o convite aparecem aqui.',
              );
            }
            return SingleChildScrollView(
              child: AppCard(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(
                        label: Text(
                          'User ID',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Papel',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Escopos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Fluxos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Ativo',
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
                    rows: users.map((u) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${u.userId}')),
                          DataCell(Text(u.role)),
                          DataCell(Text(u.modulePermissions.join(', '))),
                          DataCell(Text(u.flowPermissions.join(', '))),
                          DataCell(
                            Icon(
                              u.isActive ? Icons.check_circle : Icons.cancel,
                              color: u.isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Editar',
                              onPressed: () => _showEditDialog(context, u),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, TenantUser user) {
    String role = user.role;
    final scopesEscolhidos = user.modulePermissions.toSet();
    final flowsController = TextEditingController(
      text: user.flowPermissions.join(', '),
    );

    showDialog(
      context: context,
      // O diálogo passa a ser dono do controller: descartá-lo pelo
      // `whenComplete` do showDialog quebraria durante a animação de saída.
      builder: (dialogContext) => DialogoComCampos(
        campos: [flowsController],
        builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Editar usuário #${user.userId}'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Papel'),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: 'staff',
                            child: Text('Atendente (staff)'),
                          ),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => role = v ?? role),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Escopos',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ..._escoposConhecidos.map(
                        (s) => CheckboxListTile(
                          dense: true,
                          title: Text(s),
                          value: scopesEscolhidos.contains(s),
                          onChanged: (checked) => setDialogState(() {
                            if (checked ?? false) {
                              scopesEscolhidos.add(s);
                            } else {
                              scopesEscolhidos.remove(s);
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppTextField(
                        label:
                            'IDs dos fluxos permitidos (separados por vírgula)',
                        controller: flowsController,
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
                    final flowPermissions = flowsController.text
                        .split(',')
                        .map((s) => int.tryParse(s.trim()))
                        .whereType<int>()
                        .toList();
                    final res = await _controller.updateUser(
                      userId: user.userId,
                      role: role,
                      modulePermissions: scopesEscolhidos.toList(),
                      flowPermissions: flowPermissions,
                    );
                    if (dialogContext.mounted) {
                      if (res case Success()) {
                        Navigator.pop(dialogContext);
                      } else if (res case Failure(:final error)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Erro ao salvar: ${ErrorMessageMapper.map(error)}',
                            ),
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
      },
      ),
    );
  }
}
