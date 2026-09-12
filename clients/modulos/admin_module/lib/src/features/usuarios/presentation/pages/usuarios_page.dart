import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/admin_drawer.dart';
import '../../domain/model/usuario_global.dart';
import '../controllers/usuarios_controller.dart';

/// Usuários de todos os tenants (D7).
///
/// A v1 tinha esta lista no admin do Django. Na v2 só existia
/// `ListTenantUsers`, que resolve o tenant a partir de quem chama — o
/// superusuário não tinha por onde responder "esse cliente consegue entrar?".
class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  late final UsuariosController _controller;
  final _busca = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = inject<UsuariosController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  /// A busca é server-side: cada tecla seria uma varredura, e a última nem
  /// seria a que responde. O atraso é o mesmo já usado na tela de contatos.
  void _aoDigitar(String termo) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _controller.carregar(busca: termo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Usuários',
      drawer: const AdminDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => _controller.carregar(),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Buscar',
              hint: 'Nome, usuário ou e-mail',
              controller: _busca,
              onChanged: _aoDigitar,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ViewStateBuilder<UsuariosController, List<UsuarioGlobal>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: () => _controller.carregar(),
                ),
                onSuccess: (context, usuarios) => usuarios.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.person_search_outlined,
                        title: 'Nenhum usuário encontrado',
                        subtitle: 'Ajuste a busca ou limpe o filtro.',
                      )
                    : ListView.separated(
                        itemCount: usuarios.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _LinhaUsuario(
                          usuario: usuarios[i],
                          aoAlternar: (ativo) =>
                              _alternar(context, usuarios[i], ativo),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirma só ao BLOQUEAR: desbloquear é inofensivo e reversível, mas
  /// bloquear tira alguém do sistema — e quem esbarrou no controle sem querer
  /// só descobriria pelo chamado de suporte do outro lado.
  Future<void> _alternar(
    BuildContext context,
    UsuarioGlobal usuario,
    bool ativo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!ativo) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bloquear o acesso?'),
          content: Text(
            '${usuario.exibicao} deixa de conseguir entrar no sistema. '
            'As conversas e os dados continuam intactos — só o login é '
            'recusado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Bloquear'),
            ),
          ],
        ),
      );
      if (confirmou != true) return;
    }

    final erro = await _controller.definirAtivo(
      userId: usuario.id,
      ativo: ativo,
    );
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

class _LinhaUsuario extends StatelessWidget {
  final UsuarioGlobal usuario;
  final ValueChanged<bool> aoAlternar;

  const _LinhaUsuario({required this.usuario, required this.aoAlternar});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    final vinculo = usuario.vinculo;

    return ListTile(
      leading: CircleAvatar(
        child: Icon(
          usuario.superusuario ? Icons.shield_outlined : Icons.person_outline,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(usuario.exibicao)),
          if (!usuario.ativo) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('Bloqueado'),
              visualDensity: VisualDensity.compact,
              backgroundColor: context.colors.warning.withValues(alpha: 0.15),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          usuario.email.isEmpty ? usuario.username : usuario.email,
          // Superusuário não pertence a tenant nenhum; dizer isso é melhor que
          // uma coluna vazia que parece dado faltando.
          if (vinculo.isNotEmpty)
            usuario.tenantDono.isNotEmpty ? 'dono de $vinculo' : vinculo
          else if (usuario.superusuario)
            'superusuário do sistema',
          if (usuario.papel.isNotEmpty && usuario.tenantDono.isEmpty)
            usuario.papel,
          usuario.ultimoLogin == null
              ? 'nunca entrou'
              : 'último acesso em ${_data(usuario.ultimoLogin!)}',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      ),
      trailing: Tooltip(
        message: usuario.ativo ? 'Bloquear o acesso' : 'Desbloquear o acesso',
        child: Switch(value: usuario.ativo, onChanged: aoAlternar),
      ),
    );
  }

  String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
