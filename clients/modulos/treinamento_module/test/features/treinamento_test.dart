import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:treinamento_module/src/features/treinamento/data/datasources/treinamento_datasources.dart';
import 'package:treinamento_module/src/features/treinamento/data/repositories/treinamento_repositories.dart';
import 'package:treinamento_module/src/features/treinamento/domain/errors/treinamento_errors.dart';
import 'package:treinamento_module/src/features/treinamento/domain/model/treinamento.dart';
import 'package:treinamento_module/src/features/treinamento/domain/parameters/treinamento_parameters.dart';
import 'package:treinamento_module/src/features/treinamento/domain/usecases/treinamento_usecases.dart';

class MockAdminClient extends Mock implements proto.AdminServiceClient {}

proto.MyTreinamento protoTreinamento({
  int id = 1,
  bool finalizado = false,
  bool vetorizado = false,
}) =>
    proto.MyTreinamento(
      id: id,
      tag: 'horario',
      grupo: 'atendimento',
      conteudo: 'Abrimos de segunda a sexta, das 8h às 18h.',
      finalizado: finalizado,
      vetorizado: vetorizado,
      criadoEm: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
      atualizadoEm: Int64(DateTime(2026, 8, 2).millisecondsSinceEpoch),
    );

void main() {
  late MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyTreinamentosRequest());
    registerFallbackValue(proto.CreateMyTreinamentoRequest());
    registerFallbackValue(proto.GetMyTreinamentoRequest());
    registerFallbackValue(proto.FinalizarMyTreinamentoRequest());
    registerFallbackValue(proto.RemoverMyTreinamentoRequest());
  });

  setUp(() => client = MockAdminClient());

  ListarTreinamentosUsecase listarUsecase() => ListarTreinamentosUsecase(
        repository: ListarTreinamentosRepository(
          datasource: ListarTreinamentosDatasource(client: client),
        ),
      );

  group('situação derivada dos dois booleanos', () {
    // A tela mostra os três estados do ciclo; eles não vêm prontos do servidor,
    // são derivados de `finalizado`/`vetorizado`.
    test('rascunho enquanto não foi aceito', () {
      final t = _dominio(finalizado: false, vetorizado: false);
      expect(t.situacao, SituacaoTreinamento.rascunho);
    });

    test('processando depois de aceito, antes de virar vetor', () {
      final t = _dominio(finalizado: true, vetorizado: false);
      expect(t.situacao, SituacaoTreinamento.naFila);
    });

    test('ativo quando já virou vetor', () {
      final t = _dominio(finalizado: true, vetorizado: true);
      expect(t.situacao, SituacaoTreinamento.ativo);
    });

    test('vetorizado vence: material em uso não volta a ser rascunho', () {
      // Defensivo contra estado inconsistente vindo do banco — se está
      // vetorizado, o assistente já responde com ele.
      final t = _dominio(finalizado: false, vetorizado: true);
      expect(t.situacao, SituacaoTreinamento.ativo);
    });
  });

  test('listar converte o protobuf para o domínio', () async {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyTreinamentosResponse(
          treinamentos: [protoTreinamento(vetorizado: true, finalizado: true)],
        ),
      ),
    );

    final res = await listarUsecase()(noParams);
    final itens = (res as Success<List<Treinamento>, TreinamentoError>).value;

    expect(itens, hasLength(1));
    expect(itens.first.tag, 'horario');
    expect(itens.first.situacao, SituacaoTreinamento.ativo);
  });

  test('criar envia os três campos', () async {
    when(() => client.createMyTreinamento(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.MyTreinamentoResponse(treinamento: protoTreinamento()),
      ),
    );

    final usecase = CriarTreinamentoUsecase(
      repository: CriarTreinamentoRepository(
        datasource: CriarTreinamentoDatasource(client: client),
      ),
    );
    final res = await usecase(
      const CriarTreinamentoParameters(
        tag: 'horario',
        grupo: 'atendimento',
        conteudo: 'Abrimos de segunda a sexta.',
      ),
    );

    expect(res, isA<Success<Treinamento, TreinamentoError>>());
    final enviado = verify(() => client.createMyTreinamento(captureAny()))
        .captured
        .single as proto.CreateMyTreinamentoRequest;
    expect(enviado.tag, 'horario');
    expect(enviado.grupo, 'atendimento');
    expect(enviado.conteudo, 'Abrimos de segunda a sexta.');
  });

  test('finalizar leva o texto revisado, não o original', () async {
    // O ponto: é o texto que está na tela que vira vetor. Enviar o original
    // faria a revisão não valer nada.
    when(() => client.finalizarMyTreinamento(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );

    final usecase = FinalizarTreinamentoUsecase(
      repository: FinalizarTreinamentoRepository(
        datasource: FinalizarTreinamentoDatasource(client: client),
      ),
    );
    await usecase(
      const FinalizarTreinamentoParameters(id: 7, conteudo: 'texto revisado'),
    );

    final enviado = verify(() => client.finalizarMyTreinamento(captureAny()))
        .captured
        .single as proto.FinalizarMyTreinamentoRequest;
    expect(enviado.id, 7);
    expect(enviado.conteudo, 'texto revisado');
  });

  group('tradução de erro', () {
    test('permissão negada vira erro de autorização', () async {
      when(() => client.listMyTreinamentos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final res = await listarUsecase()(noParams);
      expect((res as Failure).error, isA<TreinamentoNaoAutorizado>());
    });

    test('servidor fora do ar vira erro de rede', () async {
      when(() => client.listMyTreinamentos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
      );

      final res = await listarUsecase()(noParams);
      expect((res as Failure).error, isA<TreinamentoIndisponivel>());
    });

    test('recusa de validação preserva a mensagem do servidor', () async {
      // A mensagem vem do servidor porque é ele quem sabe o motivo — repetir
      // um texto genérico aqui esconderia a causa de quem está na tela.
      when(() => client.createMyTreinamento(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument('informe a tag e o grupo'),
        ),
      );

      final usecase = CriarTreinamentoUsecase(
        repository: CriarTreinamentoRepository(
          datasource: CriarTreinamentoDatasource(client: client),
        ),
      );
      final res = await usecase(
        const CriarTreinamentoParameters(tag: '', grupo: '', conteudo: 'x'),
      );

      final erro = (res as Failure).error;
      expect(erro, isA<TreinamentoDadosInvalidos>());
      expect(erro.message, contains('informe a tag e o grupo'));
    });
  });
}

Treinamento _dominio({required bool finalizado, required bool vetorizado}) =>
    Treinamento(
      id: 1,
      tag: 'horario',
      grupo: 'atendimento',
      conteudo: 'x',
      finalizado: finalizado,
      vetorizado: vetorizado,
      criadoEm: DateTime(2026, 8, 1),
      atualizadoEm: DateTime(2026, 8, 2),
    );
