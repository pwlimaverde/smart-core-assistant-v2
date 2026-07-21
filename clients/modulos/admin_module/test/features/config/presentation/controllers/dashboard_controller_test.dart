import 'package:admin_module/src/features/config/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_dashboard_summary_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/dashboard_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O DashboardController estende BaseController (Cubit) e delega ao usecase via
// execute(), que emite [Loading, Success] ou [Loading, Error]. O AdminService e
// mockado; os usecases reais sao construidos sobre ele.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  DashboardController build() => DashboardController(
        getSummaryUsecase: GetDashboardSummaryUsecase(service: service),
      );

  group('DashboardController.fetchSummary', () {
    blocTest<DashboardController, ViewState<DashboardSummary>>(
      'sucesso: emite [Loading, Success] com o resumo',
      build: () {
        when(() => service.getDashboardSummary())
            .thenAnswer((_) async => SuccessReturn(success: dashboardSummaryFixture()));
        return build();
      },
      act: (c) => c.fetchSummary(),
      expect: () => [
        isA<LoadingState<DashboardSummary>>(),
        isA<SuccessState<DashboardSummary>>()
            .having((s) => s.data.totalTenants, 'totalTenants', 10),
      ],
    );

    blocTest<DashboardController, ViewState<DashboardSummary>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.getDashboardSummary())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchSummary(),
      expect: () => [
        isA<LoadingState<DashboardSummary>>(),
        isA<ErrorState<DashboardSummary>>(),
      ],
    );
  });
}
