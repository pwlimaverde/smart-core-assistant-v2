import 'package:design_system_module/src/theme/app_colors.dart';
import 'package:design_system_module/src/theme/app_theme.dart';
import 'package:design_system_module/src/tokens/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('Tema light usa acento gold e registra a extensão de cores', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, equals(AppPalette.gold500));

      final colors = theme.extension<AppColors>();
      expect(colors, equals(AppColors.light));
      expect(colors!.bg, equals(AppPalette.stone100));
    });

    test('Tema dark registra a variante escura da extensão de cores', () {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, equals(AppPalette.gold500));
      expect(theme.extension<AppColors>(), equals(AppColors.dark));
    });
  });
}
