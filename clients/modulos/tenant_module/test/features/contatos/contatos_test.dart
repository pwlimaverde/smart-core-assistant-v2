import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:login_module/login_module.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/contatos/data/datasources/contatos_datasources.dart';
import 'package:tenant_module/src/features/contatos/data/repositories/contatos_repositories.dart';
import 'package:tenant_module/src/features/contatos/domain/errors/contatos_errors.dart';
import 'package:tenant_module/src/features/contatos/domain/model/contato.dart';
import 'package:tenant_module/src/features/contatos/domain/parameters/contatos_parameters.dart';
import 'package:tenant_module/src/features/contatos/domain/usecases/contatos_usecases.dart';
import 'package:tenant_module/src/features/contatos/presentation/controllers/contatos_controllers.dart';
import 'package:tenant_module/src/features/contatos/presentation/pages/contatos_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() => registerFallbackValue(proto.ListMyContatosRequest()));
  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  Contato contatoCom({
    String nomeContato = '',
    String nomePerfilWhatsapp = '',
    String telefone = '',
    bool ativo = true,
  }) =>
      Contato(
        id: 1,
        telefone: telefone,
        nomeContato: nomeContato,
        nomePerfilWhatsapp: nomePerfilWhatsapp,
        email: '',
        ativo: ativo,
        ultimaInteracao: DateTime.now(),
        cadastradoEm: DateTime.now(),
      );

  group('nome de exibição', () {
    test('o cadastro ganha do perfil do WhatsApp', () {
      // Quem cadastrou o contato escolheu aquele nome de propósito; o perfil
      // do WhatsApp é o que a própria pessoa pôs, e muda sem aviso.
      expect(
        contatoCom(nomeContato: 'Maria Silva', nomePerfilWhatsapp: 'Mari 💜')
            .exibicao,
        'Maria Silva',
      );
    });

    test('sem cadastro, o perfil do WhatsApp serve', () {
      expect(
        contatoCom(nomePerfilWhatsapp: 'Mari 💜', telefone: '5511999').exibicao,
        'Mari 💜',
      );
    });

    test('sem nome nenhum, o telefone é melhor que linha em branco', () {
      final c = contatoCom(telefone: '5511999998888');
      expect(c.exibicao, '5511999998888');
      expect(c.semNome, isTrue);
    });

    test('nome só com espaço não conta como nome', () {
      // Espaço em branco passa em `isNotEmpty` e deixaria a linha aparentemente
      // vazia na lista.
      expect(contatoCom(nomeContato: '   ', telefone: '551199').exibicao,
          '551199');
    });

    test('sem nome e sem telefone ainda rende alguma coisa na tela', () {
      expect(contatoCom().exibicao, 'Sem identificação');
    });

    test('contato com cadastro não é marcado como pendente', () {
      expect(contatoCom(nomeContato: 'Maria').semNome, isFalse);
      expect(contatoCom(nomePerfilWhatsapp: 'Mari').semNome, isFalse);
    });
  });

  group('ContatosPage', () {
    void registrar() {
      getIt.registerSingleton<ContatosController>(
        ContatosController(
          listar: ListarContatosUsecase(
            repository: ListarContatosRepository(
              datasource: ListarContatosDatasource(client: client),
            ),
          ),
        ),
      );
      final auth = _MockAuthService();
      when(() => auth.currentSession).thenReturn(null);
      getIt.registerSingleton<AuthService>(auth);
    }

    void responde(List<proto.MyContato> contatos) {
      when(() => client.listMyContatos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyContatosResponse(contatos: contatos),
        ),
      );
    }

    proto.MyContato pb({
      int id = 1,
      String nome = '',
      String perfil = '',
      String telefone = '',
      bool ativo = true,
      int diasAtras = 0,
    }) =>
        proto.MyContato(
          id: id,
          telefone: telefone,
          nomeContato: nome,
          nomePerfilWhatsapp: perfil,
          ativo: ativo,
          ultimaInteracao: Int64(
            DateTime.now()
                .subtract(Duration(days: diasAtras))
                .millisecondsSinceEpoch,
          ),
        );

    Future<void> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const ContatosPage())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
    }

    testWidgets('lista os contatos', (tester) async {
      responde([
        pb(nome: 'Maria Silva', telefone: '5511999998888'),
        pb(id: 2, perfil: 'João', telefone: '5511777776666', diasAtras: 40),
      ]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Maria Silva'), findsOneWidget);
      expect(find.text('João'), findsOneWidget);
      expect(find.text('hoje'), findsOneWidget);
      expect(find.text('há 1 meses'), findsOneWidget);
    });

    testWidgets('contato só com número é marcado como pendente', (
      tester,
    ) async {
      responde([pb(telefone: '5511999998888')]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Sem cadastro'), findsOneWidget);
    });

    testWidgets('contato inativo mostra o estado, não a pendência', (
      tester,
    ) async {
      responde([pb(telefone: '5511999998888', ativo: false)]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Inativo'), findsOneWidget);
      expect(find.text('Sem cadastro'), findsNothing);
    });

    testWidgets('conta sem contato nenhum explica de onde eles vêm', (
      tester,
    ) async {
      responde([]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum contato ainda'), findsOneWidget);
    });

    testWidgets('a busca vai ao servidor, uma vez só, depois da pausa', (
      tester,
    ) async {
      // Sem o atraso, digitar dez letras dispararia dez varreduras no banco e
      // a última resposta nem seria necessariamente a que fica na tela.
      responde([pb(nome: 'Maria Silva')]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'mar');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'maria');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final enviados = verify(() => client.listMyContatos(captureAny()))
          .captured
          .cast<proto.ListMyContatosRequest>();
      // Uma na montagem, uma da busca — o 'mar' intermediário foi descartado.
      expect(enviados, hasLength(2));
      expect(enviados.last.busca, 'maria');
    });

    testWidgets('busca sem resultado diz que foi o filtro', (tester) async {
      // Confundir "nada encontrado" com "conta vazia" mandaria a pessoa
      // procurar defeito onde só há filtro.
      responde([]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Nada encontrado'), findsOneWidget);
      expect(find.textContaining('"zzz"'), findsOneWidget);
    });

    testWidgets('recarregar mantém o filtro digitado', (tester) async {
      responde([pb(nome: 'Maria Silva')]);
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'maria');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Recarregar'));
      await tester.pumpAndSettle();

      final enviados = verify(() => client.listMyContatos(captureAny()))
          .captured
          .cast<proto.ListMyContatosRequest>();
      expect(enviados.last.busca, 'maria');
    });

    testWidgets('erro do servidor vira tela de erro', (tester) async {
      when(() => client.listMyContatos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
      );
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });

    test('sessão expirada é distinguida de servidor fora do ar', () async {
      when(() => client.listMyContatos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unauthenticated('expirou')),
      );

      final res = await ListarContatosUsecase(
        repository: ListarContatosRepository(
          datasource: ListarContatosDatasource(client: client),
        ),
      )(const ListarContatosParameters());

      expect((res as Failure).error, isA<ContatosAcessoNegado>());
    });
  });
}
