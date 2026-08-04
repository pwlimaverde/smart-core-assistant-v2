import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';

/// Menu do app do tenant. As telas administrativas (convites/usuários/config)
/// só aparecem para sessões com escopo `tenant:admin` — RBAC de UI (defesa em
/// profundidade; o backend já barra por escopo mesmo se alguém forçar a URL).
class TenantDrawer extends StatelessWidget {
  const TenantDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isTenantAdmin =
        inject<AuthService>().currentSession?.isTenantAdmin ?? false;

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: const Center(
              child: Text(
                'Smart Core Tenant',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_kanban),
            title: const Text('Atendimento (Kanban)'),
            selected: location == '/atendimentos',
            onTap: () {
              Navigator.pop(context);
              context.go('/atendimentos');
            },
          ),
          if (isTenantAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Convites'),
              selected: location == '/tenant/convites',
              onTap: () {
                Navigator.pop(context);
                context.go('/tenant/convites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Usuários'),
              selected: location == '/tenant/usuarios',
              onTap: () {
                Navigator.pop(context);
                context.go('/tenant/usuarios');
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('Conexões de WhatsApp'),
              selected: location == '/tenant/conexoes',
              onTap: () {
                Navigator.pop(context);
                context.go('/tenant/conexoes');
              },
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Treinamento da IA'),
              selected: location == '/tenant/treinamento',
              onTap: () {
                Navigator.pop(context);
                context.go('/tenant/treinamento');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Configuração do Tenant'),
              selected: location == '/tenant/config',
              onTap: () {
                Navigator.pop(context);
                context.go('/tenant/config');
              },
            ),
          ],
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
