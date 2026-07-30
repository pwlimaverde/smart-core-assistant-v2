import 'package:flutter/material.dart';

import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'app_colors.dart';

/// Temas Material 3 do design system (gold + stone).
///
/// O tema é montado a partir dos tokens semânticos [AppColors], registrados
/// também como [ThemeExtension] para que telas leiam cores via `context.colors`.
/// O tema **claro** é o padrão do app; o escuro é a variante opcional.
abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);

  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accentHover,
      onSecondary: Colors.white,
      surface: c.card,
      onSurface: c.fgStrong,
      error: c.danger,
      onError: Colors.white,
      outline: c.border,
      outlineVariant: c.divider,
    );

    final textTheme = AppTypography.textTheme(fg: c.fg, fgStrong: c.fgStrong);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      // `fontFamily` no tema alcança o que o `textTheme` não alcança: widget que
      // constrói `TextStyle` do zero, ou tema de componente que não deriva do
      // textTheme, cairia na fonte default do engine — que no Web significa
      // buscar a Roboto em fonts.gstatic.com e ficar SEM TEXTO quando o CSP
      // bloqueia. Com a família declarada aqui, todo texto usa a fonte do bundle.
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      extensions: [c],
      dividerColor: c.divider,
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputBg,
        hintStyle: TextStyle(color: c.fgSubtle),
        labelStyle: TextStyle(color: c.fgMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.fgSubtle,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          textStyle: AppTypography.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.accentHover),
      ),
    );
  }
}
