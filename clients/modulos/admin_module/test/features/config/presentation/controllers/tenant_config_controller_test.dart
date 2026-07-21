import 'package:admin_module/src/features/config/domain/model/tenant_config.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_tenant_config_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_tenant_config_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/tenant_config_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O TenantConfigController carrega a config via execute() e, apos um update
// bem-sucedido, recarrega a config do tenant. Em caso de erro na escrita, devolve
// o ReturnSuccessOrError sem recarregar.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUpAll(() => registerFallbackValue(tenantConfigFixture()));

  setUp(() => service = _MockAdminService());

  TenantConfigController build() => TenantConfigController(
        getUsecase: GetTenantConfigUsecase(service: service),
        updateUsecase: UpdateTenantConfigUsecase(service: service),
      );

  void stubGetOk() => when(() => service.getTenantConfig(any()))
      .thenAnswer((_) async => SuccessReturn(success: tenantConfigFixture()));

  group('fetchConfig', () {
    blocTest<TenantConfigController, ViewState<TenantConfig>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        stubGetOk();
        return build();
      },
      act: (c) => c.fetchConfig('t'),
      expect: () => [
        isA<LoadingState<TenantConfig>>(),
        isA<SuccessState<TenantConfig>>()
            .having((s) => s.data.model, 'model', 'gpt-4o'),
      ],
    );

    blocTest<TenantConfigController, ViewState<TenantConfig>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.getTenantConfig(any()))
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchConfig('t'),
      expect: () => [
        isA<LoadingState<TenantConfig>>(),
        isA<ErrorState<TenantConfig>>(),
      ],
    );
  });

  group('updateConfig', () {
    test('sucesso: dispara refetch da config', () async {
      when(() => service.updateTenantConfig(
            tenantId: any(named: 'tenantId'),
            config: any(named: 'config'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubGetOk();
      final controller = build();

      final res = await controller.updateConfig(
          tenantId: 't', config: tenantConfigFixture());

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.getTenantConfig('t')).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.updateTenantConfig(
            tenantId: any(named: 'tenantId'),
            config: any(named: 'config'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorValidation()));
      final controller = build();

      final res = await controller.updateConfig(
          tenantId: 't', config: tenantConfigFixture());

      expect((res as ErrorReturn).result, isA<ErrorValidation>());
      verifyNever(() => service.getTenantConfig(any()));
      await controller.close();
    });
  });
}
