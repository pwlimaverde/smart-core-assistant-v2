import 'package:design_system_module/src/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors', () {
    test('copyWith substitui apenas os campos informados', () {
      const original = AppColors.light;
      final copia = original.copyWith(bg: Colors.red, accent: Colors.blue);

      expect(copia.bg, Colors.red);
      expect(copia.accent, Colors.blue);
      // Os demais campos permanecem os do original.
      expect(copia.fg, original.fg);
      expect(copia.card, original.card);
      expect(copia.danger, original.danger);
    });

    test(
      'copyWith sem argumentos retorna valores equivalentes ao original',
      () {
        const original = AppColors.dark;
        final copia = original.copyWith();

        expect(copia.bg, original.bg);
        expect(copia.accent, original.accent);
        expect(copia.infoSoft, original.infoSoft);
      },
    );

    test('lerp com t=0 aproxima o início e t=1 aproxima o fim', () {
      const inicio = AppColors.light;
      const fim = AppColors.dark;

      final noInicio = inicio.lerp(fim, 0);
      final noFim = inicio.lerp(fim, 1);

      expect(noInicio.bg, Color.lerp(inicio.bg, fim.bg, 0));
      expect(noFim.bg, Color.lerp(inicio.bg, fim.bg, 1));
      expect(noFim.accent, Color.lerp(inicio.accent, fim.accent, 1));
    });

    test(
      'lerp com um ThemeExtension de outro tipo retorna o próprio (this)',
      () {
        const original = AppColors.light;
        final resultado = original.lerp(null, 0.5);

        expect(identical(resultado, original), isTrue);
      },
    );
  });

  group('AppColorsX', () {
    testWidgets(
      'sem AppColors registrado no tema, cai no default (AppColors.light)',
      (tester) async {
        late AppColors resolved;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Builder(
              builder: (context) {
                resolved = context.colors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(resolved, equals(AppColors.light));
      },
    );

    testWidgets(
      'com AppColors.dark registrado, context.colors resolve a extensão',
      (tester) async {
        late AppColors resolved;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                resolved = context.colors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(resolved, equals(AppColors.dark));
      },
    );
  });
}
