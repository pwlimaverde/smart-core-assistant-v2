import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/integracoes/presentation/widgets/aba_excluidos.dart';

class _ServicoFalso extends Mock implements ExclusaoService {}

Widget _app(ExclusaoService servico) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: AbaExcluidos(servico: servico)),
);

void main() {
  testWidgets('lista o que foi excluído, sem ação de restaurar', (
    tester,
  ) async {
    final servico = _ServicoFalso();
    when(() => servico.listarExcluidos()).thenAnswer(
      (_) async => [
        (
          tipo: 'contato',
          id: 546,
          rotulo: 'Paulo W',
          excluidoEm: DateTime(2026, 9, 27, 10, 30),
          excluidoPor: 'dono@ecoprint.com',
        ),
      ],
    );

    await tester.pumpWidget(_app(servico));
    await tester.pumpAndSettle();

    expect(find.text('Paulo W'), findsOneWidget);
    expect(
      find.textContaining('Contato · excluído em 27/09/2026 10:30'),
      findsOneWidget,
    );
    expect(find.textContaining('por dono@ecoprint.com'), findsOneWidget);
    expect(find.textContaining('Restaurar'), findsNothing);
  });

  testWidgets('sem excluídos, diz isso', (tester) async {
    final servico = _ServicoFalso();
    when(() => servico.listarExcluidos()).thenAnswer((_) async => []);

    await tester.pumpWidget(_app(servico));
    await tester.pumpAndSettle();

    expect(find.text('Nada foi excluído.'), findsOneWidget);
  });
}
