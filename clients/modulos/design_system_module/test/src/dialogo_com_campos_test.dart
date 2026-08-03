import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `dispose()` num `TextEditingController` já descartado lança — é assim que
/// se prova, sem API pública de inspeção, que ele foi (ou não) descartado.
bool foiDescartado(TextEditingController c) {
  try {
    c.dispose();
    return false; // aceitou: ainda estava vivo
  } on FlutterError {
    return true;
  }
}

void main() {
  testWidgets('descarta os campos quando o diálogo fecha', (tester) async {
    final campo = TextEditingController(text: 'algo');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DialogoComCampos(
                campos: [campo],
                builder: (dialogContext) => AlertDialog(
                  content: TextField(controller: campo),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Fechar'));

    // O ponto do teste: durante a animação de saída o campo ainda é usado.
    // Descartar aqui — que é o que `showDialog(...).whenComplete()` faz —
    // quebra com "A TextEditingController was used after being disposed".
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'o campo não pode ser descartado durante a animação de saída',
    );

    await tester.pumpAndSettle();
    expect(foiDescartado(campo), isTrue);
  });

  testWidgets('descarta também quando o diálogo é fechado por fora', (
    tester,
  ) async {
    // Clicar no barrier e a tecla Escape saem pelo mesmo caminho: a rota é
    // removida sem passar por botão nenhum.
    final campo = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DialogoComCampos(
                campos: [campo],
                builder: (_) => AlertDialog(
                  content: TextField(controller: campo),
                ),
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10)); // barrier
    await tester.pumpAndSettle();

    expect(foiDescartado(campo), isTrue);
  });
}
