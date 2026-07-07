import 'package:dependencies_module/dependencies_module.dart' hide Tenant, FeatureFlag;

import '../../domain/model/feature_flag.dart';
import '../../domain/model/tenant.dart';
import '../controllers/feature_flags_controller.dart';
import '../widgets/admin_drawer.dart';

class FeatureFlagsPage extends StatefulWidget {
  const FeatureFlagsPage({super.key});

  @override
  State<FeatureFlagsPage> createState() => _FeatureFlagsPageState();
}

class _FeatureFlagsPageState extends State<FeatureFlagsPage> {
  late final FeatureFlagsController _controller;
  List<Tenant> _allTenants = [];

  @override
  void initState() {
    super.initState();
    _controller = inject<FeatureFlagsController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchFeatureFlags();
      _loadTenants();
    });
  }

  Future<void> _loadTenants() async {
    final res = await _controller.getTenants();
    if (res is SuccessReturn<List<Tenant>>) {
      setState(() {
        _allTenants = res.result;
      });
    }
  }

  Future<void> _toggleGlobalFlag(FeatureFlag flag, bool value) async {
    final res = await _controller.setFeatureFlag(key: flag.key, enabledGlobally: value);
    if (!mounted) return;
    if (res is ErrorReturn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar flag: ${(res as ErrorReturn).result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeOverride(String flagKey, String tenantId) async {
    final res = await _controller.setFeatureFlagOverride(
      key: flagKey,
      tenantId: tenantId,
      enabled: false,
      removeOverride: true,
    );
    if (!mounted) return;
    if (res is ErrorReturn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao remover override: ${(res as ErrorReturn).result.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddOverrideDialog(FeatureFlag flag) {
    if (_allTenants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum tenant carregado para overrides.')),
      );
      return;
    }

    // Filtra tenants que ainda não possuem override para esta flag
    final existingTenantIds = flag.overrides.map((o) => o.tenantId).toSet();
    final availableTenants = _allTenants.where((t) => !existingTenantIds.contains(t.id)).toList();

    if (availableTenants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos os tenants já possuem override configurado para esta flag.')),
      );
      return;
    }

    String selectedTenantId = availableTenants.first.id;
    bool overrideValue = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Adicionar Override para ${flag.key}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedTenantId,
                    decoration: const InputDecoration(labelText: 'Tenant / Cliente'),
                    items: availableTenants.map((t) {
                      return DropdownMenuItem<String>(
                        value: t.id,
                        child: Text(t.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedTenantId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Habilitar Funcionalidade'),
                    value: overrideValue,
                    onChanged: (val) {
                      setDialogState(() => overrideValue = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final res = await _controller.setFeatureFlagOverride(
                      key: flag.key,
                      tenantId: selectedTenantId,
                      enabled: overrideValue,
                      removeOverride: false,
                    );
                    if (!context.mounted) return;
                    if (res is ErrorReturn) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao salvar override: ${(res as ErrorReturn).result.message}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('Salvar Override'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Feature Flags',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchFeatureFlags,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gerenciamento de Funcionalidades (Feature Flags)',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Controle o lançamento de novas features de forma global ou libere antecipadamente para clientes específicos usando overrides.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<FeatureFlagsController, List<FeatureFlag>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: _controller.fetchFeatureFlags,
                ),
                onSuccess: (context, flags) {
                  if (flags.isEmpty) {
                    return const Center(
                      child: Text('Nenhuma feature flag registrada.'),
                    );
                  }
                  return _buildFlagsList(flags);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagsList(List<FeatureFlag> flags) {
    return ListView.builder(
      itemCount: flags.length,
      itemBuilder: (context, index) {
        final flag = flags[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: AppCard(
            padding: const EdgeInsets.all(8.0),
            child: ExpansionTile(
              leading: Icon(
                flag.enabledGlobally ? Icons.toggle_on : Icons.toggle_off_outlined,
                color: flag.enabledGlobally ? Colors.green : Colors.grey,
                size: 32,
              ),
              title: Text(
                flag.key,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Text(flag.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Global:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Switch(
                    value: flag.enabledGlobally,
                    onChanged: (val) => _toggleGlobalFlag(flag, val),
                  ),
                ],
              ),
              children: [
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overrides Específicos por Tenant / Cliente',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Adicionar Override'),
                            onPressed: () => _showAddOverrideDialog(flag),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (flag.overrides.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'Nenhum override configurado. O comportamento global se aplica a todos.',
                              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: flag.overrides.length,
                          itemBuilder: (context, oIndex) {
                            final o = flag.overrides[oIndex];
                            final tenantName = _allTenants.firstWhere((t) => t.id == o.tenantId, orElse: () => Tenant(
                              id: o.tenantId,
                              name: 'Tenant ID: ${o.tenantId}',
                              slug: '',
                              apiKey: '',
                              ownerId: 0,
                              email: '',
                              phone: '',
                              active: false,
                              setupCompleted: false,
                              onboardingStep: 0,
                              accessCode: '',
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            )).name;

                            return ListTile(
                              leading: Icon(
                                o.enabled ? Icons.check_circle : Icons.remove_circle,
                                color: o.enabled ? Colors.green : Colors.red,
                              ),
                              title: Text(tenantName),
                              subtitle: Text(o.enabled ? 'Habilitado (Override)' : 'Desabilitado (Override)'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Remover Override',
                                onPressed: () => _removeOverride(flag.key, o.tenantId),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
