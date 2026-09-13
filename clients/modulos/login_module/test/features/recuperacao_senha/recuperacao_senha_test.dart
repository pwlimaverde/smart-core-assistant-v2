import 'package:api_client/testing.dart';
import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/recuperacao_senha/data/datasources/recuperacao_datasources.dart';
import 'package:login_module/src/features/recuperacao_senha/data/repositories/recuperacao_repositories.dart';
import 'package:login_module/src/features/recuperacao_senha/domain/errors/recuperacao_errors.dart';
import 'package:login_module/src/features/recuperacao_senha/domain/parameters/recuperacao_parameters.dart';
import 'package:login_module/src/features/recuperacao_senha/domain/usecases/recuperacao_usecases.dart';
import 'package:login_module/src/features/recuperacao_senha/presentation/pages/recuperar_senha_page.dart';
import 'package:login_module/src/features/recuperacao_senha/presentation/pages/redefinir_senha_page.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthClient extends Mock implements AuthServiceClient {}

/// N11 E8 — recuperação de senha, da tela ao stub gRPC.
void main() {
  late _MockAuthClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(SolicitarRedefinicaoSenhaRequest());
    registerFallbackValue(RedefinirSenhaRequest());
  });

  setUp(() {
    client = _MockAuthClient();
    getIt
      ..registerSingleton<SolicitarRedefinicaoUsecase>(
        SolicitarRedefinicaoUsecase(
          repository: SolicitarRedefinicaoRepository(
            datasource: SolicitarRedefinicaoDatasource(client: client),
          ),
        ),
      )
      ..registerSingleton<RedefinirSenhaUsecase>(
        RedefinirSenhaUsecase(
          repository: RedefinirSenhaRepository(
            datasource: RedefinirSenhaDatasource(client: client),
          ),
        ),
      );
  });
  tearDown(() => getIt.reset());

  Future<void> montar(WidgetTester tester, String inicial) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: inicial,
      routes: [
        GoRoute(
          path: '/recuperar-senha',
          builder: (_, _) => const RecuperarSenhaPage(),
        ),
        GoRoute(
          path: '/redefinir-senha',
          builder: (_, _) => const RedefinirSenhaPage(),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('tela de login')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  group('pedir o link', () {
    testWidgets('sem login não chega ao servidor', (tester) async {
      await montar(tester, '/recuperar-senha');

      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();

      // Texto exato: a explicação da tela começa com a mesma frase.
      expect(
        find.text('Informe o e-mail ou o usuário da sua conta.'),
        findsOneWidget,
      );
      verifyNever(() => client.solicitarRedefinicaoSenha(any()));
    });

    testWidgets('depois de enviar, diz o mesmo exista a conta ou não', (
      tester,
    ) async {
      // "E-mail não encontrado" entregaria a lista de quem tem conta aqui.
      when(() => client.solicitarRedefinicaoSenha(any())).thenAnswer(
        (_) => respostaGrpc(SolicitarRedefinicaoSenhaResponse(aceito: true)),
      );
      await montar(tester, '/recuperar-senha');

      await tester.enterText(find.byType(TextField), '  maria@x.com  ');
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();

      final enviado =
          verify(
                () => client.solicitarRedefinicaoSenha(captureAny()),
              ).captured.single
              as SolicitarRedefinicaoSenhaRequest;
      expect(enviado.login, 'maria@x.com');
      expect(find.textContaining('Se houver uma conta'), findsOneWidget);
      expect(find.text('Enviar link'), findsNothing);
    });

    testWidgets('limite por IP vira uma frase que diz o que fazer', (
      tester,
    ) async {
      when(
        () => client.solicitarRedefinicaoSenha(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('limite')));
      await montar(tester, '/recuperar-senha');

      await tester.enterText(find.byType(TextField), 'maria');
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aguarde alguns minutos'), findsOneWidget);
    });

    testWidgets('voltar leva ao login', (tester) async {
      await montar(tester, '/recuperar-senha');

      await tester.tap(find.text('Voltar ao login'));
      await tester.pumpAndSettle();

      expect(find.text('tela de login'), findsOneWidget);
    });
  });

  group('trocar a senha', () {
    Future<void> preencher(WidgetTester tester, String a, String b) async {
      await tester.enterText(find.byType(TextField).at(0), a);
      await tester.enterText(find.byType(TextField).at(1), b);
      await tester.tap(find.text('Trocar senha'));
      await tester.pumpAndSettle();
    }

    testWidgets('link sem token oferece pedir outro', (tester) async {
      await montar(tester, '/redefinir-senha');

      expect(find.text('Link incompleto'), findsOneWidget);
      expect(find.text('Pedir um link novo'), findsOneWidget);
    });

    testWidgets('senhas diferentes nem saem da tela', (tester) async {
      await montar(tester, '/redefinir-senha?token=abc');

      await preencher(tester, 'senha-nova-1', 'senha-nova-2');

      expect(find.textContaining('não são iguais'), findsOneWidget);
      verifyNever(() => client.redefinirSenha(any()));
    });

    testWidgets('senha curta nem sai da tela', (tester) async {
      await montar(tester, '/redefinir-senha?token=abc');

      await preencher(tester, '123', '123');

      // Texto exato: a dica do campo também fala em 8 caracteres.
      expect(
        find.text('A senha precisa ter ao menos 8 caracteres.'),
        findsOneWidget,
      );
      verifyNever(() => client.redefinirSenha(any()));
    });

    testWidgets('troca com o token do link e manda para o login', (
      tester,
    ) async {
      when(
        () => client.redefinirSenha(any()),
      ).thenAnswer((_) => respostaGrpc(RedefinirSenhaResponse(sucesso: true)));
      await montar(tester, '/redefinir-senha?token=abc123');

      await preencher(tester, 'senha-nova-boa', 'senha-nova-boa');

      final enviado =
          verify(() => client.redefinirSenha(captureAny())).captured.single
              as RedefinirSenhaRequest;
      expect(enviado.token, 'abc123');
      expect(enviado.novaSenha, 'senha-nova-boa');
      expect(find.text('Senha trocada'), findsOneWidget);

      await tester.tap(find.text('Ir para o login'));
      await tester.pumpAndSettle();
      expect(find.text('tela de login'), findsOneWidget);
    });

    testWidgets('link vencido diz para pedir outro', (tester) async {
      when(
        () => client.redefinirSenha(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('vencido')));
      await montar(tester, '/redefinir-senha?token=abc');

      await preencher(tester, 'senha-nova-boa', 'senha-nova-boa');

      expect(find.textContaining('não vale mais'), findsOneWidget);
    });
  });

  group('tradução das falhas', () {
    test(
      'senha recusada pelo servidor não se confunde com link vencido',
      () async {
        when(
          () => client.redefinirSenha(any()),
        ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('fraca')));

        final r = await getIt<RedefinirSenhaUsecase>()(
          const RedefinirSenhaParameters(token: 't', novaSenha: 'x'),
        );

        expect(r, isA<Failure<Unit, RedefinirSenhaError>>());
        expect((r as Failure).error, isA<SenhaRecusada>());
      },
    );

    test('servidor fora do ar no pedido do link', () async {
      when(
        () => client.solicitarRedefinicaoSenha(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('fora')));

      final r = await getIt<SolicitarRedefinicaoUsecase>()(
        const SolicitarRedefinicaoParameters(login: 'maria'),
      );

      expect((r as Failure).error, isA<SolicitarRedefinicaoIndisponivel>());
    });
  });
}
