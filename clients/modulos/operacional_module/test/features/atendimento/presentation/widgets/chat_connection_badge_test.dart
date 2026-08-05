import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/chat_state.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/chat_connection_badge.dart';

/// O aviso de conexão é o que separa "ninguém respondeu ainda" de "sua mensagem
/// nem saiu daqui". Cada estado precisa dizer coisa diferente — um aviso
/// genérico faria o atendente esperar por uma resposta que não vem.
void main() {
  Future<void> montar(WidgetTester tester, ChatConnectionStatus status) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: ChatConnectionBadge(status: status)),
        ),
      );

  testWidgets('conectado não mostra nada', (tester) async {
    // Um selo verde permanente vira ruído: o normal não precisa de aviso.
    await montar(tester, ChatConnectionStatus.conectado);

    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('conectando avisa que ainda está subindo', (tester) async {
    await montar(tester, ChatConnectionStatus.conectando);

    expect(find.text('Conectando…'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });

  testWidgets('reconectando distingue queda de tentativa em curso', (
    tester,
  ) async {
    await montar(tester, ChatConnectionStatus.reconectando);

    expect(find.textContaining('reconectando'), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
  });

  testWidgets('caído diz que não há tempo real, sem prometer retorno', (
    tester,
  ) async {
    await montar(tester, ChatConnectionStatus.caido);

    expect(find.text('Sem conexão em tempo real.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}
