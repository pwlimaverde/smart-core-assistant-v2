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
            selected: location == '/dashboard',
            onTap: () {
              Navigator.pop(context);
              context.go('/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configurações Globais'),
            selected: location == '/core-settings',
            onTap: () {
              Navigator.pop(context);
              context.go('/core-settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Configurações de Tenant'),
            selected: location == '/tenant-config',
            onTap: () {
              Navigator.pop(context);
              context.go('/tenant-config');
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Clientes / Tenants'),
            selected: location == '/tenants',
            onTap: () {
              Navigator.pop(context);
              context.go('/tenants');
            },
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Usuários'),
            selected: location == '/usuarios',
            onTap: () {
              Navigator.pop(context);
              context.go('/usuarios');
            },
          ),
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Planos & Faturamento'),
            selected: location == '/billing',
            onTap: () {
              Navigator.pop(context);
              context.go('/billing');
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync_alt),
            title: const Text('Integração Evolution'),
            selected: location == '/evolution',
            onTap: () {
              Navigator.pop(context);
              context.go('/evolution');
            },
          ),
          ListTile(
            leading: const Icon(Icons.toggle_on),
            title: const Text('Feature Flags'),
            selected: location == '/feature-flags',
            onTap: () {
              Navigator.pop(context);
              context.go('/feature-flags');
            },
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Auditoria & Segurança'),
            selected: location == '/audit',
            onTap: () {
              Navigator.pop(context);
              context.go('/audit');
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Instalador Windows'),
            selected: location == '/windows-downloads',
            onTap: () {
              Navigator.pop(context);
              context.go('/windows-downloads');
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
