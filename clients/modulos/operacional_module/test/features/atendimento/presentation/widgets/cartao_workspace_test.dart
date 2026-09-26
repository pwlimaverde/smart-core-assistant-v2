import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/atendimento_card_content.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/mini_barra_da_conversa.dart';

/// O cartão do workspace: quem é, o que foi dito por último e os sinais do
/// atendimento — o `kanban_card.html` do desenho.
void main() {
  AtendimentoResumo resumo({
    String ultimaMensagem = '',
    String tipo = '',
    String remetente = '',
    String atendente = '',
    int naoLidas = 0,
    String prioridade = 'normal',
  }) => AtendimentoResumo(
    id: 3,
    contatoId: 3,
    status: 'fila',
    assunto: 'Orçamento',
    prioridade: prioridade,
    dataInicio: DateTime(2026, 1, 1),
    contatoNome: 'Ana Lima',
    contatoTelefone: '5581999990000',
    ultimaMensagem: ultimaMensagem,
    ultimaMensagemTipo: tipo,
    ultimaMensagemRemetente: remetente,
    atendenteNome: atendente,
    naoLidas: naoLidas,
  );

  Future<void> montar(WidgetTester tester, Widget filho) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(body: SizedBox(width: 280, child: filho)),
    ),
  );

  group('prévia da última mensagem', () {
    test('o que o contato disse aparece como está', () {
      final a = resumo(ultimaMensagem: 'Bom dia', remetente: 'contato');
      expect(previaDaUltimaMensagem(a), 'Bom dia');
    });

    test('o que saiu daqui ganha a seta', () {
      final a = resumo(ultimaMensagem: 'Segue a proposta', remetente: 'bot');
      expect(previaDaUltimaMensagem(a), '↳ Segue a proposta');
    });

    test('mídia sem legenda diz o que foi mandado', () {
      final a = resumo(tipo: 'imageMessage', remetente: 'contato');
      expect(previaDaUltimaMensagem(a), '📷 Imagem');
      expect(previaDaUltimaMensagem(resumo(tipo: 'audioMessage')), '🎤 Áudio');
    });

    test('sem mensagem nenhuma, fica o assunto', () {
      expect(previaDaUltimaMensagem(resumo()), 'Orçamento');
    });
  });

  test('o tempo da última mensagem fala a língua de quem lê', () {
    final agora = DateTime(2026, 9, 26, 15, 0);
    expect(tempoRelativo(agora, agora: agora), 'agora');
    expect(
      tempoRelativo(agora.subtract(const Duration(minutes: 12)), agora: agora),
      '12 min',
    );
    expect(tempoRelativo(DateTime(2026, 9, 26, 9, 5), agora: agora), '09:05');
    expect(tempoRelativo(DateTime(2026, 9, 25, 9, 5), agora: agora), 'ontem');
    expect(tempoRelativo(DateTime(2026, 9, 1, 9, 5), agora: agora), '01/09');
  });

  testWidgets('o cartão mostra contato, prévia, atendente e não lidas', (
    tester,
  ) async {
    await montar(
      tester,
      AtendimentoCardContent(
        atendimento: resumo(
          ultimaMensagem: 'Quero 500 unidades',
          remetente: 'contato',
          atendente: 'Paulo',
          naoLidas: 3,
          prioridade: 'urgente',
        ),
      ),
    );

    expect(find.text('Ana Lima'), findsOneWidget);
    expect(find.text('5581999990000'), findsOneWidget);
    expect(find.text('Quero 500 unidades'), findsOneWidget);
    expect(find.text('urgente'), findsOneWidget);
    expect(find.text('Paulo'), findsOneWidget);
    expect(find.byKey(const ValueKey('nao-lidas')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('sem atendente, o cartão diz isso', (tester) async {
    await montar(tester, AtendimentoCardContent(atendimento: resumo()));
    expect(find.text('Sem atendente'), findsOneWidget);
    expect(find.byKey(const ValueKey('nao-lidas')), findsNothing);
  });

  testWidgets('a mini-barra traz a prévia da última mensagem', (tester) async {
    await montar(
      tester,
      OverflowBox(
        maxWidth: 400,
        child: MiniBarraDaConversa(
          atendimentoId: 3,
          atendimento: resumo(ultimaMensagem: 'Pode mandar o PIX?'),
          aoAbrir: () {},
          aoVerDetalhes: () {},
          aoFechar: () {},
        ),
      ),
    );
    expect(find.text('Pode mandar o PIX?'), findsOneWidget);
    expect(find.text('Abrir conversa'), findsOneWidget);
  });
}
