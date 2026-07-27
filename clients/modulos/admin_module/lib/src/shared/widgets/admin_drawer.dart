import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: const Center(
              child: Text(
                'Painel Admin',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard Geral'),
            selected: location == '/admin/dashboard',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configurações Globais'),
            selected: location == '/admin/core-settings',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/core-settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Configurações de Tenant'),
            selected: location == '/admin/tenant-config',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/tenant-config');
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Clientes / Tenants'),
            selected: location == '/admin/tenants',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/tenants');
            },
          ),
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Planos & Faturamento'),
            selected: location == '/admin/billing',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/billing');
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync_alt),
            title: const Text('Integração Evolution'),
            selected: location == '/admin/evolution',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/evolution');
            },
          ),
          ListTile(
            leading: const Icon(Icons.toggle_on),
            title: const Text('Feature Flags'),
            selected: location == '/admin/feature-flags',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/feature-flags');
            },
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Auditoria & Segurança'),
            selected: location == '/admin/audit',
            onTap: () {
              Navigator.pop(context);
              context.go('/admin/audit');
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () {
              Navigator.pop(context);
              inject<AuthService>().logout();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
