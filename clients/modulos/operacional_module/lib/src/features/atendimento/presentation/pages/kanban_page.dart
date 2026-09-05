import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/quadro.dart';
import '../controllers/kanban_controller.dart';
import '../controllers/kanban_state.dart';
import '../widgets/atendimento_card_content.dart';
import 'chat_page.dart';

/// Payload carregado pelo drag de um [KanbanCard] — id do atendimento e etapa
/// de origem (a coluna de onde saiu), consumido pela coluna de destino.
typedef _DragPayload = ({int atendimentoId, int etapaOrigemId});

/// Quadro de atendimento.
///
/// As colunas vêm do **fluxo cadastrado**, não dos atendimentos existentes.
/// Derivá-las dos dados fazia uma coluna vazia sumir — não havia para onde
/// arrastar — e um quadro sem conversa nenhuma abria em branco, como se
/// estivesse quebrado; era o que uma conta nova via.
///
/// O filtro de fluxo (`flow_permissions`) é 100% server-side: esta tela só
/// renderiza o que o backend devolve e reage ao erro se o movimento for negado.
class KanbanPage extends StatefulWidget {
  /// Menu lateral, injetado pelo app que monta a rota.
  ///
  /// O quadro é a primeira tela depois do login, e sem o menu não havia como
  /// chegar a nenhuma configuração — a pessoa ficava presa numa fila vazia. O
  /// menu mora no app do tenant; este módulo não o conhece, então ele entra por
  /// aqui em vez de virar uma dependência ao contrário.
  final Widget? drawer;

  /// Faixa de aviso acima do quadro, injetada pelo app do tenant.
  ///
  /// Existe para uma coisa em especial: WhatsApp fora do ar. O quadro parece
  /// normal quando a conexão cai — só não chega conversa nenhuma, e quem está
  /// atendendo demora a entender por quê. O aviso mora aqui, na primeira tela,
  /// e não numa página de configuração que ninguém abre. Como conexão é assunto
  /// do `tenant_module`, entra por injeção, igual ao menu.
  final Widget? aviso;

