import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/billing/data/datasources/billing_datasources.dart';
import 'package:admin_module/src/features/billing/data/repositories/billing_repositories.dart';
import 'package:admin_module/src/features/billing/domain/errors/billing_errors.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/billing/domain/parameters/billing_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `billing`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('listPlans', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.listPlans(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('createPlan', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.createPlan(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const CreatePlanParameters(
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('updatePlan', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.updatePlan(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpdatePlanParameters(
          id: 1,
          name: 'n',
          description: 'd',
          price: '10',
          maxInstances: 1,
          maxDepartments: 2,
          maxFluxos: 3,
          active: true,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('listSubscriptions', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('registerPayment', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.registerPayment(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      );

      final r = await usecase(
        const RegisterPaymentParameters(
          tenantId: 't1',
          amount: '10',
          paymentMethod: 'pix',
          paymentDate: '2026-01-01',
          periodStart: '2026-01-01',
          periodEnd: '2026-02-01',
          notes: '',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('listPayments', () {
    test('permissionDenied -> BillingAcessoNegado', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> BillingAcessoNegado', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> BillingNaoEncontrado', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingNaoEncontrado>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> BillingConflito', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingConflito>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> BillingDadosInvalidos', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> BillingDadosInvalidos', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> BillingIndisponivel', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> BillingIndisponivel', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> BillingInesperado', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> BillingInesperado', () async {
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      );

      final r = await usecase(const ListPaymentsParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<BillingInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as BillingError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
