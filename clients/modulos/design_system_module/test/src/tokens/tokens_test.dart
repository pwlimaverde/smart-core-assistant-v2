import 'package:design_system_module/src/tokens/app_palette.dart';
import 'package:design_system_module/src/tokens/app_radius.dart';
import 'package:design_system_module/src/tokens/app_spacing.dart';
import 'package:design_system_module/src/tokens/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Design System Tokens', () {
    test('AppPalette possui as cores de marca (gold) e neutros (stone)', () {
      expect(AppPalette.gold500, equals(const Color(0xFFA98F71)));
      expect(AppPalette.gold600, equals(const Color(0xFF8B7355)));
      expect(AppPalette.stone100, equals(const Color(0xFFF5F5F4)));
      expect(AppPalette.stone900, equals(const Color(0xFF1C1917)));
    });

    test('AppRadius possui raios válidos', () {
      expect(AppRadius.sm, equals(const BorderRadius.all(Radius.circular(6))));
      expect(AppRadius.md, equals(const BorderRadius.all(Radius.circular(8))));
      expect(
        AppRadius.card,
        equals(const BorderRadius.all(Radius.circular(10))),
      );
      expect(
        AppRadius.pill,
        equals(const BorderRadius.all(Radius.circular(9999))),
      );
    });

    test('AppSpacing possui espaçamentos válidos', () {
      expect(AppSpacing.xs, equals(4.0));
      expect(AppSpacing.sm, equals(8.0));
      expect(AppSpacing.md, equals(16.0));
      expect(AppSpacing.lg, equals(24.0));
      expect(AppSpacing.xl, equals(32.0));
      expect(AppSpacing.xxl, equals(48.0));
    });

    test('AppTypography possui os estilos tipográficos configurados', () {
      expect(AppTypography.displayLarge, isA<TextStyle>());
      expect(AppTypography.headlineMedium, isA<TextStyle>());
      expect(AppTypography.titleLarge, isA<TextStyle>());
      expect(AppTypography.bodyLarge, isA<TextStyle>());
      expect(AppTypography.bodyMedium, isA<TextStyle>());
      expect(AppTypography.labelLarge, isA<TextStyle>());
    });
  });
}
