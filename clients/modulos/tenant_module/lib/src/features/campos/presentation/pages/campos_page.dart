import 'package:dependencies_module/dependencies_module.dart';

import '../../../../shared/widgets/tenant_drawer.dart';
import '../../domain/model/campo_personalizado.dart';
import '../controllers/campos_controller.dart';
import '../widgets/dialogo_campo.dart';

/// Campos do cartão de atendimento (N9 E13).
///
/// Cada tenant desenha a ficha que faz sentido para o negócio dele — número do
/// pedido, data de retorno, tipo de produto. A tabela existia desde a migration
/// 0006 e o repositório sabia criar; o que não existia era o caminho até aqui,
/// e por isso nenhum tenant tinha um campo sequer.
final class CamposPage extends StatefulWidget {
  const CamposPage({super.key});

  @override
  State<CamposPage> createState() => _CamposPageState();
}

class _CamposPageState extends State<CamposPage> {
  late final CamposController _controller;

  @override
  void initState() {
    super.initState();
    _controller = inject<CamposController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.carregar());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Campos do atendimento',
      drawer: const TenantDrawer(),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: _controller.carregar,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'O que cada atendimento registra',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Novo campo'),
                  onPressed: () => abrirCriacaoDeCampo(context, _controller),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Os campos aparecem na ficha da conversa. Quando você descreve '
              'bem o campo, a IA consegue preenchê-lo sozinha durante o '
              'atendimento.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child:
                  ViewStateBuilder<CamposController, List<CampoPersonalizado>>(
                    controller: _controller,
                    onError: (context, error) => AppErrorView(
                      message: error.message,
                      onRetry: _controller.carregar,
                    ),
                    onSuccess: (context, itens) => itens.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.dashboard_customize_outlined,
                            title: 'Nenhum campo ainda',
                            subtitle:
                                'Crie campos como "número do pedido" ou '
                                '"data de retorno" para registrar o que '
                                'importa em cada conversa.',
                          )
                        : ListView.separated(
                            itemCount: itens.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) => _Linha(
                              campo: itens[i],
                              controller: _controller,
                            ),
                          ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  final CampoPersonalizado campo;
  final CamposController controller;

  const _Linha({required this.campo, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        campo.nome,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          // Inativo continua na lista — os valores já
                          // coletados seguem na ficha —, mas não pode parecer
                          // em uso.
                          color: campo.ativo ? null : colors.fgMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Etiqueta(texto: campo.tipo.rotulo),
                    if (campo.obrigatorio) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _Etiqueta(texto: 'Obrigatório', destaque: true),
                    ],
                    if (!campo.ativo) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _Etiqueta(texto: 'Inativo'),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  campo.descricao.isEmpty
                      ? 'Sem descrição — a IA não saberá o que procurar.'
                      : campo.descricao,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: campo.descricao.isEmpty
                        ? colors.warning
                        : colors.fgMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      campo.extrairAutomaticamente
                          ? Icons.auto_awesome
                          : Icons.edit_outlined,
                      size: 14,
                      color: colors.fgMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        campo.extrairAutomaticamente
                            ? 'A IA tenta preencher durante a conversa'
                            : 'Só preenchimento manual',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.fgMuted),
                      ),
                    ),
                    // O slug fica visível: é ele que a IA usa para gravar o
                    // valor e que aparece no MCP. Escondê-lo criaria dois
                    // vocabulários para a mesma coisa.
                    Text(
                      campo.slug,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: colors.fgMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
            onPressed: () => abrirEdicaoDeCampo(context, campo, controller),
          ),
          if (campo.ativo)
            IconButton(
              icon: const Icon(Icons.visibility_off_outlined),
              tooltip: 'Desativar',
              onPressed: () => abrirDesativacao(context, campo, controller),
            ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final bool destaque;

  const _Etiqueta({required this.texto, this.destaque = false});

  @override
  Widget build(BuildContext context) {
    final cor = destaque ? context.colors.accent : context.colors.fgMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }
}
