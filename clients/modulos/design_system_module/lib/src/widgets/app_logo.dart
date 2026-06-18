import 'package:flutter/material.dart';

/// Variantes da marca Smart Core.
enum AppLogoVariant {
  /// Símbolo + wordmark ("Smart Core Assistant"). Adapta a cor ao tema.
  full,

  /// Logo redonda (símbolo + wordmark dentro de um círculo claro).
  mark,
}

/// Marca oficial do Smart Core, empacotada no design system.
///
/// A variante [AppLogoVariant.full] escolhe a arte clara (texto escuro) ou
/// branca conforme o brilho do tema, então funciona em fundo claro e escuro.
class AppLogo extends StatelessWidget {
  final double height;
  final AppLogoVariant variant;

  const AppLogo({
    super.key,
    this.height = 64,
    this.variant = AppLogoVariant.full,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = switch (variant) {
      AppLogoVariant.mark => 'assets/brand/logo_mark.png',
      AppLogoVariant.full => isDark
          ? 'assets/brand/logo_full_white.png'
          : 'assets/brand/logo_full.png',
    };

    return Image.asset(
      asset,
      package: 'design_system_module',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'Smart Core Assistant',
    );
  }
}
