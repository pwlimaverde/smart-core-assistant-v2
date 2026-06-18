import 'package:flutter/material.dart';

import '../tokens/app_palette.dart';

/// Tokens de cor semânticos do design system, sensíveis ao tema (claro/escuro).
///
/// É a única superfície de cor que telas e módulos devem consumir. Registrado
/// como [ThemeExtension] no [ThemeData], então o valor correto para o tema
/// ativo é resolvido por `context.colors` (ver [AppColorsX]).
///
/// Espelha os tokens `--ws-*` do design original: cada campo tem o mesmo papel
/// semântico (fundo, texto, borda, acento, feedback) nas variantes claro/escuro.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  // Fundo e texto
  final Color bg;
  final Color fg;
  final Color fgStrong;
  final Color fgMuted;
  final Color fgSubtle;

  // Superfícies
  final Color card;
  final Color cardHover;
  final Color panel;
  final Color chip;
  final Color inputBg;

  // Bordas
  final Color border;
  final Color borderStrong;
  final Color divider;

  // Estruturas escuras fixas (topbar/sidebar) — escuras em ambos os temas
  final Color topbar;
  final Color topbarFg;
  final Color sidebar;
  final Color sidebarFg;

  // Acento de marca (gold)
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color accentRing;

  // Feedback
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  const AppColors({
    required this.bg,
    required this.fg,
    required this.fgStrong,
    required this.fgMuted,
    required this.fgSubtle,
    required this.card,
    required this.cardHover,
    required this.panel,
    required this.chip,
    required this.inputBg,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.topbar,
    required this.topbarFg,
    required this.sidebar,
    required this.sidebarFg,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentRing,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  /// Tokens do tema claro (padrão do app).
  static const AppColors light = AppColors(
    bg: AppPalette.stone100,
    fg: AppPalette.stone700,
    fgStrong: AppPalette.stone900,
    fgMuted: AppPalette.stone500,
    fgSubtle: AppPalette.stone400,
    card: AppPalette.white,
    cardHover: AppPalette.white,
    panel: AppPalette.white,
    chip: AppPalette.stone100,
    inputBg: AppPalette.white,
    border: AppPalette.stone200,
    borderStrong: AppPalette.stone300,
    divider: AppPalette.stone100,
    topbar: AppPalette.stone900,
    topbarFg: AppPalette.stone100,
    sidebar: AppPalette.stone900,
    sidebarFg: AppPalette.stone300,
    accent: AppPalette.gold500,
    accentHover: AppPalette.gold600,
    accentSoft: AppPalette.accentSoft,
    accentRing: AppPalette.accentRing,
    success: AppPalette.success,
    successSoft: AppPalette.successSoft,
    warning: AppPalette.warning,
    warningSoft: AppPalette.warningSoft,
    danger: AppPalette.danger,
    dangerSoft: AppPalette.dangerSoft,
    info: AppPalette.info,
    infoSoft: AppPalette.infoSoft,
  );

  /// Tokens do tema escuro — sobrescreve apenas as cores; papéis idênticos.
  static const AppColors dark = AppColors(
    bg: AppPalette.dark900,
    fg: AppPalette.darkFg,
    fgStrong: AppPalette.darkFgStrong,
    fgMuted: AppPalette.darkFgMuted,
    fgSubtle: AppPalette.darkFgSubtle,
    card: AppPalette.dark700,
    cardHover: AppPalette.dark600,
    panel: AppPalette.dark800,
    chip: AppPalette.dark500,
    inputBg: AppPalette.dark600,
    border: AppPalette.dark500,
    borderStrong: AppPalette.dark400,
    divider: AppPalette.dark600,
    topbar: AppPalette.darkTopbar,
    topbarFg: AppPalette.darkFgStrong,
    sidebar: AppPalette.darkTopbar,
    sidebarFg: AppPalette.darkFg,
    accent: AppPalette.gold500,
    accentHover: AppPalette.gold600,
    accentSoft: AppPalette.accentSoft,
    accentRing: AppPalette.accentRing,
    success: AppPalette.success,
    successSoft: AppPalette.successSoft,
    warning: AppPalette.warning,
    warningSoft: AppPalette.warningSoft,
    danger: AppPalette.danger,
    dangerSoft: AppPalette.dangerSoft,
    info: AppPalette.info,
    infoSoft: AppPalette.infoSoft,
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? fg,
    Color? fgStrong,
    Color? fgMuted,
    Color? fgSubtle,
    Color? card,
    Color? cardHover,
    Color? panel,
    Color? chip,
    Color? inputBg,
    Color? border,
    Color? borderStrong,
    Color? divider,
    Color? topbar,
    Color? topbarFg,
    Color? sidebar,
    Color? sidebarFg,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? accentRing,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      fg: fg ?? this.fg,
      fgStrong: fgStrong ?? this.fgStrong,
      fgMuted: fgMuted ?? this.fgMuted,
      fgSubtle: fgSubtle ?? this.fgSubtle,
      card: card ?? this.card,
      cardHover: cardHover ?? this.cardHover,
      panel: panel ?? this.panel,
      chip: chip ?? this.chip,
      inputBg: inputBg ?? this.inputBg,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      divider: divider ?? this.divider,
      topbar: topbar ?? this.topbar,
      topbarFg: topbarFg ?? this.topbarFg,
      sidebar: sidebar ?? this.sidebar,
      sidebarFg: sidebarFg ?? this.sidebarFg,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      accentRing: accentRing ?? this.accentRing,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgStrong: Color.lerp(fgStrong, other.fgStrong, t)!,
      fgMuted: Color.lerp(fgMuted, other.fgMuted, t)!,
      fgSubtle: Color.lerp(fgSubtle, other.fgSubtle, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardHover: Color.lerp(cardHover, other.cardHover, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      topbar: Color.lerp(topbar, other.topbar, t)!,
      topbarFg: Color.lerp(topbarFg, other.topbarFg, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarFg: Color.lerp(sidebarFg, other.sidebarFg, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentRing: Color.lerp(accentRing, other.accentRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
    );
  }
}

/// Açúcar para ler os tokens semânticos do tema ativo: `context.colors.accent`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
