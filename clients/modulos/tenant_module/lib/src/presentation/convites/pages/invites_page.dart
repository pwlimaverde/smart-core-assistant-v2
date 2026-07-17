import 'package:dependencies_module/dependencies_module.dart' hide TenantInviteCreated;

import '../../../domain/model/tenant_invite.dart';
import '../../widgets/tenant_drawer.dart';
import '../controllers/invites_controller.dart';

class InvitesPage extends StatefulWidget {
  const InvitesPage({super.key});

  @override
  State<InvitesPage> createState() => _InvitesPageState();
}

class _InvitesPageState extends State<InvitesPage> {
  late final InvitesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<InvitesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.fetchInvites());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Convites',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchInvites,
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
                  'Convites do Tenant',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo Convite'),
                  onPressed: () => _showCreateDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<InvitesController, List<TenantInvite>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.fetchInvites,
                ),
                onSuccess: (context, invites) {
                  if (invites.isEmpty) {
                    return const AppEmptyView(
                      icon: Icons.mail_outline,
                      title: 'Nenhum convite ainda',
                      subtitle: 'Use "Novo Convite" para convidar alguem ao tenant.',
                    );
                  }
                  return _buildInvitesTable(invites);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitesTable(List<TenantInvite> invites) {
    return SingleChildScrollView(
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Nome / E-mail', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Papel', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Expira em', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: invites.map((invite) {
              final status = invite.used
                  ? 'Aceito'
                  : invite.revoked
                      ? 'Revogado'
                      : invite.pendente
                          ? 'Pendente'
                          : 'Expirado';
              return DataRow(cells: [
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(invite.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(invite.email, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                  ],
                )),
                DataCell(Text(invite.role)),
                DataCell(Text(status)),
                DataCell(Text('${invite.expiresAt.day}/${invite.expiresAt.month}/${invite.expiresAt.year}')),
                DataCell(
                  invite.pendente
                      ? IconButton(
                          icon: const Icon(Icons.block, color: Colors.red),
                          tooltip: 'Revogar',
                          onPressed: () => _revoke(invite),
                        )
                      : const SizedBox.shrink(),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _revoke(TenantInvite invite) async {
    final res = await _controller.revokeInvite(invite.id);
    if (mounted && res is ErrorReturn<Unit>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao revogar: ${res.result.message}')),
      );
    }
  }

  void _showCreateDialog(BuildContext context) {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    String role = 'staff';
    final flowsController = TextEditingController();
    final scopesEscolhidos = <String>{};
    const escoposDisponiveis = [
      'atendimentos:read',
      'atendimentos:write',
      'clientes:write',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Novo Convite'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(label: 'Nome', hint: 'ex: Maria Silva', controller: nameController),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'E-mail',
                      hint: 'ex: maria@empresa.com',
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Papel'),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'staff', child: Text('Atendente (staff)')),
                      ],
                      onChanged: (v) => setDialogState(() => role = v ?? 'staff'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Escopos iniciais', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...escoposDisponiveis.map((s) => CheckboxListTile(
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
                        )),
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'IDs dos fluxos permitidos (separados por vírgula)',
                      hint: 'ex: 1,2,3',
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
                label: 'Enviar Convite',
                expand: false,
                onPressed: () async {
                  final email = emailController.text.trim();
                  final name = nameController.text.trim();
                  if (email.isEmpty || name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Preencha nome e e-mail.')),
                    );
                    return;
                  }
                  final modulePermissions = role == 'admin'
                      ? const ['tenant:admin', 'atendimentos:read', 'atendimentos:write', 'clientes:write']
                      : scopesEscolhidos.toList();
                  final flowPermissions = flowsController.text
                      .split(',')
                      .map((s) => int.tryParse(s.trim()))
                      .whereType<int>()
                      .toList();

                  final res = await _controller.createInvite(
                    email: email,
                    name: name,
                    role: role,
                    modulePermissions: modulePermissions,
                    flowPermissions: flowPermissions,
                  );
                  if (dialogContext.mounted) {
                    if (res is SuccessReturn<TenantInviteCreated>) {
                      Navigator.pop(dialogContext);
                      if (context.mounted) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Convite Criado'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Compartilhe este link com o convidado:'),
                                const SizedBox(height: 12),
                                SelectableText(
                                  '/aceitar-convite?token=${res.result.token}',
                                  style: const TextStyle(fontFamily: 'monospace'),
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
                      }
                    } else if (res is ErrorReturn<TenantInviteCreated>) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao criar convite: ${res.result.message}')),
                      );
                    }
                  }
                },
              ),
            ],
          );
        });
      },
    );
  }
}
