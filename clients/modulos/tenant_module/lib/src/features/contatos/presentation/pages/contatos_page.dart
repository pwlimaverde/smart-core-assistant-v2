import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/contato.dart';
import '../controllers/contatos_controllers.dart';

/// Contatos do tenant — quem já falou com a empresa pelo WhatsApp.
///
/// A v1 tinha esta tela no admin do tenant; sem ela não há como responder
/// "esse número que ligou é cliente nosso?" sem abrir a conversa.
final class ContatosPage extends StatefulWidget {
  const ContatosPage({super.key});

  @override
  State<ContatosPage> createState() => _ContatosPageState();
}

class _ContatosPageState extends State<ContatosPage> {
  late final ContatosController _controller;
  final _busca = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = inject<ContatosController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  /// Cada tecla é uma consulta ao banco; sem o atraso, digitar um nome de dez
  /// letras dispararia dez varreduras e a última nem seria a que responde.
  void _aoDigitar(String texto) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _controller.carregar(busca: texto.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Contatos',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => _controller.carregar(),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _busca,
              onChanged: _aoDigitar,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar por nome ou telefone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ViewStateBuilder<ContatosController, List<Contato>>(
                controller: _controller,
                onError: (context, error) => AppErrorView(
                  message: error.message,
                  onRetry: () => _controller.carregar(),
                ),
                onSuccess: (context, contatos) {
                  if (contatos.isEmpty) {
                    // Lista vazia por filtro e lista vazia por conta nova são
                    // problemas diferentes; o mesmo texto para os dois mandaria
                    // quem filtrou procurar erro onde não há.
                    return AppEmptyView(
                      title: _controller.busca.isEmpty
                          ? 'Nenhum contato ainda'
                          : 'Nada encontrado',
                      subtitle: _controller.busca.isEmpty
                          ? 'Os contatos aparecem sozinhos quando alguém manda '
                              'mensagem para o seu WhatsApp.'
                          : 'Nenhum contato casa com "${_controller.busca}".',
                    );
                  }

                  return ListView.separated(
                    itemCount: contatos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LinhaContato(item: contatos[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaContato extends StatelessWidget {
  final Contato item;

  const _LinhaContato({required this.item});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(
              item.exibicao.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.exibicao,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!item.ativo) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Etiqueta(texto: 'Inativo', cor: muted),
                    ] else if (item.semNome) ...[
                      const SizedBox(width: AppSpacing.sm),
                      // Contato sem nome nenhum é o que o operador precisa
                      // completar — marcar evita que ele se perca na lista.
                      const _Etiqueta(texto: 'Sem cadastro', cor: Colors.orange),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (item.telefone.isNotEmpty) item.telefone,
                    if (item.email.isNotEmpty) item.email,
                  ].join(' · '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            _quando(item.ultimaInteracao),
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Há quanto tempo foi a última mensagem. A data absoluta obrigaria a fazer a
/// conta de cabeça — o que interessa aqui é se foi hoje ou há meses.
String _quando(DateTime quando) {
  final dias = DateTime.now().difference(quando).inDays;
  if (dias <= 0) return 'hoje';
  if (dias == 1) return 'ontem';
  if (dias < 30) return 'há $dias dias';
  if (dias < 365) return 'há ${dias ~/ 30} meses';
  return 'há ${dias ~/ 365} anos';
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color cor;

  const _Etiqueta({required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cor,
        ),
      ),
    );
  }
}
