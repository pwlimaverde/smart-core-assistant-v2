import 'package:admin_module/src/features/config/domain/model/core_setting.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/delete_core_setting_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_core_settings_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/upsert_core_setting_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/core_settings_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O CoreSettingsController lista settings via execute() e, apos upsert/delete
// bem-sucedidos, recarrega a lista. Em caso de erro na escrita, devolve o
// ReturnSuccessOrError sem recarregar.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  CoreSettingsController build() => CoreSettingsController(
        listUsecase: ListCoreSettingsUsecase(service: service),
        upsertUsecase: UpsertCoreSettingUsecase(service: service),
        deleteUsecase: DeleteCoreSettingUsecase(service: service),
      );

  void stubListOk() => when(() => service.listCoreSettings())
      .thenAnswer((_) async => SuccessReturn(success: [coreSettingFixture()]));

  group('fetchSettings', () {
    blocTest<CoreSettingsController, ViewState<List<CoreSetting>>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        stubListOk();
        return build();
      },
      act: (c) => c.fetchSettings(),
      expect: () => [
        isA<LoadingState<List<CoreSetting>>>(),
        isA<SuccessState<List<CoreSetting>>>()
            .having((s) => s.data, 'lista', hasLength(1)),
      ],
    );

    blocTest<CoreSettingsController, ViewState<List<CoreSetting>>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.listCoreSettings())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchSettings(),
      expect: () => [
        isA<LoadingState<List<CoreSetting>>>(),
        isA<ErrorState<List<CoreSetting>>>(),
      ],
    );
  });

  group('upsertSetting', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.upsertCoreSetting(
            key: any(named: 'key'),
            value: any(named: 'value'),
            encrypted: any(named: 'encrypted'),
            description: any(named: 'description'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.upsertSetting(
          key: 'k', value: 'v', encrypted: false, description: 'd');

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listCoreSettings()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.upsertCoreSetting(
            key: any(named: 'key'),
            value: any(named: 'value'),
            encrypted: any(named: 'encrypted'),
            description: any(named: 'description'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorValidation()));
      final controller = build();

      await controller.upsertSetting(
          key: 'k', value: 'v', encrypted: false, description: 'd');

      verifyNever(() => service.listCoreSettings());
      await controller.close();
    });
  });

  group('deleteSetting', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.deleteCoreSetting(any()))
          .thenAnswer((_) async => const SuccessReturn(success: unit));
      stubListOk();
      final controller = build();

      final res = await controller.deleteSetting('k');

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listCoreSettings()).called(1);
      await controller.close();
    });

    test('erro: nao dispara refetch', () async {
      when(() => service.deleteCoreSetting(any()))
          .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
      final controller = build();

      await controller.deleteSetting('k');

      verifyNever(() => service.listCoreSettings());
      await controller.close();
    });
  });
}
