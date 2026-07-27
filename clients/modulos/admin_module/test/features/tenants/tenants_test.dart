import 'package:admin_module/src/features/tenants/data/datasources/tenants_datasources.dart';
import 'package:admin_module/src/features/tenants/data/repositories/tenants_repositories.dart';
import 'package:admin_module/src/features/tenants/domain/errors/tenants_errors.dart';
import 'package:admin_module/src/features/tenants/domain/model/tenant.dart';
import 'package:admin_module/src/features/tenants/domain/parameters/tenants_parameters.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:admin_module/src/features/tenants/presentation/controllers/tenants_controller.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

proto.Tenant _tenantProto({
  String id = 't1',
  String name = 'Empresa X',
  bool active = true,
  int ownerId = 7,
}) => proto.Tenant(
  id: id,
  name: name,
  slug: 'empresa-x',
  apiKey: 'chave',
  ownerId: ownerId,
  email: 'contato@x.com',
  phone: '11999',
  active: active,
  setupCompleted: true,
  onboardingStep: 3,
  accessCode: 'ACESSO-1',
  createdAt: ms(DateTime(2026, 1, 1)),
  updatedAt: ms(DateTime(2026, 2, 1)),
);

TenantsController _controller(MockAdminClient client) => TenantsController(
  listUsecase: ListTenantsUsecase(
    repository: ListTenantsRepository(
      datasource: ListTenantsDatasource(client: client),
    ),
  ),
  createUsecase: CreateTenantUsecase(
    repository: CreateTenantRepository(
      datasource: CreateTenantDatasource(client: client),
    ),
  ),
  updateUsecase: UpdateTenantUsecase(
    repository: UpdateTenantRepository(
      datasource: UpdateTenantDatasource(client: client),
    ),
  ),
  setActiveUsecase: SetTenantActiveUsecase(
    repository: SetTenantActiveRepository(
      datasource: SetTenantActiveDatasource(client: client),
    ),
  ),
  generateAccessCodeUsecase: GenerateAccessCodeUsecase(
    repository: GenerateAccessCodeRepository(
      datasource: GenerateAccessCodeDatasource(client: client),
    ),
  ),
);

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  void listaResponde(List<proto.Tenant> tenants) =>
      when(() => client.listTenants(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListTenantsResponse(tenants: tenants)),
      );

  group('conversão protobuf → domínio', () {
    test('listTenants converte todos os campos do tenant', () async {
      listaResponde([_tenantProto()]);

      final r = await ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      )(noParams);

      final t = (r as Success<List<Tenant>, TenantsError>).value.single;
      expect(t.id, 't1');
      expect(t.name, 'Empresa X');
      expect(t.slug, 'empresa-x');
      expect(t.ownerId, 7);
      expect(t.active, isTrue);
      expect(t.accessCode, 'ACESSO-1');
    });

    test('createTenant envia os campos do formulário', () async {
      when(() => client.createTenant(any())).thenAnswer(
        (_) => respostaGrpc(proto.CreateTenantResponse(tenant: _tenantProto())),
      );

      await CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: client),
        ),
      )(
        const CreateTenantParameters(
          name: 'Nova',
          slug: 'nova',
          ownerId: 9,
          email: 'a@b.com',
          phone: '11888',
        ),
      );

      final enviado =
          verify(() => client.createTenant(captureAny())).captured.single
              as proto.CreateTenantRequest;
      expect(enviado.name, 'Nova');
      expect(enviado.slug, 'nova');
      expect(enviado.ownerId, 9);
      expect(enviado.email, 'a@b.com');
      expect(enviado.phone, '11888');
    });

    test('generateAccessCode devolve o código gerado', () async {
      when(() => client.generateAccessCode(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GenerateAccessCodeResponse(accessCode: 'NOVO-CODIGO'),
        ),
      );

      final r = await GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: client),
        ),
      )(const GenerateAccessCodeParameters(id: 't1'));

      expect((r as Success).value, 'NOVO-CODIGO');
    });

    test('exportTenantsCsv concatena os chunks do stream', () async {
      // O RPC é de streaming: o datasource precisa juntar os pedaços na ordem.
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpc([
          proto.ExportTenantsCsvResponse(chunk: [1, 2]),
          proto.ExportTenantsCsvResponse(chunk: [3]),
        ]),
      );

      final r = await ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      )(noParams);

      expect((r as Success).value, [1, 2, 3]);
    });

    test('setTenantActive envia o id e o novo estado', () async {
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SetTenantActiveResponse()));

      await SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: client),
        ),
      )(const SetTenantActiveParameters(id: 't9', active: false));

      final enviado =
          verify(() => client.setTenantActive(captureAny())).captured.single
              as proto.SetTenantActiveRequest;
      expect(enviado.id, 't9');
      expect(enviado.active, isFalse);
    });
  });

  group('TenantsController', () {
    blocTest<TenantsController, ViewState<List<Tenant>>>(
      'carrega a lista: [Loading, Success]',
      build: () {
        listaResponde([_tenantProto(), _tenantProto(id: 't2')]);
        return _controller(client);
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<SuccessState<List<Tenant>>>().having(
          (s) => s.data,
          'tenants',
          hasLength(2),
        ),
      ],
    );

    blocTest<TenantsController, ViewState<List<Tenant>>>(
      'sem escopo de superusuário: [Loading, Error] com acesso negado',
      build: () {
        when(() => client.listTenants(any())).thenAnswer(
          (_) => falhaGrpc(proto.GrpcError.permissionDenied('nao superuser')),
        );
        return _controller(client);
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<ErrorState<List<Tenant>>>().having(
          (s) => s.error,
          'erro',
          isA<TenantsAcessoNegado>(),
        ),
      ],
    );

    test('criar tenant com sucesso recarrega a lista', () async {
      listaResponde([_tenantProto()]);
      when(() => client.createTenant(any())).thenAnswer(
        (_) => respostaGrpc(proto.CreateTenantResponse(tenant: _tenantProto())),
      );
      final controller = _controller(client);

      final r = await controller.createTenant(
        name: 'Nova',
        slug: 'nova',
        ownerId: 1,
        email: 'a@b.com',
        phone: '1',
      );

      expect(r, isA<Success>());
      verify(() => client.listTenants(any())).called(1);
      await controller.close();
    });

    test('slug duplicado devolve conflito e NÃO recarrega a lista', () async {
      listaResponde([_tenantProto()]);
      when(() => client.createTenant(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.alreadyExists('slug em uso')),
      );
      final controller = _controller(client);

      final r = await controller.createTenant(
        name: 'Nova',
        slug: 'existente',
        ownerId: 1,
        email: 'a@b.com',
        phone: '1',
      );

      expect((r as Failure).error, isA<TenantsConflito>());
      verifyNever(() => client.listTenants(any()));
      await controller.close();
    });

    test('desativar tenant com sucesso recarrega a lista', () async {
      listaResponde([_tenantProto()]);
      when(
        () => client.setTenantActive(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SetTenantActiveResponse()));
      final controller = _controller(client);

      final r = await controller.setTenantActive(id: 't1', active: false);

      expect(r, isA<Success>());
      verify(() => client.listTenants(any())).called(1);
      await controller.close();
    });

    test('gerar código de acesso não recarrega a lista', () async {
      // Gerar código não altera a listagem — recarregar seria I/O desperdiçado.
      listaResponde([_tenantProto()]);
      when(() => client.generateAccessCode(any())).thenAnswer(
        (_) => respostaGrpc(proto.GenerateAccessCodeResponse(accessCode: 'X')),
      );
      final controller = _controller(client);

      final r = await controller.generateAccessCode('t1');

      expect((r as Success).value, 'X');
      verifyNever(() => client.listTenants(any()));
      await controller.close();
    });
  });
}
