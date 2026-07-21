import 'package:admin_module/src/features/config/domain/model/evolution_connection_result.dart';
import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_tenants_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/test_evolution_connection_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/evolution_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O EvolutionController lista tenants via execute() e expoe testConnection, que
// apenas repassa o resultado do usecase (sem alterar o estado do Cubit).
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  EvolutionController build() => EvolutionController(
        listTenantsUsecase: ListTenantsUsecase(service: service),
        testConnectionUsecase: TestEvolutionConnectionUsecase(service: service),
      );

  group('fetchTenants', () {
    blocTest<EvolutionController, ViewState<List<Tenant>>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        when(() => service.listTenants())
            .thenAnswer((_) async => SuccessReturn(success: [tenantFixture()]));
        return build();
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<SuccessState<List<Tenant>>>(),
      ],
    );

    blocTest<EvolutionController, ViewState<List<Tenant>>>(
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

  group('testConnection', () {
    test('sucesso: repassa o EvolutionConnectionResult', () async {
      when(() => service.testEvolutionConnection(any())).thenAnswer(
          (_) async => SuccessReturn(success: evolutionResultFixture()));
      final controller = build();

      final res = await controller.testConnection('t');

      expect(res, isA<SuccessReturn<EvolutionConnectionResult>>());
      expect((res as SuccessReturn).result.status, 'connected');
      await controller.close();
    });

    test('erro: repassa o ErrorReturn', () async {
      when(() => service.testEvolutionConnection(any()))
          .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      final res = await controller.testConnection('t');

      expect((res as ErrorReturn).result, isA<ErrorNetwork>());
      await controller.close();
    });
  });
}
