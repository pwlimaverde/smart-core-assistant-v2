import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ficha.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/ficha_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/dialogo_valor_campo.dart';

import '../../support/fake_gateway.dart';

/// N9 E13 — preencher (ou apagar) um campo do cartão na ficha.
void main() {
  late FakeAtendimentoGateway gateway;

  ValorCampo campo({
    String tipo = 'texto',
    String valorJson = '',
    String origem = 'MANUAL',
    double confianca = 0,
    List<({String id, String rotulo})> opcoes = const [],
    String descricao = '',
  }) => ValorCampo(
    campoId: 4,
    slug: 'numero_pedido',
    nome: 'Número do pedido',
    descricao: descricao,
    tipo: tipo,
    opcoes: opcoes,
    obrigatorio: false,
    valorJson: valorJson,
    origem: origem,
    confianca: confianca,
    editadoPorHumano: false,
  );

  Future<FichaController> montar(WidgetTester tester, ValorCampo alvo) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final us = usecasesSobre(gateway);
    final controller = FichaController(
      carregar: us.ficha,
      criarEtiqueta: us.criarEtiqueta,
      alternar: us.alternarEtiqueta,
      criarNota: us.criarNota,
      definirBot: us.definirBot,
      definirValorCampo: us.definirValorCampo,
    );
    addTearDown(controller.close);
    await controller.abrir(7);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => abrirEdicaoDeValor(context, alvo, controller),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return controller;
  }

  setUp(() => gateway = FakeAtendimentoGateway());

  testWidgets('texto salva com aspas de JSON', (tester) async {
    await montar(tester, campo());

    await tester.enterText(find.byType(TextField), '  A-1234  ');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(gateway.valorCampoRecebido?.campoId, 4);
    expect(gateway.valorCampoRecebido?.valorJson, '"A-1234"');
  });

  testWidgets('campo de lista vira seletor, e só aceita o catálogo', (
    tester,
  ) async {
    // Um `TextField` aqui jogaria no operador o trabalho de acertar o id — e é
    // justamente o id que o servidor confere.
    await montar(
      tester,
      campo(
        tipo: 'lista',
        opcoes: const [
          (id: 'cartao', rotulo: 'Cartão'),
          (id: 'pix', rotulo: 'Pix'),
        ],
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pix').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(gateway.valorCampoRecebido?.valorJson, '"pix"');
  });

  testWidgets('booleano vira interruptor', (tester) async {
    await montar(tester, campo(tipo: 'booleano'));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(gateway.valorCampoRecebido?.valorJson, 'true');
  });

  testWidgets('número recusa o que não é número, e aceita vírgula', (
    tester,
  ) async {
    await montar(tester, campo(tipo: 'numero'));

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('valor válido'), findsOneWidget);
    expect(gateway.valorCampoRecebido, isNull);

    // Vírgula é como se digita decimal em português.
    await tester.enterText(find.byType(TextField), '12,5');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(gateway.valorCampoRecebido?.valorJson, '12.5');
  });

  testWidgets('data sem escolha não salva', (tester) async {
    await montar(tester, campo(tipo: 'data'));

    expect(find.text('Nenhuma data escolhida'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('valor válido'), findsOneWidget);
    expect(gateway.valorCampoRecebido, isNull);
  });

  testWidgets('data já preenchida aparece no formato de quem lê', (
    tester,
  ) async {
    // Guardado em AAAA-MM-DD, que é o único sem ambiguidade entre dia e mês;
    // mostrado em DD/MM/AAAA, que é como se lê aqui.
    await montar(tester, campo(tipo: 'data', valorJson: '"2026-09-15"'));

    expect(find.text('15/09/2026'), findsOneWidget);
  });

  testWidgets('apagar manda null explícito, não campo em branco', (
    tester,
  ) async {
    // `null` é uma decisão, e o servidor a respeita: a IA não repreenche o que
    // alguém tirou.
    await montar(tester, campo(valorJson: '"A-1234"'));

    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();

    expect(gateway.valorCampoRecebido?.valorJson, 'null');
  });

  testWidgets('campo nunca preenchido não oferece apagar', (tester) async {
    await montar(tester, campo());

    expect(find.text('Apagar'), findsNothing);
  });

  testWidgets('valor da IA avisa que passa a valer o que a pessoa escrever', (
    tester,
  ) async {
    await montar(
      tester,
      campo(valorJson: '"A-1234"', origem: 'IA', confianca: 0.92),
    );

    expect(find.textContaining('92% de confiança'), findsOneWidget);
  });

  testWidgets('a descrição do campo aparece para quem preenche', (
    tester,
  ) async {
    await montar(tester, campo(descricao: 'o código que vem no e-mail'));

    expect(find.text('o código que vem no e-mail'), findsOneWidget);
  });

  testWidgets('erro do servidor fica dentro da janela', (tester) async {
    // Fechar e piscar um aviso atrás faria perder o que foi digitado.
    gateway.erroValorCampo = GrpcError.invalidArgument('formato recusado');
    await montar(tester, campo());

    await tester.enterText(find.byType(TextField), 'A-1');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Número do pedido'), findsOneWidget);
  });

  testWidgets('cancelar não escreve nada', (tester) async {
    await montar(tester, campo());

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(gateway.valorCampoRecebido, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
