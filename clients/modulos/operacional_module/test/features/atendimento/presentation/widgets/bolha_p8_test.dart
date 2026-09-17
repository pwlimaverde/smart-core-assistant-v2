import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/chat_message_bubble.dart';

/// P8 — enquete, lista, botões e reação na bolha.
///
/// Até aqui os quatro caíam em "Other" na normalização e chegavam VAZIOS: a
/// enquete mostrava a pergunta sem nenhuma alternativa, e a reação virava uma
/// bolha "👍" solta no meio da conversa.
void main() {
  MensagemThread mensagem({
    String tipo = 'texto',
    String conteudo = 'oi',
    Map<String, dynamic> metadados = const {},
    List<ReacaoDaMensagem> reacoes = const [],
    String remetente = 'contato',
  }) => MensagemThread(
    id: 1,
    atendimentoId: 9,
    tipo: tipo,
    conteudo: conteudo,
    remetente: remetente,
    timestamp: DateTime(2026, 9, 17, 10, 30),
    statusEnvio: 'sent',
    metadados: metadados,
    reacoes: reacoes,
  );

  Future<void> montar(WidgetTester tester, MensagemThread m) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatMessageBubble(mensagem: m))),
    );
  }

  testWidgets('a enquete mostra a pergunta E as alternativas', (tester) async {
    await montar(
      tester,
      mensagem(
        tipo: 'enquete',
        conteudo: 'Qual horário fica melhor?',
        metadados: const {
          'opcoes': ['Manhã', 'Tarde'],
        },
      ),
    );

    expect(find.text('Qual horário fica melhor?'), findsOneWidget);
    expect(find.text('Manhã'), findsOneWidget);
    expect(find.text('Tarde'), findsOneWidget);
  });

  testWidgets('a lista mostra o título de cada item', (tester) async {
    await montar(
      tester,
      mensagem(
        tipo: 'lista',
        conteudo: 'Escolha o serviço',
        metadados: const {
          'itens': [
            {'titulo': 'Suporte', 'descricao': 'Problemas'},
            {'titulo': 'Vendas', 'descricao': 'Orçamento'},
          ],
        },
      ),
    );

    expect(find.text('Suporte'), findsOneWidget);
    expect(find.text('Vendas'), findsOneWidget);
  });

  testWidgets('os botões aparecem como opções, não como botões', (
    tester,
  ) async {
    // São opções que o contato vê no celular dele; clicar daqui não faria nada,
    // e um botão que não funciona é pior do que uma lista que se explica.
    await montar(
      tester,
      mensagem(
        tipo: 'botoes',
        conteudo: 'Confirma o horário?',
        metadados: const {
          'botoes': ['Sim', 'Não'],
        },
      ),
    );

    expect(find.text('Sim'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sim'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Sim'), findsNothing);
  });

  testWidgets('a reação aparece junto da bolha, e não como mensagem', (
    tester,
  ) async {
    await montar(
      tester,
      mensagem(
        reacoes: const [ReacaoDaMensagem(emoji: '👍', de: 'contato')],
      ),
    );

    expect(find.text('oi'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
  });

  testWidgets('duas pessoas reagindo mostram os dois emojis', (tester) async {
    await montar(
      tester,
      mensagem(
        reacoes: const [
          ReacaoDaMensagem(emoji: '👍', de: 'contato'),
          ReacaoDaMensagem(emoji: '❤️', de: 'atendente'),
        ],
      ),
    );

    expect(find.text('👍❤️'), findsOneWidget);
  });

  testWidgets('mensagem comum não ganha nada além do texto', (tester) async {
    await montar(tester, mensagem());

    expect(find.text('oi'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
  });

  test('os acessores leem só a chave do próprio tipo', () {
    // O mapa é cru porque o formato varia com o tipo; cada bolha lê a chave
    // dela e ignora o resto.
    final m = mensagem(
      tipo: 'enquete',
      metadados: const {
        'opcoes': ['A'],
        'botoes': ['X'],
      },
    );
    expect(m.opcoesDaEnquete, ['A']);
    expect(m.rotulosDosBotoes, ['X']);
    expect(m.itensDaLista, isEmpty);
  });
}
