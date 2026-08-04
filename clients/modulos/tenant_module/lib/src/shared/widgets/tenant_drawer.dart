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
          // Rolável: o menu já passou de oito itens e cresce a cada tela nova.
          // Numa janela baixa, a Column rígida estourava e escondia o fim da
          // lista sem nem sinalizar que havia mais.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Item(
                  icone: Icons.view_kanban,
                  titulo: 'Atendimento (Kanban)',
                  rota: '/atendimentos',
                  atual: location,
                ),
                if (isTenantAdmin) ...[
                  const Divider(),
                  _Item(
                    icone: Icons.insights_outlined,
                    titulo: 'Painel',
                    rota: '/tenant/painel',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.contacts_outlined,
                    titulo: 'Contatos',
                    rota: '/tenant/contatos',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.groups_outlined,
                    titulo: 'Equipe',
                    rota: '/tenant/equipe',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.qr_code_2_outlined,
                    titulo: 'Conexões de WhatsApp',
                    rota: '/tenant/conexoes',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.school_outlined,
                    titulo: 'Treinamento da IA',
                    rota: '/tenant/treinamento',
                    atual: location,
                  ),
                  const Divider(),
                  _Item(
                    icone: Icons.mail_outline,
                    titulo: 'Convites',
                    rota: '/tenant/convites',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.people_outline,
                    titulo: 'Usuários',
                    rota: '/tenant/usuarios',
                    atual: location,
                  ),
                  _Item(
                    icone: Icons.settings_outlined,
                    titulo: 'Configuração do Tenant',
                    rota: '/tenant/config',
                    atual: location,
                  ),
                ],
              ],
            ),
          ),
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

/// Um destino do menu. Fecha o menu antes de navegar: deixá-lo aberto sobre a
/// tela nova esconderia justamente o que a pessoa acabou de pedir.
class _Item extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String rota;
  final String atual;

  const _Item({
    required this.icone,
    required this.titulo,
    required this.rota,
    required this.atual,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icone),
      title: Text(titulo),
      selected: atual == rota,
      onTap: () {
        Navigator.pop(context);
        context.go(rota);
      },
    );
  }
}
