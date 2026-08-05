import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ficha.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/ficha_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/ficha_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/painel_ficha.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

Etiqueta _etiqueta({
  required int id,
  required String nome,
  String cor = '#3b82f6',
  bool ativo = true,
}) =>
    Etiqueta(
      id: id,
      nome: nome,
      cor: cor,
      descricao: '',
      ativo: ativo,
    );

void main() {
  FichaController controllerSobre(FakeAtendimentoGateway gateway) =>
      FichaController(
        carregar: GetFichaUsecase(
          repository: GetFichaRepository(
            datasource: GetFichaDatasource(gateway: gateway),
          ),
        ),
        criarEtiqueta: CriarEtiquetaUsecase(
          repository: CriarEtiquetaRepository(
            datasource: CriarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        alternar: AlternarEtiquetaUsecase(
          repository: AlternarEtiquetaRepository(
            datasource: AlternarEtiquetaDatasource(gateway: gateway),
          ),
        ),
        criarNota: CriarNotaUsecase(
          repository: CriarNotaRepository(
            datasource: CriarNotaDatasource(gateway: gateway),
          ),
        ),
      );

  Future<FichaController> montar(
    WidgetTester tester,
    FakeAtendimentoGateway gateway,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final controller = controllerSobre(gateway);
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PainelFicha(controller: controller))),
    );
    await controller.abrir(7);
    await tester.pumpAndSettle();
    return controller;
  }

  group('etiquetas disponíveis', () {
    test('não oferece o que já está colado na conversa', () {
      // Oferecer uma etiqueta já aplicada seria um clique sem efeito.
      final ficha = FichaAtendimento(
        catalogo: [
          _etiqueta(id: 1, nome: 'urgente'),
          _etiqueta(id: 2, nome: 'vip'),
        ],
        aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
        notas: const [],
      );

      expect(ficha.disponiveis.map((e) => e.id), [2]);
    });

    test('não oferece etiqueta desativada do catálogo', () {
      final ficha = FichaAtendimento(
        catalogo: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        aplicadas: const [],
        notas: const [],
      );

      expect(ficha.disponiveis, isEmpty);
    });

    test('etiqueta desativada JÁ aplicada continua na conversa', () {
      // Sumir com ela reescreveria o passado desta conversa.
      final ficha = FichaAtendimento(
        catalogo: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        aplicadas: [_etiqueta(id: 3, nome: 'antiga', ativo: false)],
        notas: const [],
      );

      expect(ficha.aplicadas.single.nome, 'antiga');
      expect(ficha.disponiveis, isEmpty);
    });
  });

  group('corDaEtiqueta', () {
    test('converte o hex do catálogo', () {
      expect(corDaEtiqueta('#3b82f6'), const Color(0xFF3B82F6));
      expect(corDaEtiqueta('3b82f6'), const Color(0xFF3B82F6));
    });

    test('hex inválido não derruba o painel', () {
      expect(corDaEtiqueta(''), const Color(0xFFA98F71));
      expect(corDaEtiqueta('#zzz'), const Color(0xFFA98F71));
    });
  });

  group('PainelFicha', () {
    testWidgets('mostra as etiquetas da conversa e as disponíveis', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [
            _etiqueta(id: 1, nome: 'urgente'),
            _etiqueta(id: 2, nome: 'vip'),
          ],
          aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
          notas: const [],
        );

      await montar(tester, gateway);

      expect(find.text('urgente'), findsOneWidget);
      expect(find.text('vip'), findsOneWidget);
      expect(find.text('Colar nesta conversa'), findsOneWidget);
    });

    testWidgets('conversa sem etiqueta diz isso, sem parecer erro', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);

      expect(find.text('Nenhuma etiqueta nesta conversa.'), findsOneWidget);
      expect(find.text('Nada anotado ainda.'), findsOneWidget);
    });

    testWidgets('colar uma etiqueta manda aplicar', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [_etiqueta(id: 2, nome: 'vip')],
          aplicadas: const [],
          notas: const [],
        );

      await montar(tester, gateway);
      await tester.tap(find.text('vip'));
      await tester.pumpAndSettle();

      expect(gateway.etiquetaAlternada, (2, true));
    });

    testWidgets('tirar a etiqueta manda o oposto', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: [_etiqueta(id: 1, nome: 'urgente')],
          aplicadas: [_etiqueta(id: 1, nome: 'urgente')],
          notas: const [],
        );

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Tirar desta conversa'));
      await tester.pumpAndSettle();

      expect(gateway.etiquetaAlternada, (1, false));
    });

    testWidgets('as notas aparecem da mais recente para a mais antiga', (
      tester,
    ) async {
      // Quem abre a ficha quer o que aconteceu por último, não o começo.
      final gateway = FakeAtendimentoGateway()
        ..ficha = FichaAtendimento(
          catalogo: const [],
          aplicadas: const [],
          notas: [
            Nota(
              id: 1,
              texto: 'primeira',
              criadoEm: DateTime.now().subtract(const Duration(days: 2)),
            ),
            Nota(id: 2, texto: 'ultima', criadoEm: DateTime.now()),
          ],
        );

      final controller = await montar(tester, gateway);

      final ficha =
          (controller.state as SuccessState<FichaAtendimento>).data;
      expect(ficha.notas.first.texto, 'ultima');
      expect(find.text('agora'), findsOneWidget);
    });

    testWidgets('a nota avisa que é interna, dentro da janela', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();

      expect(find.text('Só a equipe vê. O contato, nunca.'), findsOneWidget);
    });

    testWidgets('nota vazia é barrada sem chamar o servidor', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Escreva a anotação.'), findsOneWidget);
      expect(gateway.notaRecebida, isNull);
    });

    testWidgets('anotar manda o texto e recarrega a ficha', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      final antes = gateway.chamadasFicha;

      await tester.tap(find.byTooltip('Anotar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'O que registrar'),
        'cliente pediu para ligar depois das 18h',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(gateway.notaRecebida, 'cliente pediu para ligar depois das 18h');
      expect(gateway.chamadasFicha, greaterThan(antes));
    });

    testWidgets('etiqueta sem nome é barrada', (tester) async {
      final gateway = FakeAtendimentoGateway();

      await montar(tester, gateway);
      await tester.tap(find.byTooltip('Nova etiqueta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome da etiqueta.'), findsOneWidget);
      expect(gateway.etiquetaCriada, isNull);
    });

    testWidgets('falha da ficha não derruba nada além dela', (tester) async {
      final gateway = FakeAtendimentoGateway()
        ..erroFicha = GrpcError.unavailable('fora do ar');

      await montar(tester, gateway);

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });
  });

  test('nome de etiqueta repetido volta com a mensagem do servidor', () async {
    // A UNIQUE (tenant, nome) diz qual nome colidiu.
    final gateway = FakeAtendimentoGateway()
      ..erroFicha = GrpcError.alreadyExists('já existe a etiqueta "urgente"');

    final res = await CriarEtiquetaUsecase(
      repository: CriarEtiquetaRepository(
        datasource: CriarEtiquetaDatasource(gateway: gateway),
      ),
    )(const CriarEtiquetaParameters(nome: 'urgente', cor: '#fff'));

    final erro = (res as Failure).error;
    expect(erro, isA<FichaRecusado>());
    expect(erro.message, contains('urgente'));
  });

  test('sessão expirada é distinguida de servidor fora do ar', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroFicha = GrpcError.unauthenticated('expirou');

    final res = await GetFichaUsecase(
      repository: GetFichaRepository(
        datasource: GetFichaDatasource(gateway: gateway),
      ),
    )(const AtendimentoIdParameters(atendimentoId: 1));

    expect((res as Failure).error, isA<FichaAcessoNegado>());
  });
}
