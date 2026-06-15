import 'package:design_system_module/src/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTextField', () {
    testWidgets('renderiza label, hint e errorText corretamente', (tester) async {
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
  });
}
