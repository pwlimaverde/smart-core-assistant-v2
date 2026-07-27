import 'package:design_system_module/src/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTextField', () {
    testWidgets('renderiza label, hint e errorText corretamente', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(
              label: 'Usuário',
              hint: 'Digite seu nome',
              errorText: 'Campo obrigatório',
            ),
          ),
        ),
      );

      expect(find.text('Usuário'), findsOneWidget);
      expect(find.text('Digite seu nome'), findsOneWidget);
      expect(find.text('Campo obrigatório'), findsOneWidget);
    });

    testWidgets('chama onChanged ao alterar o texto', (tester) async {
      var alterou = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextField(
              label: 'Texto',
              onChanged: (val) => alterou = val,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'novo valor');
      expect(alterou, 'novo valor');
    });

    testWidgets('campo de senha alterna a visibilidade pelo botão', (
      tester,
    ) async {
      // O olho de mostrar/ocultar senha é o único estado interno do widget:
      // sem exercitá-lo, o setState e o tooltip nunca rodam.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(
              label: 'Senha',
              obscureText: true,
              obscureToggle: true,
              prefixIcon: Icons.lock,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
    });
  });
}
