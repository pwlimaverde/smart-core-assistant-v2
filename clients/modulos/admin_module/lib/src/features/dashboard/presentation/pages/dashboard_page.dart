import 'package:dependencies_module/dependencies_module.dart'
    hide ServiceHealth;

import '../../domain/model/dashboard_summary.dart';
import '../../domain/model/service_health.dart';
import '../controllers/dashboard_controller.dart';
import '../../../../shared/widgets/admin_drawer.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<DashboardController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dashboard Geral',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.fetchSummary,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ViewStateBuilder<DashboardController, DashboardSummary>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.fetchSummary,
          ),
          onSuccess: (context, summary) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visão Geral do Sistema',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                // KPIs Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double cardWidth = (constraints.maxWidth - 48) / 4;
                    final isSmallScreen = constraints.maxWidth < 800;

                    if (isSmallScreen) {
                      return Column(
                        children: [
                          _buildKpiRow([
                            _buildKpiCard(
                              title: 'Total de Clientes / Tenants',
                              value: summary.totalTenants.toString(),
                              icon: Icons.business,
                              color: Colors.blue,
                            ),
                            _buildKpiCard(
                              title: 'Tenants Ativos',
                              value: summary.activeTenants.toString(),
                              icon: Icons.check_circle_outline,
                              color: Colors.green,
                            ),
                          ]),
                          const SizedBox(height: 16),
                          _buildKpiRow([
                            _buildKpiCard(
                              title: 'Assinaturas Ativas',
                              value: summary.totalSubscriptions.toString(),
                              icon: Icons.card_membership,
                              color: Colors.purple,
                            ),
                            _buildKpiCard(
                              title: 'Receita Mensal Recorrente (MRR)',
                              value: 'R\$ ${summary.monthlyRecurringRevenue}',
                              icon: Icons.monetization_on_outlined,
                              color: Colors.amber[700]!,
                            ),
                          ]),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Total de Clientes / Tenants',
                            value: summary.totalTenants.toString(),
                            icon: Icons.business,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Tenants Ativos',
                            value: summary.activeTenants.toString(),
                            icon: Icons.check_circle_outline,
                            color: Colors.green,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Assinaturas Ativas',
                            value: summary.totalSubscriptions.toString(),
                            icon: Icons.card_membership,
                            color: Colors.purple,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildKpiCard(
                            title: 'Receita Mensal Recorrente (MRR)',
                            value: 'R\$ ${summary.monthlyRecurringRevenue}',
                            icon: Icons.monetization_on_outlined,
                            color: Colors.amber[700]!,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Monitor de Saúde
                Text(
                  'Status e Saúde dos Serviços',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildHealthList(summary.health),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildKpiRow(List<Widget> children) {
    return Row(
      children: children
          .map(
            (child) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: child,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthList(List<ServiceHealth> services) {
    if (services.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Nenhum dado de saúde reportado.')),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: services.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final service = services[index];
          return ListTile(
            leading: Icon(
              _getServiceIcon(service.serviceName),
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              service.serviceName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              service.message.isEmpty
                  ? 'Operando normalmente'
                  : service.message,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${service.responseTimeMs} ms',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(width: 12),
                _buildHealthBadge(service.status),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _getServiceIcon(String name) {
    switch (name.toLowerCase()) {
      case 'database':
        return Icons.storage;
      case 'redis':
        return Icons.memory;
      case 'evolution_api':
        return Icons.webhook;
      case 'control_plane':
        return Icons.settings_input_component;
      default:
        return Icons.dns;
    }
  }

  Widget _buildHealthBadge(String status) {
    Color color;
    String text;

    switch (status.toLowerCase()) {
      case 'healthy':
        color = Colors.green;
        text = 'Saudável';
        break;
      case 'degraded':
        color = Colors.orange;
        text = 'Instável';
        break;
      case 'unhealthy':
      default:
        color = Colors.red;
        text = 'Fora do Ar';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
