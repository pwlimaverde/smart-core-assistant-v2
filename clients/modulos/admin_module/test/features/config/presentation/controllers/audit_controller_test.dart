import 'package:admin_module/src/features/config/domain/model/audit_log_entry.dart';
import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/export_tenants_csv_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_tenants_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/query_audit_log_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/audit_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O AuditController consulta o log via execute() e expoe exportTenantsCsv e
// getTenants como passthrough (usados pela UI para exportar/filtrar).
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  AuditController build() => AuditController(
        queryUsecase: QueryAuditLogUsecase(service: service),
        exportUsecase: ExportTenantsCsvUsecase(service: service),
        listTenantsUsecase: ListTenantsUsecase(service: service),
      );

  group('fetchAuditLogs', () {
    blocTest<AuditController, ViewState<List<AuditLogEntry>>>(
      'sucesso: emite [Loading, Success]',
      build: () {
        when(() => service.queryAuditLog(
              tenantId: any(named: 'tenantId'),
              eventType: any(named: 'eventType'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => SuccessReturn(success: [auditLogEntryFixture()]));
        return build();
      },
      act: (c) => c.fetchAuditLogs(tenantId: 't', eventType: 'x'),
      expect: () => [
        isA<LoadingState<List<AuditLogEntry>>>(),
        isA<SuccessState<List<AuditLogEntry>>>()
            .having((s) => s.data, 'entries', hasLength(1)),
      ],
    );

    blocTest<AuditController, ViewState<List<AuditLogEntry>>>(
      'erro: emite [Loading, Error]',
      build: () {
        when(() => service.queryAuditLog(
              tenantId: any(named: 'tenantId'),
              eventType: any(named: 'eventType'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchAuditLogs(),
      expect: () => [
        isA<LoadingState<List<AuditLogEntry>>>(),
        isA<ErrorState<List<AuditLogEntry>>>(),
      ],
    );
  });

  group('exportTenantsCsv', () {
    test('repassa os bytes do CSV', () async {
      when(() => service.exportTenantsCsv())
          .thenAnswer((_) async => const SuccessReturn(success: [1, 2, 3]));
      final controller = build();

      final res = await controller.exportTenantsCsv();

      expect((res as SuccessReturn).result, [1, 2, 3]);
      await controller.close();
    });
  });

  group('getTenants', () {
    test('repassa a lista de tenants', () async {
      when(() => service.listTenants())
          .thenAnswer((_) async => SuccessReturn(success: [tenantFixture()]));
      final controller = build();

      final res = await controller.getTenants();

      expect(res, isA<SuccessReturn<List<Tenant>>>());
      await controller.close();
    });
  });
}
