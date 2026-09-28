import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta um botão que abre o diálogo e guarda o resultado.
Future<List<bool>> _abrir(
  WidgetTester tester, {
  required DescricaoDeExclusao descricao,
  required Future<String?> Function(String) excluir,
}) async {
  final resultados = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => resultados.add(
            await abrirExclusaoDefinitiva(
              context,
              oQue: 'o contato',
              simular: () async => descricao,
              excluir: excluir,
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultados;
}

FilledButton _botao(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Excluir definitivamente'),
);

void main() {
  testWidgets('só libera a exclusão com o nome digitado', (tester) async {
    final confirmados = <String>[];
    final resultados = await _abrir(
      tester,
      descricao: (rotulo: 'Paulo W', conversas: 2, emUso: ''),
      excluir: (c) async {
        confirmados.add(c);
        return null;
      },
    );

    expect(find.textContaining('não pode ser restaurado'), findsOneWidget);
    expect(find.textContaining('2 conversa(s)'), findsOneWidget);
    expect(_botao(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Paulo');
    await tester.pump();
    expect(_botao(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Paulo W');
    await tester.pump();
    await tester.tap(find.text('Excluir definitivamente'));
    await tester.pumpAndSettle();

    expect(confirmados, ['Paulo W']);
    expect(resultados, [true]);
  });

  testWidgets('mostra o erro do servidor e não fecha', (tester) async {
    final resultados = await _abrir(
      tester,
      descricao: (rotulo: 'Nota', conversas: 0, emUso: ''),
      excluir: (_) async => 'o nome digitado não é o do item',
    );

    await tester.enterText(find.byType(TextField), 'Nota');
    await tester.pump();
    await tester.tap(find.text('Excluir definitivamente'));
    await tester.pumpAndSettle();

    expect(find.text('o nome digitado não é o do item'), findsOneWidget);
    expect(resultados, isEmpty);
  });

  testWidgets('item em uso não oferece a exclusão', (tester) async {
    final resultados = await _abrir(
      tester,
      descricao: (rotulo: 'Vendas', conversas: 0, emUso: 'há 2 conversa(s)'),
      excluir: (_) async => fail('não pode excluir item em uso'),
    );

    expect(find.textContaining('há 2 conversa(s)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(resultados, [false]);
  });
}
