/// Escala de espaçamento do design system (múltiplos de 4 dp).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // --------------------------------------------------------------------------
  // Densidade e padding de superfícies (espelham os tokens `--ws-pad-*`).
  // --------------------------------------------------------------------------
  /// Padding interno de um card de kanban.
  static const double padCard = 12;

  /// Gap entre cards numa coluna.
  static const double gapCard = 8;

  /// Padding interno de painéis.
  static const double padPanel = 16;

  /// Padding interno de seções de um drawer/painel de detalhe.
  static const double padSection = 20;
}
