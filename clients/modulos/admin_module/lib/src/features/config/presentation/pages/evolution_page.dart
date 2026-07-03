import 'package:dependencies_module/dependencies_module.dart' hide Tenant;

import '../../domain/model/tenant.dart';
import '../../domain/model/evolution_connection_result.dart';
import '../controllers/evolution_controller.dart';
import '../widgets/admin_drawer.dart';

class EvolutionPage extends StatefulWidget {
  const EvolutionPage({super.key});

  @override
  State<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends State<EvolutionPage> {
  late final EvolutionController _controller;
  final Map<String, EvolutionConnectionResult?> _testResults = {};
  final Map<String, bool> _loadingStates = {};

  @override
  void initState() {
    super.initState();
    _controller = inject<EvolutionController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchTenants();
    });
  }

  Future<void> _testConnection(String tenantId) async {
    setState(() {
      _loadingStates[tenantId] = true;
      _testResults[tenantId] = null;
    });

    final res = await _controller.testConnection(tenantId);

    if (mounted) {
      setState(() {
        _loadingStates[tenantId] = false;
        if (res is SuccessReturn<EvolutionConnectionResult>) {
          _testResults[tenantId] = res.result;
        } else {
          _testResults[tenantId] = EvolutionConnectionResult(
            status: 'error',
            errorMessage: (res as ErrorReturn).result.message,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Conexões Evolution API',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar Tenants',
          onPressed: _controller.fetchTenants,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Garantia de Conectividade',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Verifique a integridade e o estado de conexão das instâncias do WhatsApp integradas via Evolution API.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<EvolutionController, List<Tenant>>(
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
                DataColumn(label: Text('Nome do Tenant', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Slug', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status do Tenant', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status de Conexão WhatsApp', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: tenants.map((tenant) {
                final isLoading = _loadingStates[tenant.id] ?? false;
                final result = _testResults[tenant.id];

                return DataRow(
                  cells: [
                    DataCell(Text(tenant.name)),
                    DataCell(Text(tenant.slug)),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tenant.active ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tenant.active ? 'Ativo' : 'Inativo',
                          style: TextStyle(
                            color: tenant.active ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    DataCell(_buildConnectionStatusWidget(isLoading, result)),
                    DataCell(
                      ElevatedButton.icon(
                        icon: isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.sync_alt, size: 16),
                        label: Text(isLoading ? 'Testando...' : 'Testar Conectividade'),
                        onPressed: isLoading ? null : () => _testConnection(tenant.id),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );
  }

  Widget _buildConnectionStatusWidget(bool isLoading, EvolutionConnectionResult? result) {
    if (isLoading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Consultando API...', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      );
    }

    if (result == null) {
      return const Text('Não testado', style: TextStyle(color: Colors.grey));
    }

    Color color;
    String text;
    IconData icon;

    switch (result.status.toLowerCase()) {
      case 'open':
        color = Colors.green;
        text = 'CONECTADO (OPEN)';
        icon = Icons.check_circle;
        break;
      case 'connecting':
        color = Colors.amber[800]!;
        text = 'CONECTANDO...';
        icon = Icons.hourglass_empty;
        break;
      case 'close':
        color = Colors.grey[600]!;
        text = 'DESCONECTADO (CLOSE)';
        icon = Icons.cancel;
        break;
      case 'error':
      default:
        color = Colors.red;
        text = 'ERRO API';
        icon = Icons.error_outline;
        break;
    }

    return Tooltip(
      message: result.errorMessage.isNotEmpty ? result.errorMessage : text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
