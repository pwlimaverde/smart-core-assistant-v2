import 'package:flutter/material.dart';

/// Raios de borda do design system (espelham os tokens `--ws-radius-*`).
abstract final class AppRadius {
  /// Tags pequenas — 6dp.
  static const BorderRadius sm = BorderRadius.all(Radius.circular(6));

  /// Botões compactos e inputs — 8dp.
  static const BorderRadius md = BorderRadius.all(Radius.circular(8));

  /// Cards e bolhas — 10dp.
  static const BorderRadius card = BorderRadius.all(Radius.circular(10));

  /// Colunas de kanban — 14dp.
  static const BorderRadius col = BorderRadius.all(Radius.circular(14));

  /// Painéis maiores — 16dp.
  static const BorderRadius panel = BorderRadius.all(Radius.circular(16));

  /// CTAs e pills — totalmente arredondado.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(9999));
}
