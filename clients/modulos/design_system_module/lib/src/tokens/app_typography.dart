import 'package:flutter/material.dart';

/// Escala tipográfica do design system.
///
/// O design original usa a família **Outfit**. A fonte ainda não está empacotada
/// no app; quando for adicionada (asset + `pubspec`), basta definir [fontFamily]
/// que todos os estilos herdam — nenhuma tela precisa mudar. Enquanto isso, a
/// fonte do sistema é usada como fallback.
abstract final class AppTypography {
  /// Família de marca. `null` enquanto a fonte não está empacotada.
  static const String? fontFamily = null;

  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
  );
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.42,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// Monta o [TextTheme] para o [ThemeData], colorindo os estilos conforme o
  /// texto padrão/forte do tema.
  static TextTheme textTheme({required Color fg, required Color fgStrong}) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: fgStrong),
      headlineMedium: headlineMedium.copyWith(color: fgStrong),
      titleLarge: titleLarge.copyWith(color: fgStrong),
      titleMedium: titleMedium.copyWith(color: fgStrong),
      bodyLarge: bodyLarge.copyWith(color: fg),
      bodyMedium: bodyMedium.copyWith(color: fg),
      bodySmall: bodySmall.copyWith(color: fg),
      labelLarge: labelLarge.copyWith(color: fgStrong),
      labelSmall: labelSmall.copyWith(color: fg),
    );
  }
}
