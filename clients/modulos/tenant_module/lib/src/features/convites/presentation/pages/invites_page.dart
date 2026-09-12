import 'package:dependencies_module/dependencies_module.dart'
    hide TenantInviteCreated;
// `Clipboard` não vem pelo dependencies_module (que reexporta material, não
// services).
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../domain/model/tenant_invite.dart';
import '../../../../shared/widgets/tenant_drawer.dart';
import '../controllers/invites_controller.dart';

/// O link que o convidado vai abrir, absoluto.
///
/// A tela mostrava `/aceitar-convite?token=…` — um caminho, não um endereço.
/// Colado num WhatsApp ele não abre nada, e não havia como saber qual host
/// prefixar: dev e produção são domínios diferentes. Sai do `AppConfig`, que é
/// onde o flavor já define o ambiente.
String linkDoConvite(String token) {
  final base = inject<AppConfig>().apiEndpoint.replaceAll(RegExp(r'/+$'), '');
  return '$base/aceitar-convite?token=$token';
}

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.fetchInvites(),
    );
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
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
                      subtitle:
                          'Use "Novo Convite" para convidar alguem ao tenant.',
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
              DataColumn(
                label: Text(
                  'Nome / E-mail',
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
                  'Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Expira em',
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
            rows: invites.map((invite) {
              final status = invite.used
                  ? 'Aceito'
                  : invite.revoked
                  ? 'Revogado'
                  : invite.pendente
                  ? 'Pendente'
                  : 'Expirado';
              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          invite.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          invite.email,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(invite.role)),
                  DataCell(Text(status)),
                  DataCell(
                    Text(
                      '${invite.expiresAt.day}/${invite.expiresAt.month}/${invite.expiresAt.year}',
                    ),
                  ),
                  DataCell(
                    invite.pendente
                        ? IconButton(
                            icon: const Icon(Icons.block, color: Colors.red),
                            tooltip: 'Revogar',
                            onPressed: () => _revoke(invite),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _revoke(TenantInvite invite) async {
    final res = await _controller.revokeInvite(invite.id);
    if (!mounted) return;
    if (res case Failure(:final error)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao revogar: ${ErrorMessageMapper.map(error)}'),
        ),
      );
    }
  }

  void _showCreateDialog(BuildContext context) {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    String role = 'staff';
    final flowsController = TextEditingController();
    final scopesEscolhidos = <String>{};
    // O catálogo canônico inteiro, o mesmo que o authorization server publica
    // em `scopes_supported`. Antes eram três escopos escritos à mão aqui, e
    // convidar alguém para treinamento, financeiro ou configurações era
    // impossível pela tela — restava editar a pessoa depois de ela entrar.
    //
    // `tenant:admin` fica de fora da lista: quem deve ser administrador é
    // convidado pelo papel "Admin", logo acima, e não marcando uma caixa no
    // meio das outras.
    const escoposDisponiveis = <String, String>{
      'atendimentos:read': 'Ver atendimentos',
      'atendimentos:write': 'Atender e responder',
      'clientes:read': 'Ver clientes',
      'clientes:write': 'Cadastrar e editar clientes',
      'operacional:read': 'Ver a operação (filas, atendentes)',
      'operacional:admin': 'Administrar a operação',
      'kanban:admin': 'Configurar os quadros',
      'treinamento:read': 'Ver o treinamento da IA',
      'treinamento:write': 'Treinar a IA',
      'financeiro:read': 'Ver o financeiro',
      'financeiro:write': 'Mexer no financeiro',
      'configuracoes:read': 'Ver as configurações',
      'configuracoes:write': 'Alterar as configurações',
    };

    showDialog(
      context: context,
      // O diálogo é dono dos controllers; ver `DialogoComCampos`.
      builder: (dialogContext) => DialogoComCampos(
        campos: [emailController, nameController, flowsController],
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Novo Convite'),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          label: 'Nome',
                          hint: 'ex: Maria Silva',
                          controller: nameController,
                        ),
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
                              setDialogState(() => role = v ?? 'staff'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Escopos iniciais',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...escoposDisponiveis.entries.map(
                          (e) => CheckboxListTile(
                            dense: true,
                            title: Text(e.value),
                            // O nome técnico continua visível: é ele que
                            // aparece na tela de usuários e no token do MCP,
                            // e esconder cria dois vocabulários para a mesma
                            // coisa.
                            subtitle: Text(
                              e.key,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            value: scopesEscolhidos.contains(e.key),
                            onChanged: (checked) => setDialogState(() {
                              if (checked ?? false) {
                                scopesEscolhidos.add(e.key);
                              } else {
                                scopesEscolhidos.remove(e.key);
                              }
                            }),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppTextField(
                          label:
                              'IDs dos fluxos permitidos (separados por vírgula)',
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
                          const SnackBar(
                            content: Text('Preencha nome e e-mail.'),
                          ),
                        );
                        return;
                      }
                      final modulePermissions = role == 'admin'
                          ? const [
                              'tenant:admin',
                              'atendimentos:read',
                              'atendimentos:write',
                              'clientes:write',
                            ]
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
                        if (res case Success(value: final convite)) {
                          Navigator.pop(dialogContext);
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Convite criado'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Envie este link para ${convite.email}. '
                                      'Ele vale uma vez e expira.',
                                    ),
                                    const SizedBox(height: 12),
                                    SelectableText(
                                      linkDoConvite(convite.token),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // O link é longo e a pessoa vai colá-lo
                                    // noutro aplicativo: selecionar à mão um
                                    // token de 64 caracteres é onde se erra.
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text: linkDoConvite(convite.token),
                                          ),
                                        );
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          const SnackBar(
                                            content: Text('Link copiado.'),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('Copiar link'),
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
                        } else if (res case Failure(:final error)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Erro ao criar convite: '
                                '${ErrorMessageMapper.map(error)}',
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
