import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/chat_message_bubble.dart';

MensagemThread _mensagem({
  bool geradoPorIa = false,
  String? resumoMidia,
  String remetente = 'bot',
}) => MensagemThread(
  id: 1,
  atendimentoId: 1,
  tipo: 'texto',
  conteudo: 'Olá, como posso ajudar?',
  remetente: remetente,
  timestamp: DateTime(2026, 1, 1, 10, 30),
  statusEnvio: 'enviado',
  geradoPorIa: geradoPorIa,
  resumoMidia: resumoMidia,
);

Future<void> _pump(WidgetTester tester, MensagemThread mensagem) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatMessageBubble(mensagem: mensagem)),
      ),
    );

void main() {
  group('ChatMessageBubble', () {
    testWidgets('sem indicador "Gerado por IA" quando geradoPorIa=false', (
      tester,
    ) async {
      await _pump(tester, _mensagem());

      expect(find.text('Gerado por IA'), findsNothing);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(find.text('Olá, como posso ajudar?'), findsOneWidget);
    });

    testWidgets('com indicador "Gerado por IA" quando geradoPorIa=true', (
      tester,
    ) async {
      await _pump(tester, _mensagem(geradoPorIa: true));

      expect(find.text('Gerado por IA'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('sem bloco de resumo quando resumoMidia=null', (tester) async {
      await _pump(tester, _mensagem());

      expect(find.text('Resumo da mídia'), findsNothing);
    });

    testWidgets('renderiza o resumo da mídia quando resumoMidia != null', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(resumoMidia: 'Áudio: cliente pede segunda via do boleto.'),
      );

      expect(find.text('Resumo da mídia'), findsOneWidget);
      expect(
        find.text('Áudio: cliente pede segunda via do boleto.'),
        findsOneWidget,
      );
    });
  });
}
