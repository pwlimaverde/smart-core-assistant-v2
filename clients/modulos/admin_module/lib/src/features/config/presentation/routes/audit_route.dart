import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/query_audit_log_usecase.dart';
import '../../domain/usecases/export_tenants_csv_usecase.dart';
import '../../domain/usecases/list_tenants_usecase.dart';
import '../controllers/audit_controller.dart';
import '../pages/audit_page.dart';

final class AuditRoute extends GetItModule {
  @override
  String get path => '/admin/audit';

  @override
  Widget get page => const AuditPage();

  @override
  void binds(Injector i) {
    i.controller<AuditController>(
      () => AuditController(
        queryUsecase: inject<QueryAuditLogUsecase>(),
        exportUsecase: inject<ExportTenantsCsvUsecase>(),
        listTenantsUsecase: inject<ListTenantsUsecase>(),
      ),
    );
  }
}
