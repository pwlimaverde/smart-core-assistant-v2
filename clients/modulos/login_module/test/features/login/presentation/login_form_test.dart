// A tela de login serve os DOIS apps, e a diferença entre eles é uma só: o
// caminho para criar conta.
//
// No app do tenant — instalado no computador de quem vai virar cliente — não
// existe URL para digitar. Sem um botão visível aqui, o cadastro é
// inalcançável e o programa recém-instalado vira uma tela de login sem saída.
// No painel do superusuário não há autocadastro, e o mesmo botão seria um beco.
import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/domain/errors/auth_errors.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/services/auth_service.dart';
import 'package:login_module/src/features/login/presentation/controllers/login_controller.dart';
import 'package:login_module/src/features/login/presentation/widgets/login_form.dart';

/// AuthService que nunca é chamado: estes testes são sobre a tela, não o login.
class _AuthOcioso implements AuthService {
  @override
  Future<ReturnSuccessOrError<Session, LoginError>> login({
    required String email,
    required String password,
  }) async => const Failure(CredenciaisInvalidas());
  @override
  Future<ReturnSuccessOrError<Session, RefreshError>> refresh() async =>
      const Failure(SemSessaoPersistida());
  @override
  Future<ReturnSuccessOrError<Unit, LogoutError>> logout() async =>
      const Success(unit);
  @override
  bool get isAuthenticated => false;
  @override
  Session? get currentSession => null;
  @override
  Listenable get authChanges => ValueNotifier<int>(0);
}

void main() {
  late LoginController controller;

  setUp(() => controller = LoginController(auth: _AuthOcioso()));
  tearDown(() => controller.close());

  /// Monta a tela dentro de um GoRouter — `context.go` exige um.
  Future<GoRouter> montar(WidgetTester tester, {String? rotaDeCadastro}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => Scaffold(
            body: LoginForm(
              controller: controller,
              rotaDeCadastro: rotaDeCadastro,
            ),
          ),
        ),
        GoRoute(path: '/cadastro', builder: (_, _) => const Text('wizard')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    return router;
  }

  testWidgets('app do tenant: oferece criar conta', (tester) async {
    await montar(tester, rotaDeCadastro: '/cadastro');

    expect(find.text('Primeira vez por aqui?'), findsOneWidget);
    expect(find.text('Criar conta da minha empresa'), findsOneWidget);
  });

  testWidgets('painel do superusuário: não oferece criar conta', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('Primeira vez por aqui?'), findsNothing);
    expect(find.text('Criar conta da minha empresa'), findsNothing);
    // O login em si continua lá.
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('o botão leva ao wizard de cadastro', (tester) async {
    await montar(tester, rotaDeCadastro: '/cadastro');

    await tester.tap(find.text('Criar conta da minha empresa'));
    await tester.pumpAndSettle();

    expect(find.text('wizard'), findsOneWidget);
  });
}