  const KanbanPage({this.drawer, this.aviso, super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  @override
  void initState() {
    super.initState();
    inject<KanbanController>().carregar();
  }

  @override
  Widget build(BuildContext context) {
    final controller = inject<KanbanController>();

    return AppScaffold(
      title: 'Atendimento',
      drawer: widget.drawer,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => controller.carregar(),
        ),
      ],
      // O aviso fica FORA do BlocBuilder: ele avisa que não chega conversa, e
      // some justamente quando o quadro está carregando ou falhou — que é
      // quando mais se precisa dele.
      body: Column(
        children: [
          if (widget.aviso != null) widget.aviso!,
          Expanded(
            child: BlocBuilder<KanbanController, ViewState<KanbanViewModel>>(
              bloc: controller,
              builder: (context, state) {
                return switch (state) {
                  InitialState() || LoadingState() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  ErrorState(:final error) => AppErrorView(
                    message: error.message,
                    onRetry: () => controller.carregar(),
                  ),
                  SuccessState(:final data) => _Quadro(
                    viewModel: data,
                    controller: controller,
                  ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Quadro extends StatelessWidget {
  final KanbanViewModel viewModel;
  final KanbanController controller;

  const _Quadro({required this.viewModel, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Conta sem fluxo nenhum: o convite é configurar, não "aguarde chegar
    // conversa" — sem quadro, nada chega a lugar nenhum.
    if (!viewModel.temQuadro) {
      return const AppEmptyView(
        icon: Icons.account_tree_outlined,
        title: 'Nenhum quadro configurado',
        subtitle: 'Crie um fluxo de atendimento em "Fluxos de atendimento" '
            'para que as conversas tenham por onde andar.',
      );
    }

    final soltas = viewModel.semColuna;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewModel.fluxos.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<int>(
                  value: viewModel.fluxoId,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final f in viewModel.fluxos)
                      DropdownMenuItem(value: f.id, child: Text(f.rotulo)),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.abrirQuadro(v);
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final coluna in viewModel.colunas)
                    _Coluna(
                      coluna: coluna,
                      itens:
                          viewModel.porEtapa[coluna.id] ??
                          const <AtendimentoResumo>[],
                      viewModel: viewModel,
                      controller: controller,
                    ),
                  // Conversas fora de qualquer coluna do quadro: chegaram antes
                  // do fluxo existir, ou apontam para uma coluna já removida.
                  // Escondê-las faria sumir atendimento de verdade.
                  if (soltas.isNotEmpty)
                    _Coluna(
                      coluna: const ColunaDoQuadro(
                        id: KanbanViewModel.semEtapa,
                        nome: 'Sem coluna',
                        cor: '#F59E0B',
                        ordem: 9999,
                        tipo: 'fila',
                      ),
                      itens: soltas,
                      viewModel: viewModel,
                      controller: controller,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Coluna extends StatelessWidget {
  final ColunaDoQuadro coluna;
  final List<AtendimentoResumo> itens;
  final KanbanViewModel viewModel;
  final KanbanController controller;

  const _Coluna({
    required this.coluna,
    required this.itens,
    required this.viewModel,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return KanbanDropColumn<_DragPayload>(
      title: coluna.nome,
      itemCount: itens.length,
      onAccept: (payload) {
        if (payload.etapaOrigemId == coluna.id) return;
        _moverComFeedback(
          context,
          atendimentoId: payload.atendimentoId,
          etapaOrigemId: payload.etapaOrigemId,
          etapaDestinoId: coluna.id,
        );
      },
      children: [
        for (final atendimento in itens)
          KanbanCard<_DragPayload>(
            key: ValueKey(atendimento.id),
            data: (atendimentoId: atendimento.id, etapaOrigemId: coluna.id),
            isDragging: viewModel.movendoAtendimentoId == atendimento.id,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatPage(atendimentoId: atendimento.id),
                      ),
                    ),
                    child: AtendimentoCardContent(atendimento: atendimento),
                  ),
                ),
                // O arrasto continua sendo o caminho principal; este menu
                // existe para o quadro que não tem coluna daquele tipo — sem
                // ele, não haveria como marcar uma conversa como pendente num
                // quadro de três colunas.
                _MenuDeEstado(
                  atendimento: atendimento,
                  controller: controller,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _moverComFeedback(
    BuildContext context, {
    required int atendimentoId,
    required int etapaOrigemId,
    required int etapaDestinoId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await controller.moverCard(
      atendimentoId: atendimentoId,
      etapaOrigemId: etapaOrigemId,
      etapaDestinoId: etapaDestinoId,
    );
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

/// Os estados que uma conversa pode assumir pela mão do atendente.
///
/// `arquivado` fica de fora: é decisão de curadoria do histórico, não do
/// atendimento em si, e oferecê-la aqui convidaria a sumir com conversa viva.
const _estadosOferecidos = <(String, String)>[
  ('em_atendimento', 'Assumir'),
  ('pendencia', 'Marcar como pendente'),
  ('fila', 'Devolver à fila'),
  ('resolvido', 'Resolver'),
  ('cancelado', 'Cancelar atendimento'),
];

class _MenuDeEstado extends StatelessWidget {
  final AtendimentoResumo atendimento;
  final KanbanController controller;

  const _MenuDeEstado({required this.atendimento, required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Mudar o estado',
      itemBuilder: (_) => [
        for (final (status, rotulo) in _estadosOferecidos)
          if (status != atendimento.status)
            PopupMenuItem(value: status, child: Text(rotulo)),
      ],
      onSelected: (status) async {
        final messenger = ScaffoldMessenger.of(context);
        final erro = await controller.definirStatus(
          atendimentoId: atendimento.id,
          status: status,
        );
        if (erro != null) {
          messenger.showSnackBar(SnackBar(content: Text(erro.message)));
        }
      },
    );
  }
}
