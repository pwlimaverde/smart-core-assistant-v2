import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/tenants/data/datasources/tenants_datasources.dart';
import 'package:admin_module/src/features/tenants/data/repositories/tenants_repositories.dart';
import 'package:admin_module/src/features/tenants/domain/errors/tenants_errors.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:admin_module/src/features/tenants/domain/parameters/tenants_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `tenants`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('listTenants', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('getTenant', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.getTenant(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('createTenant', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.createTenant(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreateTenantParameters(
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('updateTenant', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.updateTenant(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdateTenantParameters(
          id: 't1',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e@e.com',
          phone: '1',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('setTenantActive', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetTenantActiveParameters(id: 't1', active: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('generateAccessCode', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(
        () => client.generateAccessCode(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      );

      final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('exportTenantsCsv', () {
    test('permissionDenied -> TenantsAcessoNegado', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(
          const [],
          GrpcError.permissionDenied('sem escopo'),
        ),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantsAcessoNegado', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(
          const [],
          GrpcError.unauthenticated('sem sessao'),
        ),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantsNaoEncontrado', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(const [], GrpcError.notFound('inexistente')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsNaoEncontrado>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantsConflito', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) =>
            streamGrpcComFalha(const [], GrpcError.alreadyExists('duplicado')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsConflito>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantsDadosInvalidos', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) =>
            streamGrpcComFalha(const [], GrpcError.invalidArgument('invalido')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantsDadosInvalidos', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(
          const [],
          GrpcError.failedPrecondition('estado'),
        ),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantsIndisponivel', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(const [], GrpcError.unavailable('offline')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantsIndisponivel', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) =>
            streamGrpcComFalha(const [], GrpcError.resourceExhausted('quota')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantsInesperado', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(const [], GrpcError.internal('boom')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantsInesperado', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpcComFalha(const [], const FormatException('json')),
      );
      final usecase = ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<TenantsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
