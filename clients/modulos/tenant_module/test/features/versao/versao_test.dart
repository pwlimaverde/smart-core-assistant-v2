import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:dependencies_module/dependencies_module.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/versao/data/versao_datasource.dart';
import 'package:tenant_module/src/features/versao/domain/versao_do_app.dart';
import 'package:tenant_module/src/features/versao/presentation/aviso_versao.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// P11 — aviso de versão nova do app Windows.
void main() {
  late _MockAdminClient client;

  setUpAll(() => registerFallbackValue(proto.GetVersaoDoAppRequest()));
  setUp(() => client = _MockAdminClient());
  tearDown(() => GetIt.instance.reset());

  void publicado(int build, {String url = 'https://x/app.zip'}) {
    when(() => client.getVersaoDoApp(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetVersaoDoAppResponse(
          buildAtual: Int64(build),
          urlDownload: url,
          notas: 'correções no chat',
        ),
      ),
    );
    GetIt.instance.registerSingleton<ConsultarVersaoUsecase>(
      ConsultarVersaoUsecase(
        repository: ConsultarVersaoRepository(
          datasource: ConsultarVersaoDatasource(client: client),
        ),
      ),
    );
  }

  group('quando avisar', () {
    const v = VersaoPublicada(build: 202609191200, urlDownload: 'u', notas: '');

    test('só com build publicado maior que o local', () {
      expect(v.maisNovaQue(202609181200), isTrue);
      expect(v.maisNovaQue(202609191200), isFalse);
      expect(v.maisNovaQue(202609201200), isFalse);
    });

    test('build local desconhecido nunca avisa', () {
      // Sem saber a própria versão, o app não tem como dizer que está velho.
      expect(v.maisNovaQue(0), isFalse);
    });

    test('sem link para baixar não avisa', () {
      // Faixa sem botão seria só incômodo.
      const semUrl = VersaoPublicada(build: 9, urlDownload: '', notas: '');
      expect(semUrl.maisNovaQue(1), isFalse);
    });
  });

  testWidgets('versão nova aparece com o botão de baixar', (tester) async {
    publicado(202609191200);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AvisoVersao(build: 202609010000, somenteDesktop: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('versão nova'), findsOneWidget);
    expect(find.text('Baixar'), findsOneWidget);

    await tester.tap(find.text('Depois'));
    await tester.pump();
    expect(find.text('Baixar'), findsNothing);
  });

  testWidgets('na mesma versão não aparece nada', (tester) async {
    publicado(202609010000);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AvisoVersao(build: 202609010000, somenteDesktop: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Baixar'), findsNothing);
  });
}
