import 'package:flutter/animation.dart';

/// Durações e curvas de animação do design system (tokens `--ws-dur-*`/`--ws-ease`).
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);

  /// Curva padrão de transição — `cubic-bezier(0.2, 0.6, 0.2, 1)`.
  static const Curve ease = Cubic(0.2, 0.6, 0.2, 1);
}
