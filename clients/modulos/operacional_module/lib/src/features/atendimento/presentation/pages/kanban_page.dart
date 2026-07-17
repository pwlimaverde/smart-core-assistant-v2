import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/atendimento_resumo.dart';
import '../controllers/kanban_controller.dart';
import '../controllers/kanban_state.dart';
import '../widgets/atendimento_card_content.dart';
import 'chat_page.dart';

/// Payload carregado pelo drag de um [KanbanCard] — id do atendimento e etapa
/// de origem (a coluna de onde saiu), consumido pela coluna de destino.
typedef _DragPayload = ({int atendimentoId, int etapaOrigemId});

/// Tela de fila/Kanban por departamento (WS-6.2): colunas dinâmicas agrupadas
/// pela etapa atual dos atendimentos retornados pelo backend. Mover um card
/// entre colunas despacha [KanbanController.moverCard] — o filtro de fluxo
/// (`flow_permissions`, WS-5a) é 100% server-side; esta tela só renderiza o
/// que o backend devolve e reage ao erro se o movimento for negado.
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  @override
  void initState() {
    super.initState();
    inject<KanbanController>().carregarFila();
  }

  @override
  Widget build(BuildContext context) {
    final controller = inject<KanbanController>();

    return AppScaffold(
      title: 'Fila de atendimento',
      body: BlocBuilder<KanbanController, ViewState<KanbanViewModel>>(
        bloc: controller,
        builder: (context, state) {
          return switch (state) {
            InitialState() || LoadingState() => const Center(
              child: CircularProgressIndicator(),
            ),
            ErrorState(:final error) => AppErrorView(
              message: error.message,
              onRetry: () => controller.carregarFila(),
            ),
            SuccessState(:final data) => _KanbanBoard(
              viewModel: data,
              controller: controller,
            ),
          };
        },
      ),
    );
  }
}

class _KanbanBoard extends StatelessWidget {
  final KanbanViewModel viewModel;
  final KanbanController controller;

  const _KanbanBoard({required this.viewModel, required this.controller});

  /// Convenção de etapas fixas para o MVP (fila → em atendimento → resolvido).
  /// Etapas adicionais retornadas pelo backend aparecem automaticamente ao
  /// final — nenhuma tela precisa ser alterada quando um novo fluxo/etapa
  /// for cadastrado (o agrupamento vem 100% dos dados).
  static const _colunaFila = KanbanViewModel.semEtapa;

  @override
  Widget build(BuildContext context) {
    final etapas = viewModel.porEtapa.keys.toList()..sort();

    if (etapas.isEmpty) {
      return const AppEmptyView(
        icon: Icons.inbox_outlined,
        title: 'Nenhum atendimento na fila',
        subtitle: 'Novos atendimentos aparecem aqui automaticamente.',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final etapaId in etapas)
              KanbanDropColumn<_DragPayload>(
                title: etapaId == _colunaFila ? 'Fila' : 'Etapa $etapaId',
                itemCount: viewModel.porEtapa[etapaId]?.length ?? 0,
                onAccept: (payload) {
                  if (payload.etapaOrigemId == etapaId) return;
                  _moverComFeedback(
                    context,
                    atendimentoId: payload.atendimentoId,
                    etapaOrigemId: payload.etapaOrigemId,
                    etapaDestinoId: etapaId,
                  );
                },
                children: [
                  for (final atendimento in viewModel.porEtapa[etapaId] ?? const <AtendimentoResumo>[])
                    KanbanCard<_DragPayload>(
                      key: ValueKey(atendimento.id),
                      data: (
                        atendimentoId: atendimento.id,
                        etapaOrigemId: etapaId,
                      ),
                      isDragging: viewModel.movendoAtendimentoId == atendimento.id,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(atendimentoId: atendimento.id),
                          ),
                        ),
                        child: AtendimentoCardContent(
                          atendimento: atendimento,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
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
