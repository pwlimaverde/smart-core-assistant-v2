import 'package:design_system_module/src/tokens/app_colors.dart';
import 'package:design_system_module/src/tokens/app_radius.dart';
import 'package:design_system_module/src/tokens/app_spacing.dart';
import 'package:design_system_module/src/tokens/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Design System Tokens', () {
    test('AppColors possui as cores do tema', () {
      expect(AppColors.primary, equals(const Color(0xFF1E88E5)));
      expect(AppColors.secondary, equals(const Color(0xFF26C6DA)));
      expect(AppColors.background, equals(const Color(0xFF121212)));
      expect(AppColors.backgroundLight, equals(const Color(0xFFF5F5F5)));
    });

    test('AppRadius possui raios válidos', () {
      expect(AppRadius.sm, equals(const BorderRadius.all(Radius.circular(4))));
      expect(AppRadius.md, equals(const BorderRadius.all(Radius.circular(8))));
      expect(AppRadius.lg, equals(const BorderRadius.all(Radius.circular(16))));
      expect(AppRadius.pill, equals(const BorderRadius.all(Radius.circular(50))));
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
