import 'package:design_system_module/src/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogo', () {
    AssetImage assetOf(WidgetTester tester) {
      final image = tester.widget<Image>(find.byType(Image));
      return image.image as AssetImage;
    }

    testWidgets('variante full em tema claro usa a arte com texto escuro', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const AppLogo(),
        ),
      );

      expect(assetOf(tester).assetName, 'assets/brand/logo_full.png');
    });

    testWidgets('variante full em tema escuro usa a arte branca', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const AppLogo(),
        ),
      );

      expect(assetOf(tester).assetName, 'assets/brand/logo_full_white.png');
    });

    testWidgets('variante mark ignora o brilho do tema', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const AppLogo(variant: AppLogoVariant.mark),
        ),
      );

      expect(assetOf(tester).assetName, 'assets/brand/logo_mark.png');
    });

    testWidgets('respeita a altura customizada', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppLogo(height: 120)));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.height, 120);
    });
  });
}
