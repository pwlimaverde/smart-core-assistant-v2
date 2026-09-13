import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';

import '../../../permissoes_de_tela.dart';

/// Menu do app do tenant, **por escopo** (B2).
///
/// Era um `if (isTenantAdmin)` envolvendo nove itens: um `manager` autorizado
/// pelo servidor a editar fluxos não via o item de fluxos, e o papel
/// somente-leitura da D4 existia no backend e não na tela. Agora cada item
/// aparece para quem pode abrir a tela, pela mesma regra que o guard de rota usa
/// (`permissoes_de_tela.dart`) — nada visível leva a um redirect.
class TenantDrawer extends StatelessWidget {
  const TenantDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    // Sem sessão, nenhuma tela além do quadro: o menu não tem motivo para
    // presumir permissão.
    final escopos =
        inject<AuthService>().currentSession?.scopes ?? const <String>[];

    _Item? item(IconData icone, String titulo, String rota) =>
        podeAbrirTela(escopos, rota)
        ? _Item(icone: icone, titulo: titulo, rota: rota, atual: location)
        : null;

    final operacao = [
      item(Icons.insights_outlined, 'Painel', '/tenant/painel'),
      item(Icons.contacts_outlined, 'Contatos', '/tenant/contatos'),
      item(Icons.business_outlined, 'Clientes', '/tenant/clientes'),
      item(Icons.groups_outlined, 'Equipe', '/tenant/equipe'),
      item(
        Icons.account_tree_outlined,
        'Fluxos de atendimento',
        '/tenant/fluxos',
      ),
      item(
        Icons.dashboard_customize_outlined,
        'Campos do atendimento',
        '/tenant/campos',
      ),
      item(
        Icons.qr_code_2_outlined,
        'Conexões de WhatsApp',
        '/tenant/conexoes',
      ),
      item(Icons.school_outlined, 'Treinamento da IA', '/tenant/treinamento'),
    ].nonNulls.toList();

    final administracao = [
      item(Icons.mail_outline, 'Convites', '/tenant/convites'),
      item(Icons.people_outline, 'Usuários', '/tenant/usuarios'),
      item(Icons.settings_outlined, 'Configuração do Tenant', '/tenant/config'),
    ].nonNulls.toList();

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
                // Para qualquer sessão: os aplicativos de IA conectados são de
                // cada pessoa (N13.8). Esconder esta tela deixaria um `staff`
                // sem meio de desconectar um agente que ele mesmo autorizou.
                _Item(
                  icone: Icons.smart_toy_outlined,
                  titulo: 'Aplicativos conectados',
                  rota: '/tenant/integracoes',
                  atual: location,
                ),
                // Divisória só com o que dividir: um separador sobre grupo
                // vazio sugere que há algo escondido ali.
                if (operacao.isNotEmpty) ...[const Divider(), ...operacao],
                if (administracao.isNotEmpty) ...[
                  const Divider(),
                  ...administracao,
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
      // As subtelas contam como a mesma seção: em `/tenant/fluxos/3/etapas` o
      // menu ainda deve mostrar onde a pessoa está.
      selected: atual == rota || atual.startsWith('$rota/'),
      onTap: () {
        Navigator.pop(context);
        context.go(rota);
      },
    );
  }
}
