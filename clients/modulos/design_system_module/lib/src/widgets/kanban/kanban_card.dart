import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';

/// Card de um item de Kanban (ex.: atendimento na fila), arrastável via
/// [Draggable] nativo do Flutter — decisão fechada do plano (sem dependência
/// de board externa). O [child] é o conteúdo (título/meta), fornecido pela
/// tela; este widget só cuida do visual/drag do card em si.
///
/// [data] é o payload carregado pelo drag (tipicamente o id do item + a etapa
/// de origem), consumido pelo [KanbanDropColumn] de destino.
class KanbanCard<T extends Object> extends StatelessWidget {
  final T data;
  final Widget child;
  final bool isDragging;

  const KanbanCard({
    super.key,
    required this.data,
    required this.child,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final surface = Container(
      width: 260,
      padding: const EdgeInsets.all(AppSpacing.padCard),
      margin: const EdgeInsets.only(bottom: AppSpacing.gapCard),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: colors.border),
      ),
      child: child,
    );

    return Opacity(
      opacity: isDragging ? 0.5 : 1,
      child: Draggable<T>(
        data: data,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(AppSpacing.padCard),
            decoration: BoxDecoration(
              color: colors.cardHover,
              borderRadius: AppRadius.card,
              border: Border.all(color: colors.accent, width: 2),
            ),
            child: child,
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: surface),
        child: surface,
      ),
    );
  }
}
