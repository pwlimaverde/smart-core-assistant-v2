import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/avatar_do_contato.dart';

/// P6 — a foto que não abre pede o contato de novo UMA vez e cai nas iniciais.
///
/// Em teste o `Image.network` sempre falha (o `HttpClient` do binding de
/// teste devolve 400), o que simula a URL assinada vencida.
void main() {
  const assinadaA =
      'https://r2.exemplo/contatos/4/avatar-aaaa1111.jpg?X-Amz-Signature=1';
  const assinadaB =
      'https://r2.exemplo/contatos/4/avatar-aaaa1111.jpg?X-Amz-Signature=2';
  const outraFoto =
      'https://r2.exemplo/contatos/4/avatar-bbbb2222.jpg?X-Amz-Signature=3';

  Future<void> montar(
    WidgetTester tester,
    String url,
    VoidCallback aoFalhar,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvatarDoContato(
            nome: 'Ana Lima',
            fotoUrl: url,
            aoFalharFoto: aoFalhar,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // O aviso sai depois do quadro em que o `errorBuilder` rodou.
    await tester.pump();
  }

  testWidgets('falha ao abrir pede a recarga uma vez e mostra as iniciais', (
    tester,
  ) async {
    var pedidos = 0;
    await montar(tester, assinadaA, () => pedidos++);

    expect(pedidos, 1);
    expect(find.text('AL'), findsOneWidget);

    // Redesenho com a mesma URL quebrada: nada de novo pedido.
    await montar(tester, assinadaA, () => pedidos++);
    expect(pedidos, 1);
    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets(
    'URL nova do mesmo objeto que também falha não pede de novo (sem laço)',
    (tester) async {
      var pedidos = 0;
      await montar(tester, assinadaA, () => pedidos++);
      expect(pedidos, 1);

      // A recarga trouxe outra assinatura do mesmo objeto, e ela também falha.
      await montar(tester, assinadaB, () => pedidos++);

      expect(pedidos, 1);
      expect(find.text('AL'), findsOneWidget);
    },
  );

  testWidgets('foto nova (outro objeto) que falha pode pedir uma vez', (
    tester,
  ) async {
    var pedidos = 0;
    await montar(tester, assinadaA, () => pedidos++);
    await montar(tester, outraFoto, () => pedidos++);

    expect(pedidos, 2);
    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets('sem URL, iniciais direto e nenhum pedido', (tester) async {
    var pedidos = 0;
    await montar(tester, '', () => pedidos++);

    expect(pedidos, 0);
    expect(find.text('AL'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
