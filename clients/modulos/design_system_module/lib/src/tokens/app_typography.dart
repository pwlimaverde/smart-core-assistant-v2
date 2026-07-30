import 'package:flutter/material.dart';

/// Escala tipográfica do design system.
///
/// Usa a família **Outfit**, empacotada em
/// `assets/fonts/` (declarada no `pubspec` deste módulo).
///
/// A fonte é empacotada, não vem de CDN: sem uma fonte de TEXTO no bundle, o
/// engine do Flutter Web busca a Roboto em `fonts.gstatic.com`, e o CSP da borda
/// bloqueia — a UI renderiza sem texto algum (só os ícones, que são asset
/// local). Todos os estilos abaixo herdam [fontFamily]; nenhuma tela muda.
abstract final class AppTypography {
  /// Família de marca (empacotada em `assets/fonts/`).
  ///
  /// O prefixo `packages/<pacote>/` é obrigatório: fonte declarada no `pubspec`
  /// de um PACOTE é registrada no `FontManifest.json` com esse namespace, e
  /// `fontFamily: 'Outfit'` puro não a encontraria — cairia silenciosamente na
  /// fonte default do engine, que é justamente o que se quer evitar. Equivale a
  /// `TextStyle(fontFamily: 'Outfit', package: 'design_system_module')`.
  static const String fontFamily = 'packages/design_system_module/Outfit';

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
