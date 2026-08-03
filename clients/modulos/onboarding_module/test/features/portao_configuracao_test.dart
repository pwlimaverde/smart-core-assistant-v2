import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onboarding_module/onboarding_module.dart';
import 'package:onboarding_module/src/features/configuracao/data/datasources/configuracao_datasources.dart';
import 'package:onboarding_module/src/features/configuracao/data/repositories/configuracao_repositories.dart';
import 'package:onboarding_module/src/features/configuracao/domain/usecases/configuracao_usecases.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.GetMyOnboardingProgressRequest());
  });

  setUp(() => client = _MockAdminClient());

  PortaoConfiguracao portao() => PortaoConfiguracao(
        consultar: ConsultarProgressoUsecase(
          repository: ConsultarProgressoRepository(
            datasource: ConsultarProgressoDatasource(client: client),
          ),
        ),
      );

  void respondeProgresso({required bool concluido, required int passo}) {
    when(() => client.getMyOnboardingProgress(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetMyOnboardingProgressResponse(
          passo: passo,
          concluido: concluido,
        ),
      ),
    );
  }

  test('antes de consultar, não se sabe — o guard segura na splash', () async {
    respondeProgresso(concluido: false, passo: 6);
    final p = portao();
    expect(p.pendente, isNull);

    await p.avaliar();
    expect(p.pendente, isTrue);
    expect(p.passo, 6);
  });

  test('roteiro concluído libera o workspace', () async {
    respondeProgresso(concluido: true, passo: 8);
    final p = portao();
    await p.avaliar();
    expect(p.pendente, isFalse);
  });

  test('concluir libera sem nova consulta, e notifica o router', () async {
    // Regressão: a tela final gravava a conclusão no servidor e navegava para
    // '/atendimentos', mas o portão — que é quem o guard consulta — continuava
    // dizendo "pendente". O guard devolvia a tela para o roteiro, e não havia
    // como sair do laço.
    respondeProgresso(concluido: false, passo: 8);
    final p = portao();
    await p.avaliar();
    expect(p.pendente, isTrue);

    var notificou = false;
    p.addListener(() => notificou = true);

    p.concluir();

    expect(p.pendente, isFalse);
    expect(notificou, isTrue, reason: 'o router precisa reavaliar a rota');
    // Uma consulta só: concluir não pode depender de ida ao servidor.
    verify(() => client.getMyOnboardingProgress(any())).called(1);
  });

  test('consulta que falha não prende ninguém no roteiro', () async {
    when(() => client.getMyOnboardingProgress(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
    );
    final p = portao();

    await p.avaliar();

    // Prender alguém no roteiro por causa de uma consulta que falhou é pior do
    // que deixá-lo entrar: o roteiro é retomável, o workspace não some.
    expect(p.pendente, isFalse);
  });

  test('limpar esquece — a próxima sessão pode ser de outro tenant', () async {
    respondeProgresso(concluido: true, passo: 8);
    final p = portao();
    await p.avaliar();
    expect(p.pendente, isFalse);

    p.limpar();
    expect(p.pendente, isNull);
  });
}
