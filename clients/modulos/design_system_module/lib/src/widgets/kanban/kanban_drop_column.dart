import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';

/// Coluna de Kanban com área de drop ([DragTarget] nativo do Flutter —
/// decisão fechada do plano, sem dependência de board externa).
///
/// [onAccept] recebe o [data] carregado pelo [KanbanCard] solto nesta coluna
/// (a tela decide o que fazer — tipicamente despachar o movimento de etapa).
/// [itemCount] só alimenta o contador do cabeçalho; os cards em si são
/// passados via [children] (a tela monta a lista de [KanbanCard]s).
class KanbanDropColumn<T extends Object> extends StatelessWidget {
  final String title;
  final int itemCount;
  final List<Widget> children;
  final void Function(T data) onAccept;
  final bool Function(T data)? onWillAccept;

  const KanbanDropColumn({
    super.key,
    required this.title,
    required this.itemCount,
    required this.children,
    required this.onAccept,
    this.onWillAccept,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DragTarget<T>(
      onWillAcceptWithDetails: (details) =>
          onWillAccept?.call(details.data) ?? true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final destacado = candidateData.isNotEmpty;
        return Container(
          width: 292,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: destacado ? colors.accentSoft : colors.panel,
            borderRadius: AppRadius.col,
            border: Border.all(
              color: destacado ? colors.accent : colors.border,
              width: destacado ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: colors.fgStrong),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.chip,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        '$itemCount',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.fgMuted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Column(children: children),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
