import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/equipe/data/datasources/equipe_datasources.dart';
import 'package:tenant_module/src/features/equipe/data/repositories/equipe_repositories.dart';
import 'package:tenant_module/src/features/equipe/domain/errors/equipe_errors.dart';
import 'package:tenant_module/src/features/equipe/domain/model/equipe.dart';
import 'package:tenant_module/src/features/equipe/domain/parameters/equipe_parameters.dart';
import 'package:tenant_module/src/features/equipe/domain/usecases/equipe_usecases.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyDepartamentosRequest());
    registerFallbackValue(proto.ListMyAtendentesRequest());
    registerFallbackValue(proto.CreateMyDepartamentoRequest());
    registerFallbackValue(proto.UpdateMyDepartamentoRequest());
    registerFallbackValue(proto.MyDepartamentoIdRequest());
  });

  setUp(() => client = _MockAdminClient());

  CarregarEquipeUsecase carregar() => CarregarEquipeUsecase(
        repository: CarregarEquipeRepository(
          datasource: CarregarEquipeDatasource(client: client),
        ),
      );

  void respondeListas({
    List<proto.MyDepartamento> departamentos = const [],
    List<proto.MyAtendente> atendentes = const [],
  }) {
    when(() => client.listMyDepartamentos(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyDepartamentosResponse(departamentos: departamentos),
      ),
    );
    when(() => client.listMyAtendentes(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyAtendentesResponse(atendentes: atendentes),
      ),
    );
  }

  test('carrega as duas listas num estado só', () async {
    // Carregar em separado deixaria metade da tela viva enquanto a outra
    // falha — e a relação entre departamento e atendente é o que importa aqui.
    respondeListas(
      departamentos: [
        proto.MyDepartamento(
          id: 1,
          nome: 'Suporte',
          slug: 'suporte',
          descricao: 'Dúvidas',
          ativo: true,
          criadoEm: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
        ),
      ],
      atendentes: [
        proto.MyAtendente(
          id: 9,
          nome: 'Ana',
          email: 'ana@x.com',
          cargo: 'Atendente',
          departamentoId: 1,
          ativo: true,
          disponivel: false,
          maxAtendimentosSimultaneos: 5,
        ),
      ],
    );

    final res = await carregar()(noParams);
    final equipe = (res as Success<Equipe, EquipeError>).value;

    expect(equipe.departamentos, hasLength(1));
    expect(equipe.departamentos.first.slug, 'suporte');
    expect(equipe.atendentes, hasLength(1));
    // Ativo e disponível são estados distintos: quem está de férias fica ativo
    // e indisponível, e a tela precisa distinguir.
    expect(equipe.atendentes.first.ativo, isTrue);
    expect(equipe.atendentes.first.disponivel, isFalse);
  });

  test('atendente sem departamento chega como 0, não como erro', () async {
    respondeListas(
      atendentes: [
        proto.MyAtendente(id: 2, nome: 'Bruno', departamentoId: 0, ativo: true),
      ],
    );

    final res = await carregar()(noParams);
    final equipe = (res as Success<Equipe, EquipeError>).value;
    expect(equipe.atendentes.first.departamentoId, 0);
  });

  test('atualizar envia id, nome e o estado ativo', () async {
    when(() => client.updateMyDepartamento(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    respondeListas();

    final usecase = AtualizarDepartamentoUsecase(
      repository: AtualizarDepartamentoRepository(
        datasource: AtualizarDepartamentoDatasource(client: client),
      ),
    );
    await usecase(
      const AtualizarDepartamentoParameters(
        id: 4,
        nome: 'Vendas',
        descricao: 'Pré-venda',
        ativo: false,
      ),
    );

    final enviado = verify(() => client.updateMyDepartamento(captureAny()))
        .captured
        .single as proto.UpdateMyDepartamentoRequest;
    expect(enviado.id, 4);
    expect(enviado.nome, 'Vendas');
    expect(enviado.ativo, isFalse);
  });

  group('tradução de erro', () {
    test('teto do plano NÃO vira "servidor indisponível"', () async {
      // O servidor recusa com RESOURCE_EXHAUSTED quando o plano não tem mais
      // vagas. Traduzir para indisponibilidade mandaria o tenant tentar de
      // novo para sempre; o caminho é mudar de plano.
      when(() => client.createMyDepartamento(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.resourceExhausted('limite atingido')),
      );

      final usecase = CriarDepartamentoUsecase(
        repository: CriarDepartamentoRepository(
          datasource: CriarDepartamentoDatasource(client: client),
        ),
      );
      final res = await usecase(
        const CriarDepartamentoParameters(nome: 'x', descricao: ''),
      );

      expect((res as Failure).error, isA<LimiteDeDepartamentos>());
    });

    test('sem escopo vira acesso negado', () async {
      when(() => client.listMyDepartamentos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );
      when(() => client.listMyAtendentes(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyAtendentesResponse()),
      );

      final res = await carregar()(noParams);
      expect((res as Failure).error, isA<EquipeAcessoNegado>());
    });

    test('recusa de validação preserva a mensagem do servidor', () async {
      when(() => client.updateMyDepartamento(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument('informe o nome do departamento'),
        ),
      );

      final usecase = AtualizarDepartamentoUsecase(
        repository: AtualizarDepartamentoRepository(
          datasource: AtualizarDepartamentoDatasource(client: client),
        ),
      );
      final res = await usecase(
        const AtualizarDepartamentoParameters(
          id: 1,
          nome: '',
          descricao: '',
          ativo: true,
        ),
      );

      final erro = (res as Failure).error;
      expect(erro, isA<EquipeDadosInvalidos>());
      expect(erro.message, contains('informe o nome'));
    });
  });
}
