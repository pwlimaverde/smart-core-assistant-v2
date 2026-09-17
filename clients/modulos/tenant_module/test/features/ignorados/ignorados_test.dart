import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/ignorados/data/datasources/ignorados_datasources.dart';
import 'package:tenant_module/src/features/ignorados/data/repositories/ignorados_repositories.dart';
import 'package:tenant_module/src/features/ignorados/domain/errors/ignorados_errors.dart';
import 'package:tenant_module/src/features/ignorados/domain/model/numero_ignorado.dart';
import 'package:tenant_module/src/features/ignorados/domain/parameters/ignorados_parameters.dart';
import 'package:tenant_module/src/features/ignorados/domain/usecases/ignorados_usecases.dart';
import 'package:tenant_module/src/features/ignorados/presentation/controllers/ignorados_controller.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// P7 — os números que o sistema ignora (a "whitelist" da v1).
void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyNumerosIgnoradosRequest());
    registerFallbackValue(proto.CriarNumeroIgnoradoRequest());
    registerFallbackValue(proto.AtualizarNumeroIgnoradoRequest());
    registerFallbackValue(proto.NumeroIgnoradoIdRequest());
  });

  setUp(() => client = _MockAdminClient());

  IgnoradosController controller() => IgnoradosController(
    listar: ListarIgnoradosUsecase(
      repository: ListarIgnoradosRepository(
        datasource: ListarIgnoradosDatasource(client: client),
      ),
    ),
    criar: CriarIgnoradoUsecase(
      repository: CriarIgnoradoRepository(
        datasource: CriarIgnoradoDatasource(client: client),
      ),
    ),
    atualizar: AtualizarIgnoradoUsecase(
      repository: AtualizarIgnoradoRepository(
        datasource: AtualizarIgnoradoDatasource(client: client),
      ),
    ),
    remover: RemoverIgnoradoUsecase(
      repository: RemoverIgnoradoRepository(
        datasource: RemoverIgnoradoDatasource(client: client),
      ),
    ),
  );

  void listaResponde(List<proto.MyNumeroIgnorado> itens) {
    when(() => client.listMyNumerosIgnorados(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyNumerosIgnoradosResponse(itens: itens)),
    );
  }

  proto.MyNumeroIgnorado item({
    int id = 1,
    String telefone = '5511999999999',
    bool ativo = true,
  }) => proto.MyNumeroIgnorado(
    id: id,
    nome: 'Contador',
    telefone: telefone,
    ativo: ativo,
    criadoEm: Int64(DateTime(2026, 9, 1).millisecondsSinceEpoch),
  );

  test('a lista traz também os desligados', () async {
    // Desligar é como se volta a atender alguém sem perder o registro de que
    // ele esteve fora. Se a listagem escondesse os inativos, religar a regra
    // exigiria cadastrar o número de novo.
    listaResponde([item(), item(id: 2, telefone: '5511888888888', ativo: false)]);

    final res = await ListarIgnoradosUsecase(
      repository: ListarIgnoradosRepository(
        datasource: ListarIgnoradosDatasource(client: client),
      ),
    )(noParams);

    final itens = (res as Success<List<NumeroIgnorado>, IgnoradosError>).value;
    expect(itens, hasLength(2));
    expect(itens.map((i) => i.ativo), [true, false]);
  });

  test('criar manda número e nome e recarrega a lista', () async {
    listaResponde([item()]);
    when(() => client.criarNumeroIgnorado(any())).thenAnswer(
      (_) => respostaGrpc(proto.MyNumeroIgnoradoResponse(item: item())),
    );
    final c = controller();

    final erro = await c.criar(nome: 'Contador', telefone: '5511999999999');

    expect(erro, isNull);
    final enviado = verify(
      () => client.criarNumeroIgnorado(captureAny()),
    ).captured.single as proto.CriarNumeroIgnoradoRequest;
    expect(enviado.telefone, '5511999999999');
    expect(enviado.nome, 'Contador');
    // Recarregou: a lista na tela precisa mostrar o que acabou de entrar.
    verify(() => client.listMyNumerosIgnorados(any())).called(1);
    await c.close();
  });

  test('número repetido vira recusa com a mensagem do servidor', () async {
    // O par (tenant, telefone) é único; repetir o número é o erro mais comum
    // desta tela, e a mensagem precisa dizer isso em vez de "algo deu errado".
    when(() => client.criarNumeroIgnorado(any())).thenThrow(
      GrpcError.alreadyExists('Este número já está na lista'),
    );
    final c = controller();

    final erro = await c.criar(nome: '', telefone: '5511999999999');

    expect(erro, isA<IgnoradoRecusado>());
    expect(erro!.message, contains('já está na lista'));
    await c.close();
  });

  test('desligar preserva nome e telefone', () async {
    // Alternar manda o registro inteiro: mandar só o `ativo` apagaria o nome,
    // porque o servidor grava os três campos de uma vez.
    listaResponde([item(ativo: false)]);
    when(() => client.atualizarNumeroIgnorado(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    final c = controller();

    final erro = await c.atualizar(
      id: 1,
      nome: 'Contador',
      telefone: '5511999999999',
      ativo: false,
    );

    expect(erro, isNull);
    final enviado = verify(
      () => client.atualizarNumeroIgnorado(captureAny()),
    ).captured.single as proto.AtualizarNumeroIgnoradoRequest;
    expect(enviado.nome, 'Contador');
    expect(enviado.telefone, '5511999999999');
    expect(enviado.ativo, isFalse);
    await c.close();
  });

  test('remover manda o id e recarrega', () async {
    listaResponde([]);
    when(() => client.removerNumeroIgnorado(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    final c = controller();

    final erro = await c.remover(7);

    expect(erro, isNull);
    final enviado = verify(
      () => client.removerNumeroIgnorado(captureAny()),
    ).captured.single as proto.NumeroIgnoradoIdRequest;
    expect(enviado.id, 7);
    await c.close();
  });

  test('sessão expirada não vira "sem permissão"', () async {
    // Juntar as duas manda o dono da conta caçar um acesso que ele já tem.
    when(() => client.listMyNumerosIgnorados(any()))
        .thenThrow(GrpcError.unauthenticated('token expirado'));

    final res = await ListarIgnoradosUsecase(
      repository: ListarIgnoradosRepository(
        datasource: ListarIgnoradosDatasource(client: client),
      ),
    )(noParams);

    expect(
      (res as Failure<List<NumeroIgnorado>, IgnoradosError>).error,
      isA<IgnoradosSessaoExpirada>(),
    );
  });

  test('parameters carregam o que a tela precisa mandar', () {
    const p = AtualizarIgnoradoParameters(
      id: 3,
      nome: 'Equipe',
      telefone: '5511777777777',
      ativo: true,
    );
    expect(p.id, 3);
    expect(const IgnoradoIdParameters(id: 9).id, 9);
    expect(
      const CriarIgnoradoParameters(nome: 'x', telefone: 'y').telefone,
      'y',
    );
  });
}
