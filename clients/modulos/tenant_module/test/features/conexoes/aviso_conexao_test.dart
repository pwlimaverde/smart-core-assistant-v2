import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/conexoes/data/datasources/conexoes_datasources.dart';
import 'package:tenant_module/src/features/conexoes/data/repositories/conexoes_repositories.dart';
import 'package:tenant_module/src/features/conexoes/domain/usecases/conexoes_usecases.dart';
import 'package:tenant_module/src/shared/widgets/aviso_conexao.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyWhatsappInstancesRequest());
    registerFallbackValue(proto.GetMyWhatsappInstanceStatusRequest());
  });

  setUp(() {
    client = _MockAdminClient();
    getIt.registerSingleton<ListarConexoesUsecase>(
      ListarConexoesUsecase(
        repository: ListarConexoesRepository(
          datasource: ListarConexoesDatasource(client: client),
        ),
      ),
    );
    getIt.registerSingleton<EstadoPareamentoUsecase>(
      EstadoPareamentoUsecase(
        repository: EstadoPareamentoRepository(
          datasource: EstadoPareamentoDatasource(client: client),
        ),
      ),
    );
  });
  tearDown(() => getIt.reset());

  void conexaoForaDoAr() {
    when(() => client.listMyWhatsappInstances(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyWhatsappInstancesResponse(
          instancias: [
            proto.MyWhatsappInstance(
              id: 1,
              name: '5588981061874',
              phoneNumber: '5588981061874',
              connectionState: 'disconnected',
              active: true,
            ),
          ],
        ),
      ),
    );
    when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetMyWhatsappInstanceStatusResponse(
          connectionState: 'disconnected',
        ),
      ),
    );
  }

  /// A faixa tem de ocupar a largura da tela.
  ///
  /// Ela quebrou em produção renderizando **uma letra por linha**: o texto
  /// recebeu uns poucos pixels de largura, ficou mais alto que a janela e
  /// empurrou o quadro inteiro para fora da tela — a página de atendimento
  /// aparecia sem card nenhum. Um aviso de que "nada está chegando" que impede
  /// de ver o que chegou é pior do que aviso nenhum.
  testWidgets('a faixa ocupa a largura da tela', (tester) async {
    conexaoForaDoAr();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            // Mesma composição da KanbanPage: faixa no topo, quadro embaixo.
            body: Column(
              children: [
                AvisoConexao(),
                Expanded(child: Placeholder(key: Key('quadro'))),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light),
    );
    await tester.pumpAndSettle();

    final faixa = tester.getSize(find.byType(AvisoConexao));
    expect(faixa.width, 1400, reason: 'a faixa encolheu na horizontal: $faixa');
    expect(
      faixa.height,
      lessThan(120),
      reason: 'a faixa tomou a tela na vertical: $faixa',
    );

    // E o quadro continua visível — é o que o operador veio ver.
    expect(
      tester.getSize(find.byKey(const Key('quadro'))).height,
      greaterThan(700),
    );
  });

  /// Mesma prova, mas pela composição que o app usa de verdade.
  ///
  /// O app não injeta `AvisoConexao` direto: injeta `AvisosDoQuadro`, que é uma
  /// `Column(mainAxisSize: min)` com as duas faixas. É a diferença entre o que
  /// os testes cobriam e o que rodava.
  testWidgets('a faixa ocupa a largura da tela dentro de uma Column min', (
    tester,
  ) async {
    conexaoForaDoAr();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Column(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [SizedBox.shrink(), AvisoConexao()],
                ),
                Expanded(child: Placeholder(key: Key('quadro'))),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light),
    );
    await tester.pumpAndSettle();

    final faixa = tester.getSize(find.byType(AvisoConexao));
    expect(faixa.width, 1400, reason: 'a faixa encolheu: $faixa');
    expect(faixa.height, lessThan(120), reason: 'a faixa cresceu: $faixa');
  });
}
