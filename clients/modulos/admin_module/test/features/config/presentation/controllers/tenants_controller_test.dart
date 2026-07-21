import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/create_tenant_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/generate_access_code_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_tenants_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_tenant_active_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_tenant_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/tenants_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O TenantsController lista tenants via execute() e expoe acoes de escrita
// (create/update/setActive) que, em caso de sucesso, disparam um refetch da lista.
// As acoes devolvem o ReturnSuccessOrError para a UI decidir feedback.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  TenantsController build() => TenantsController(
        listUsecase: ListTenantsUsecase(service: service),
        createUsecase: CreateTenantUsecase(service: service),
        updateUsecase: UpdateTenantUsecase(service: service),
        setActiveUsecase: SetTenantActiveUsecase(service: service),
        generateAccessCodeUsecase: GenerateAccessCodeUsecase(service: service),
      );

  void stubListOk() => when(() => service.listTenants())
      .thenAnswer((_) async => SuccessReturn(success: [tenantFixture()]));

  group('fetchTenants', () {
    blocTest<TenantsController, ViewState<List<Tenant>>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        stubListOk();
        return build();
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<SuccessState<List<Tenant>>>()
            .having((s) => s.data, 'lista', hasLength(1)),
      ],
    );

    blocTest<TenantsController, ViewState<List<Tenant>>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.listTenants())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<ErrorState<List<Tenant>>>(),
      ],
    );
  });

  group('createTenant', () {
    test('sucesso: dispara refetch e devolve SuccessReturn', () async {
      when(() => service.createTenant(
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => SuccessReturn(success: tenantFixture()));
      stubListOk();
      final controller = build();

      final res = await controller.createTenant(
          name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');

      expect(res, isA<SuccessReturn<Tenant>>());
      verify(() => service.listTenants()).called(1);
      expect(controller.state, isA<SuccessState<List<Tenant>>>());
      await controller.close();
    });

    test('erro: devolve ErrorReturn e NAO dispara refetch', () async {
      when(() => service.createTenant(
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorValidation()));
      final controller = build();

      final res = await controller.createTenant(
          name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');

      expect((res as ErrorReturn).result, isA<ErrorValidation>());
      verifyNever(() => service.listTenants());
      await controller.close();
    });
  });

  group('updateTenant', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.updateTenant(
            id: any(named: 'id'),
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.updateTenant(
          id: 'i', name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listTenants()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.updateTenant(
            id: any(named: 'id'),
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      await controller.updateTenant(
          id: 'i', name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');

      verifyNever(() => service.listTenants());
      await controller.close();
    });
  });

  group('setTenantActive', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.setTenantActive(
            id: any(named: 'id'),
            active: any(named: 'active'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.setTenantActive(id: 'i', active: false);

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listTenants()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.setTenantActive(
            id: any(named: 'id'),
            active: any(named: 'active'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      await controller.setTenantActive(id: 'i', active: false);

      verifyNever(() => service.listTenants());
      await controller.close();
    });
  });

  group('generateAccessCode', () {
    test('repassa o resultado do usecase sem refetch', () async {
      when(() => service.generateAccessCode(any()))
          .thenAnswer((_) async => const SuccessReturn(success: 'CODE'));
      final controller = build();

      final res = await controller.generateAccessCode('i');

      expect((res as SuccessReturn).result, 'CODE');
      verifyNever(() => service.listTenants());
      await controller.close();
    });
  });
}
