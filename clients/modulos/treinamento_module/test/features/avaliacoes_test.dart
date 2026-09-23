import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treinamento_module/src/features/ensaio/data/datasources/ensaio_datasources.dart';
import 'package:treinamento_module/src/features/ensaio/data/repositories/ensaio_repositories.dart';
import 'package:treinamento_module/src/features/ensaio/domain/model/ensaio.dart';
import 'package:treinamento_module/src/features/ensaio/domain/usecases/ensaio_usecases.dart';
import 'package:treinamento_module/src/features/ensaio/presentation/widgets/aba_avaliacoes.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// P17 — a correção feita no teste vira material de treinamento.
void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyAvaliacoesDeTesteRequest());
    registerFallbackValue(proto.MarcarAvaliacaoTratadaRequest());
  });
  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  void registrar(List<proto.AvaliacaoDeTeste> itens) {
    when(() => client.listMyAvaliacoesDeTeste(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyAvaliacoesDeTesteResponse(itens: itens)),
    );
    when(() => client.marcarAvaliacaoTratada(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    getIt
      ..registerSingleton<ListarAvaliacoesUsecase>(
        ListarAvaliacoesUsecase(
          repository: ListarAvaliacoesRepository(
            datasource: ListarAvaliacoesDatasource(client: client),
          ),
        ),
      )
      ..registerSingleton<TratarAvaliacaoUsecase>(
        TratarAvaliacaoUsecase(
          repository: TratarAvaliacaoRepository(
            datasource: TratarAvaliacaoDatasource(client: client),
          ),
        ),
      );
  }

  proto.AvaliacaoDeTeste item({
    int id = 1,
    String avaliacao = 'ruim',
    String correcao = 'Abrimos às 8h.',
  }) => proto.AvaliacaoDeTeste(
    id: id,
    pergunta: 'Que horas abre?',
    respostaBot: 'Não sei.',
    respostaCorrigida: correcao,
    avaliacao: avaliacao,
    criadaEm: Int64(DateTime(2026, 9, 1).millisecondsSinceEpoch),
  );

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AbaAvaliacoes())),
    );
    await tester.pumpAndSettle();
  }

  group('regra', () {
    AvaliacaoPendente a({bool boa = false, String correcao = 'x'}) =>
        AvaliacaoPendente(
          id: 1,
          pergunta: 'p',
          respostaBot: 'r',
          respostaCorrigida: correcao,
          boa: boa,
          criadaEm: DateTime(2026),
        );

    test('só a ruim com correção vira treinamento', () {
      expect(a().podeVirarTreinamento, isTrue);
      expect(a(boa: true).podeVirarTreinamento, isFalse);
      expect(a(correcao: '  ').podeVirarTreinamento, isFalse);
    });

    test('o material leva a pergunta e a resposta certa', () {
      expect(a(correcao: 'Abrimos às 8h').conteudoParaTreinamento,
          contains('Abrimos às 8h'));
    });
  });

  testWidgets('lista vazia explica de onde vêm as avaliações', (tester) async {
    registrar([]);
    await montar(tester);

    expect(find.text('Nada para revisar'), findsOneWidget);
  });

  testWidgets('a correção aparece e oferece virar treinamento', (
    tester,
  ) async {
    registrar([item()]);
    await montar(tester);

    expect(find.text('Que horas abre?'), findsOneWidget);
    expect(find.text('Correção: Abrimos às 8h.'), findsOneWidget);
    expect(find.text('Virar treinamento'), findsOneWidget);
  });

  testWidgets('a boa não oferece virar treinamento, só dispensar', (
    tester,
  ) async {
    registrar([item(avaliacao: 'boa', correcao: '')]);
    await montar(tester);

    expect(find.text('Virar treinamento'), findsNothing);
    await tester.tap(find.byTooltip('Dispensar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(() => client.marcarAvaliacaoTratada(captureAny())).captured.single
            as proto.MarcarAvaliacaoTratadaRequest;
    expect(enviado.id, 1);
    expect(enviado.virouTreinamento, isFalse);
  });
}
