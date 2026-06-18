import 'package:flutter/material.dart';

/// Sombras do design system (espelham os tokens `--ws-shadow-*`).
///
/// Cada constante é a lista de [BoxShadow] pronta para um [BoxDecoration].
abstract final class AppShadows {
  static const List<BoxShadow> xs = [
    BoxShadow(
      color: Color(0x0A020617), // rgba(2,6,23,.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x0F020617), // rgba(2,6,23,.06)
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
    BoxShadow(
      color: Color(0x0A020617), // rgba(2,6,23,.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x14020617), // rgba(2,6,23,.08)
      offset: Offset(0, 6),
      blurRadius: 18,
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1A020617), // rgba(2,6,23,.10)
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// Sombra da mini-bar flutuante.
  static const List<BoxShadow> mini = [
    BoxShadow(
      color: Color(0x2E020617), // rgba(2,6,23,.18)
      offset: Offset(0, 12),
      blurRadius: 32,
    ),
  ];
}
