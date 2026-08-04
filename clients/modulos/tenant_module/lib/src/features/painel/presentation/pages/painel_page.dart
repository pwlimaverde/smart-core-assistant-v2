import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/painel.dart';
import '../controllers/painel_controllers.dart';

/// Painel do tenant.
///
/// A tela que faltava depois do login: até aqui o app abria direto na fila de
/// atendimento, que numa conta nova está vazia e não diz o que fazer.
///
/// A ordem dos números não é decorativa. Primeiro o que exige ação agora
/// (conversas na fila, conexão caída), depois o volume, por último a estrutura.
final class PainelPage extends StatefulWidget {
  const PainelPage({super.key});

  @override
  State<PainelPage> createState() => _PainelPageState();
}

class _PainelPageState extends State<PainelPage> {
  late final PainelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<PainelController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Painel',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ViewStateBuilder<PainelController, Painel>(
          controller: _controller,
          onError: (context, error) => AppErrorView(
            message: error.message,
            onRetry: _controller.carregar,
          ),
          onSuccess: (context, p) => ListView(
            children: [
              if (p.temConexaoCaida)
                _Aviso(
                  icone: Icons.link_off,
                  cor: Theme.of(context).colorScheme.error,
                  titulo: 'Uma conexão de WhatsApp caiu',
                  detalhe: '${p.conexoesAtivas} de ${p.conexoesTotal} '
                      'conectadas. Sem conexão, mensagem nenhuma entra.',
                  rotuloAcao: 'Ver conexões',
                  aoAgir: () => context.go('/tenant/conexoes'),
                )
              else if (p.faltaEstrutura)
                _Aviso(
                  icone: Icons.construction,
                  cor: Colors.orange,
                  titulo: 'Falta terminar a configuração',
                  detalhe: p.conexoesTotal == 0
                      ? 'Nenhum WhatsApp conectado ainda.'
                      : 'Nenhum departamento: a fila não tem para onde mandar '
                          'as conversas que chegam.',
                  rotuloAcao: p.conexoesTotal == 0
                      ? 'Conectar WhatsApp'
                      : 'Criar departamento',
                  aoAgir: () => context.go(
                    p.conexoesTotal == 0
                        ? '/tenant/conexoes'
                        : '/tenant/equipe',
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Agora',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _Numero(
                    rotulo: 'Na fila',
                    valor: p.aguardando,
                    icone: Icons.hourglass_top,
                    // Fila com gente esperando é o número que dói; destacar só
                    // quando há alguém evita alarme falso na conta vazia.
                    destaque: p.aguardando > 0,
                  ),
                  _Numero(
                    rotulo: 'Em atendimento',
                    valor: p.emAndamento,
                    icone: Icons.forum_outlined,
                  ),
                  _Numero(
                    rotulo: 'Mensagens (24h)',
                    valor: p.mensagens24h,
                    icone: Icons.mark_chat_read_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Estrutura',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _Numero(
                    rotulo: 'Conexões ativas',
                    valor: p.conexoesAtivas,
                    icone: Icons.qr_code_2,
                    sufixo: ' / ${p.conexoesTotal}',
                  ),
                  _Numero(
                    rotulo: 'Departamentos',
                    valor: p.departamentos,
                    icone: Icons.business_outlined,
                  ),
                  _Numero(
                    rotulo: 'Material treinado',
                    valor: p.treinamentosAtivos,
                    icone: Icons.school_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String detalhe;
  final String rotuloAcao;
  final VoidCallback aoAgir;

  const _Aviso({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.detalhe,
    required this.rotuloAcao,
    required this.aoAgir,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icone, color: cor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(fontWeight: FontWeight.bold, color: cor),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  detalhe,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.colors.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // O aviso leva à tela que resolve: dizer o problema sem oferecer o
          // caminho deixaria a pessoa procurando no menu.
          TextButton(onPressed: aoAgir, child: Text(rotuloAcao)),
        ],
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  final String rotulo;
  final int valor;
  final IconData icone;
  final String sufixo;
  final bool destaque;

  const _Numero({
    required this.rotulo,
    required this.valor,
    required this.icone,
    this.sufixo = '',
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = destaque
        ? Theme.of(context).colorScheme.primary
        : context.colors.fgMuted;

    return SizedBox(
      width: 210,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 18, color: cor),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    rotulo,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.colors.fgMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$valor$sufixo',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: destaque ? cor : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
