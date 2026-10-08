import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/midia_mensagem.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/chat_message_bubble.dart';

MensagemThread _mensagem({
  bool geradoPorIa = false,
  String? resumoMidia,
  String? analiseMidia,
  String remetente = 'bot',
}) => MensagemThread(
  id: 1,
  atendimentoId: 1,
  tipo: 'texto',
  conteudo: 'Olá, como posso ajudar?',
  remetente: remetente,
  timestamp: DateTime(2026, 1, 1, 10, 30),
  // O vocabulário é o do provedor, o mesmo que o banco guarda: 'sent',
  // 'delivered', 'read'. Um valor inventado aqui derivaria para "pendente" e
  // o teste passaria a medir outra coisa.
  statusEnvio: 'sent',
  geradoPorIa: geradoPorIa,
  resumoMidia: resumoMidia,
  analiseMidia: analiseMidia,
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

    testWidgets('sem bloco de análise quando não há resumo nem transcrição', (
      tester,
    ) async {
      await _pump(tester, _mensagem());

      expect(find.text('Análise IA'), findsNothing);
    });

    testWidgets('análise IA começa recolhida e abre com a descrição', (
      tester,
    ) async {
      await _pump(tester, _mensagem(resumoMidia: 'Foto de um boleto vencido.'));

      expect(find.text('Análise IA'), findsOneWidget);
      expect(find.text('Foto de um boleto vencido.'), findsNothing);

      await tester.tap(find.text('Análise IA'));
      await tester.pump();

      expect(find.text('Descrição'), findsOneWidget);
      expect(find.text('Foto de um boleto vencido.'), findsOneWidget);
    });

    testWidgets('a transcrição só aparece com áudio, nunca como texto solto', (
      tester,
    ) async {
      await _pump(
        tester,
        _mensagem(analiseMidia: 'Quero a segunda via do boleto.'),
      );

      await tester.tap(find.text('Análise IA'));
      await tester.pump();

      expect(find.text('Transcrição'), findsNothing);
      expect(find.text('Quero a segunda via do boleto.'), findsNothing);
    });
  });
  // ─── P2: ticks e citação ──────────────────────────────────────────────────
  group('ticks e citação (P2)', () {
    testWidgets('mensagem que saiu mostra tick; a do contato, não', (
      tester,
    ) async {
      await _pump(tester, _mensagem(remetente: 'atendente'));
      expect(find.byIcon(Icons.done), findsOneWidget);

      await _pump(tester, _mensagem(remetente: 'cliente'));
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('lida desenha o tick duplo azul', (tester) async {
      final lida = MensagemThread(
        id: 1,
        atendimentoId: 1,
        tipo: 'texto',
        conteudo: 'Olá',
        remetente: 'atendente',
        timestamp: DateTime(2026, 1, 1, 10, 30),
        statusEnvio: 'sent',
        lidaEm: DateTime(2026, 1, 1, 10, 31),
      );
      await _pump(tester, lida);

      final icone = tester.widget<Icon>(find.byIcon(Icons.done_all));
      expect(icone.color, const Color(0xFF2563EB));
    });

    testWidgets('a citação aparece acima do texto', (tester) async {
      final comCitacao = MensagemThread(
        id: 2,
        atendimentoId: 1,
        tipo: 'texto',
        conteudo: 'Já vou verificar',
        remetente: 'atendente',
        timestamp: DateTime(2026, 1, 1, 10, 30),
        statusEnvio: 'sent',
        citacao: const CitacaoMensagem(
          mensagemId: 1,
          remetente: 'cliente',
          preview: 'Meu pedido atrasou',
        ),
      );
      await _pump(tester, comCitacao);

      expect(find.text('Meu pedido atrasou'), findsOneWidget);
      expect(find.text('Contato'), findsOneWidget);
    });

    testWidgets('clique longo pede para citar quando a tela aceita', (
      tester,
    ) async {
      var citou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              mensagem: _mensagem(),
              aoCitar: () => citou = true,
            ),
          ),
        ),
      );

      await tester.longPress(find.text('Olá, como posso ajudar?'));
      expect(citou, isTrue);
    });
  });

  // ─── P1.1-D: agrupamento das bolhas ───────────────────────────────────────
  group('mesmoBloco / posicaoNoGrupo (P1.1-D)', () {
    final t0 = DateTime(2026, 1, 1, 10, 30);

    MensagemThread m(
      int id,
      DateTime quando, {
      String remetente = 'cliente',
      String statusEnvio = 'sent',
    }) => MensagemThread(
      id: id,
      atendimentoId: 1,
      tipo: 'texto',
      conteudo: 'm$id',
      remetente: remetente,
      timestamp: quando,
      statusEnvio: statusEnvio,
    );

    test('mesmo remetente, mesmo dia, até 2 min = mesmo bloco', () {
      expect(
        mesmoBloco(m(1, t0), m(2, t0.add(const Duration(minutes: 2)))),
        isTrue,
      );
    });

    test('mais de 2 min quebra o bloco', () {
      expect(
        mesmoBloco(
          m(1, t0),
          m(2, t0.add(const Duration(minutes: 2, seconds: 1))),
        ),
        isFalse,
      );
    });

    test('bot e atendente contam como remetentes diferentes', () {
      expect(
        mesmoBloco(
          m(1, t0, remetente: 'bot'),
          m(2, t0, remetente: 'atendente'),
        ),
        isFalse,
      );
    });

    test('virada do dia quebra o bloco mesmo com menos de 2 min', () {
      final antes = DateTime(2026, 1, 1, 23, 59, 30);
      final depois = DateTime(2026, 1, 2, 0, 0, 30);
      expect(mesmoBloco(m(1, antes), m(2, depois)), isFalse);
    });

    test('vizinha ausente nunca é do mesmo bloco', () {
      expect(mesmoBloco(null, m(1, t0)), isFalse);
      expect(mesmoBloco(m(1, t0), null), isFalse);
    });

    test('relógio fora de ordem ainda agrupa (diferença absoluta)', () {
      expect(
        mesmoBloco(m(1, t0), m(2, t0.subtract(const Duration(seconds: 30)))),
        isTrue,
      );
    });

    test('posições de um bloco de três e de uma mensagem sozinha', () {
      final a = m(1, t0);
      final b = m(2, t0.add(const Duration(seconds: 20)));
      final c = m(3, t0.add(const Duration(seconds: 40)));
      final d = m(4, t0.add(const Duration(minutes: 1)), remetente: 'bot');

      expect(posicaoNoGrupo(null, a, b), PosicaoNoGrupo.primeira);
      expect(posicaoNoGrupo(a, b, c), PosicaoNoGrupo.meio);
      expect(posicaoNoGrupo(b, c, d), PosicaoNoGrupo.ultima);
      expect(posicaoNoGrupo(c, d, null), PosicaoNoGrupo.unica);
    });

    test(
      'pendente local (id < 0) agrupa com a anterior do mesmo remetente',
      () {
        final enviada = m(10, t0, remetente: 'atendente');
        final pendente = m(
          -1,
          t0.add(const Duration(seconds: 5)),
          remetente: 'atendente',
          statusEnvio: 'pending',
        );
        expect(
          posicaoNoGrupo(null, enviada, pendente),
          PosicaoNoGrupo.primeira,
        );
        expect(posicaoNoGrupo(enviada, pendente, null), PosicaoNoGrupo.ultima);
      },
    );
  });

  group('secoesDaAnaliseIa', () {
    test('áudio com transcrição e resumo: Transcrição, depois Resumo', () {
      final secoes = secoesDaAnaliseIa(
        tipo: TipoMidia.audio,
        transcricao: '  Quero a segunda via.  ',
        resumo: 'Pedido de boleto',
      );
      expect(secoes.map((s) => s.rotulo), ['Transcrição', 'Resumo']);
      expect(secoes.first.texto, 'Quero a segunda via.');
    });

    test('imagem nunca mostra transcrição, só descrição', () {
      final secoes = secoesDaAnaliseIa(
        tipo: TipoMidia.imagem,
        transcricao: 'texto que não deveria aparecer',
        resumo: 'Foto de um boleto vencido',
      );
      expect(secoes.map((s) => s.rotulo), ['Descrição']);
    });

    test('textos vazios ou só espaços não geram seção', () {
      expect(
        secoesDaAnaliseIa(
          tipo: TipoMidia.audio,
          transcricao: ' ',
          resumo: null,
        ),
        isEmpty,
      );
    });
  });

  group('ChatMessageBubble agrupada (P1.1-D)', () {
    final t0 = DateTime(2026, 1, 1, 10, 30);

    MensagemThread m(
      int id,
      int segundos, {
      String remetente = 'cliente',
      String statusEnvio = 'sent',
      bool geradoPorIa = false,
    }) => MensagemThread(
      id: id,
      atendimentoId: 1,
      tipo: 'texto',
      conteudo: 'mensagem $id',
      remetente: remetente,
      timestamp: t0.add(Duration(seconds: segundos)),
      statusEnvio: statusEnvio,
      geradoPorIa: geradoPorIa,
    );

    /// Desenha a lista como a tela: cada bolha com a posição calculada pelas
    /// vizinhas.
    Future<void> pumpLista(WidgetTester tester, List<MensagemThread> lista) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (var i = 0; i < lista.length; i++)
                    ChatMessageBubble(
                      mensagem: lista[i],
                      posicao: posicaoNoGrupo(
                        i == 0 ? null : lista[i - 1],
                        lista[i],
                        i == lista.length - 1 ? null : lista[i + 1],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

    testWidgets('3 consecutivas do contato: só a última mostra horário', (
      tester,
    ) async {
      await pumpLista(tester, [m(1, 0), m(2, 30), m(3, 50)]);

      expect(find.text('mensagem 1'), findsOneWidget);
      expect(find.text('mensagem 2'), findsOneWidget);
      expect(find.text('mensagem 3'), findsOneWidget);
      // As três são 10:30; num bloco, a hora aparece uma vez só.
      expect(find.text('10:30'), findsOneWidget);
    });

    testWidgets('bot depois do contato abre bloco separado com hora própria', (
      tester,
    ) async {
      await pumpLista(tester, [m(1, 0), m(2, 10), m(3, 20, remetente: 'bot')]);

      expect(find.text('10:30'), findsNWidgets(2));
    });

    testWidgets('selo de IA só na primeira; ticks só na última', (
      tester,
    ) async {
      await pumpLista(tester, [
        m(1, 0, remetente: 'bot', geradoPorIa: true),
        m(2, 10, remetente: 'bot', geradoPorIa: true),
        m(3, 20, remetente: 'bot', geradoPorIa: true),
      ]);

      expect(find.text('Gerado por IA'), findsOneWidget);
      expect(find.byIcon(Icons.done), findsOneWidget);
    });

    testWidgets('falha no meio do bloco ainda mostra o tick de erro', (
      tester,
    ) async {
      await pumpLista(tester, [
        m(1, 0, remetente: 'atendente'),
        m(2, 10, remetente: 'atendente', statusEnvio: 'failed'),
        m(3, 20, remetente: 'atendente'),
      ]);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
    });

    testWidgets('meio do bloco tem canto reduzido do lado do remetente', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              mensagem: m(1, 0, remetente: 'atendente'),
              posicao: PosicaoNoGrupo.meio,
            ),
          ),
        ),
      );

      final caixa = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      final cantos = caixa.borderRadius! as BorderRadius;
      // Atendente fala à direita: o canto de cima à direita encolhe.
      expect(cantos.topRight.x, lessThan(cantos.topLeft.x));
    });
  });
}
