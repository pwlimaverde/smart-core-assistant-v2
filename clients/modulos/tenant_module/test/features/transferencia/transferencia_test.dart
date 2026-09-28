import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/transferencia/data/datasources/transferencia_datasources.dart';
import 'package:tenant_module/src/features/transferencia/data/repositories/transferencia_repositories.dart';
import 'package:tenant_module/src/features/transferencia/domain/errors/transferencia_errors.dart';
import 'package:tenant_module/src/features/transferencia/domain/model/transferencia.dart';
import 'package:tenant_module/src/features/transferencia/domain/usecases/transferencia_usecases.dart';
import 'package:tenant_module/src/features/transferencia/presentation/controllers/transferencia_controller.dart';
import 'package:tenant_module/src/features/transferencia/presentation/pages/transferencia_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// Plano ia-engine-jev — "Transferência para atendente".
void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.GetMyConfigTransferenciaRequest());
    registerFallbackValue(proto.ListMyRegrasTransferenciaRequest());
    registerFallbackValue(proto.ListMyTransferenciasRequest());
    registerFallbackValue(proto.ListMyFluxosRequest());
    registerFallbackValue(proto.ListMyIntentsRequest());
    registerFallbackValue(proto.ListMyCamposRequest());
    registerFallbackValue(proto.SalvarMyRegraTransferenciaRequest());
    registerFallbackValue(proto.SetMyRegraTransferenciaAtivaRequest());
    registerFallbackValue(proto.SetMySinaisTransferenciaRequest());
    registerFallbackValue(proto.TestarMyRegraTransferenciaRequest());
    registerFallbackValue(proto.GerarMySugestoesTransferenciaRequest());
  });

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  final regra = proto.RegraTransferencia(
    id: Int64(5),
    nome: 'Fechar pedido',
    gatilhoTipo: 'condicao',
    condicao: 'o cliente quer fechar o pedido',
    exemplosSim: ['pode fechar'],
    momento: 'imediato',
    destinoTipo: 'fluxo',
    destinoFluxoId: 10,
    sensibilidade: 'media',
    ativa: true,
  );

  void servidorResponde({bool fluxosNegados = false}) {
    when(() => client.getMyConfigTransferencia(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ConfigTransferenciaResponse(
          config: proto.ConfigTransferencia(
            sinais: [
              proto.SinalTransferencia(
                nome: 'pede_humano',
                ativo: true,
                sensibilidade: 'media',
              ),
              proto.SinalTransferencia(nome: 'base_sem_resposta'),
            ],
            motorAnalise: 'sombra',
            msgTransferencia: 'Um momento, já te passo para alguém.',
          ),
        ),
      ),
    );
    when(() => client.listMyRegrasTransferencia(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyRegrasTransferenciaResponse(regras: [regra]),
      ),
    );
    when(() => client.listMyTransferencias(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyTransferenciasResponse(
          transferencias: [
            proto.TransferenciaIa(
              id: Int64(1),
              atendimentoId: 42,
              motor: 'jev',
              motivo: 'regra:Fechar pedido',
              fluxoNome: 'Comercial',
              criadoEm: Int64(DateTime(2026, 9, 28, 10).millisecondsSinceEpoch),
            ),
          ],
        ),
      ),
    );
    if (fluxosNegados) {
      when(
        () => client.listMyFluxos(any()),
      ).thenThrow(proto.GrpcError.permissionDenied('sem escopo'));
    } else {
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyFluxosResponse(
            fluxos: [proto.MyFluxo(id: 10, nome: 'Comercial', ativo: true)],
          ),
        ),
      );
    }
    when(() => client.listMyIntents(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyIntentsResponse(intents: [proto.MyIntent(tag: 'cartoes')]),
      ),
    );
    when(
      () => client.listMyCampos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyCamposResponse()));
  }

  TransferenciaController controller() => TransferenciaController(
    carregar: CarregarTransferenciaUsecase(
      repository: CarregarTransferenciaRepository(
        datasource: CarregarTransferenciaDatasource(client: client),
      ),
    ),
    salvar: SalvarRegraUsecase(
      repository: SalvarRegraRepository(
        datasource: SalvarRegraDatasource(client: client),
      ),
    ),
    ativa: DefinirRegraAtivaUsecase(
      repository: DefinirRegraAtivaRepository(
        datasource: DefinirRegraAtivaDatasource(client: client),
      ),
    ),
    sinais: DefinirSinaisUsecase(
      repository: DefinirSinaisRepository(
        datasource: DefinirSinaisDatasource(client: client),
      ),
    ),
    testar: TestarRegraUsecase(
      repository: TestarRegraRepository(
        datasource: TestarRegraDatasource(client: client),
      ),
    ),
    sugestoes: GerarSugestoesUsecase(
      repository: GerarSugestoesRepository(
        datasource: GerarSugestoesDatasource(client: client),
      ),
    ),
  );

  group('modelo', () {
    test('motivo legível', () {
      TransferenciaFeita t(String motivo) => TransferenciaFeita(
        id: 1,
        atendimentoId: 1,
        motor: 'jev',
        motivo: motivo,
        fluxoNome: '',
        criadoEm: DateTime(2026),
      );
      expect(t('regra:Fechar pedido').motivoLegivel, 'Regra: Fechar pedido');
      expect(t('pede_humano').motivoLegivel, 'Pediu uma pessoa');
      expect(
        t('duvida:pede_humano').motivoLegivel,
        'Pediu uma pessoa (na dúvida)',
      );
      expect(t('').motivoLegivel, 'Motivo não registrado');
    });

    test('rótulos e sensibilidade dos sinais', () {
      const s = SinalAutomatico(nome: 'irritacao', ativo: true);
      expect(s.rotulo, 'O cliente está irritado');
      expect(s.temSensibilidade, isTrue);
      expect(
        const SinalAutomatico(
          nome: 'base_sem_resposta',
          ativo: false,
        ).temSensibilidade,
        isFalse,
      );
      expect(s.copyWith(sensibilidade: 'alta').sensibilidade, 'alta');
    });

    test('regra ida e volta pelo proto', () {
      final dominio = regraDoProto(regra);
      expect(dominio.destinoFluxoId, 10);
      final volta = regraParaProto(dominio.copyWith(limparDestinoFluxo: true));
      expect(volta.destinoFluxoId, 0);
      expect(volta.exemplosSim, ['pode fechar']);
    });
  });

  group('controller', () {
    test('carrega tudo; listas auxiliares negadas não impedem', () async {
      servidorResponde(fluxosNegados: true);
      final c = controller();
      await c.carregar();
      final painel = (c.state as SuccessState<PainelTransferencia>).data;
      expect(painel.regras.single.nome, 'Fechar pedido');
      expect(painel.config.motorAnalise, 'sombra');
      expect(painel.fluxos, isEmpty);
      expect(painel.intencoes, ['cartoes']);
      expect(painel.transferencias.single.atendimentoId, 42);
      await c.close();
    });

    test('desativar manda o nome como confirmação', () async {
      servidorResponde();
      when(() => client.setMyRegraTransferenciaAtiva(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.SetMyRegraTransferenciaAtivaResponse(regra: regra),
        ),
      );
      final c = controller();
      final erro = await c.definirAtiva(regraDoProto(regra), ativa: false);
      expect(erro, isNull);
      final enviado =
          verify(
                () => client.setMyRegraTransferenciaAtiva(captureAny()),
              ).captured.single
              as proto.SetMyRegraTransferenciaAtivaRequest;
      expect(enviado.ativa, isFalse);
      expect(enviado.confirmar, 'Fechar pedido');
      await c.close();
    });

    test('recusa do servidor chega com a mensagem', () async {
      when(() => client.salvarMyRegraTransferencia(any())).thenThrow(
        proto.GrpcError.invalidArgument('descreva a condição numa frase exata'),
      );
      final c = controller();
      final erro = await c.salvar(
        const RegraDeTransferencia(nome: 'x', condicao: 'curta'),
      );
      expect(erro, isA<TransferenciaRecusada>());
      expect(erro!.message, contains('frase exata'));
      await c.close();
    });

    test('sinal e fluxo padrão vão separados', () async {
      servidorResponde();
      when(() => client.setMySinaisTransferencia(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ConfigTransferenciaResponse(
            config: proto.ConfigTransferencia(),
          ),
        ),
      );
      final c = controller();
      await c.alterarSinal(
        const SinalAutomatico(
          nome: 'irritacao',
          ativo: true,
          sensibilidade: 'alta',
        ),
      );
      await c.definirFluxoPadrao(null);
      final pedidos = verify(
        () => client.setMySinaisTransferencia(captureAny()),
      ).captured.cast<proto.SetMySinaisTransferenciaRequest>();
      expect(pedidos.first.sinais.single.sensibilidade, 'alta');
      expect(pedidos.first.alterarFluxoPadrao, isFalse);
      expect(pedidos.last.alterarFluxoPadrao, isTrue);
      expect(pedidos.last.fluxoPadraoId, 0);
      await c.close();
    });

    test('testar devolve a probabilidade e sugestões contam', () async {
      servidorResponde();
      when(() => client.testarMyRegraTransferencia(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.TestarMyRegraTransferenciaResponse(
            probabilidade: 0.9,
            limiar: 0.8,
            dispararia: true,
            modelo: 'jev-1.13.0',
          ),
        ),
      );
      when(() => client.gerarMySugestoesTransferencia(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GerarMySugestoesTransferenciaResponse(criadas: 2),
        ),
      );
      final c = controller();
      final res = await c.testar(
        frase: 'pode fechar',
        regra: regraDoProto(regra),
      );
      expect(
        (res as Success<ResultadoTesteRegra, TransferenciaError>)
            .value
            .dispararia,
        isTrue,
      );
      final s = await c.gerarSugestoes();
      expect((s as Success<int, TransferenciaError>).value, 2);
      await c.close();
    });
  });

  group('TransferenciaPage', () {
    Future<void> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      getIt.registerSingleton<TransferenciaController>(controller());
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TransferenciaPage()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra sinais, regras, padrões e transferências', (
      tester,
    ) async {
      servidorResponde();
      await montar(tester);
      expect(find.text('O cliente pede uma pessoa'), findsOneWidget);
      expect(find.text('Fechar pedido'), findsOneWidget);
      expect(find.text('Regra: Fechar pedido'), findsOneWidget);
      expect(find.textContaining('em avaliação'), findsOneWidget);
      expect(find.text('Um momento, já te passo para alguém.'), findsOneWidget);
    });

    testWidgets('nova regra valida antes de enviar', (tester) async {
      servidorResponde();
      await montar(tester);
      await tester.tap(find.byKey(const ValueKey('nova-regra')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('salvar-regra')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('erro-regra')), findsOneWidget);
      verifyNever(() => client.salvarMyRegraTransferencia(any()));
    });
  });
}
