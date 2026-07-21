import 'package:admin_module/src/features/config/domain/model/feature_flag.dart';
import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_feature_flags_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_tenants_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_feature_flag_override_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_feature_flag_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/feature_flags_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O FeatureFlagsController lista flags via execute(); set/setOverride recarregam
// a lista em caso de sucesso. getTenants apenas repassa o resultado (usado para
// popular o seletor de tenant dos overrides).
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  FeatureFlagsController build() => FeatureFlagsController(
        listUsecase: ListFeatureFlagsUsecase(service: service),
        setUsecase: SetFeatureFlagUsecase(service: service),
        setOverrideUsecase: SetFeatureFlagOverrideUsecase(service: service),
        listTenantsUsecase: ListTenantsUsecase(service: service),
      );

  void stubListOk() => when(() => service.listFeatureFlags())
      .thenAnswer((_) async => SuccessReturn(success: [featureFlagFixture()]));

  group('fetchFeatureFlags', () {
    blocTest<FeatureFlagsController, ViewState<List<FeatureFlag>>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        stubListOk();
        return build();
      },
      act: (c) => c.fetchFeatureFlags(),
      expect: () => [
        isA<LoadingState<List<FeatureFlag>>>(),
        isA<SuccessState<List<FeatureFlag>>>()
            .having((s) => s.data, 'flags', hasLength(1)),
      ],
    );

    blocTest<FeatureFlagsController, ViewState<List<FeatureFlag>>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.listFeatureFlags())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchFeatureFlags(),
      expect: () => [
        isA<LoadingState<List<FeatureFlag>>>(),
        isA<ErrorState<List<FeatureFlag>>>(),
      ],
    );
  });

  group('setFeatureFlag', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.setFeatureFlag(
            key: any(named: 'key'),
            enabledGlobally: any(named: 'enabledGlobally'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.setFeatureFlag(key: 'k', enabledGlobally: true);

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listFeatureFlags()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.setFeatureFlag(
            key: any(named: 'key'),
            enabledGlobally: any(named: 'enabledGlobally'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      await controller.setFeatureFlag(key: 'k', enabledGlobally: true);

      verifyNever(() => service.listFeatureFlags());
      await controller.close();
    });
  });

  group('setFeatureFlagOverride', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.setFeatureFlagOverride(
            key: any(named: 'key'),
            tenantId: any(named: 'tenantId'),
            enabled: any(named: 'enabled'),
            removeOverride: any(named: 'removeOverride'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.setFeatureFlagOverride(
          key: 'k', tenantId: 't', enabled: true, removeOverride: false);

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listFeatureFlags()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.setFeatureFlagOverride(
            key: any(named: 'key'),
            tenantId: any(named: 'tenantId'),
            enabled: any(named: 'enabled'),
            removeOverride: any(named: 'removeOverride'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      await controller.setFeatureFlagOverride(
          key: 'k', tenantId: 't', enabled: true, removeOverride: false);

      verifyNever(() => service.listFeatureFlags());
      await controller.close();
    });
  });

  group('getTenants', () {
    test('repassa a lista de tenants do usecase', () async {
      when(() => service.listTenants())
          .thenAnswer((_) async => SuccessReturn(success: [tenantFixture()]));
      final controller = build();

      final res = await controller.getTenants();

      expect(res, isA<SuccessReturn<List<Tenant>>>());
      expect((res as SuccessReturn).result, hasLength(1));
      await controller.close();
    });
  });
}
