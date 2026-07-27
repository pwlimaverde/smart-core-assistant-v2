import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/audit_controller.dart';
import '../pages/audit_page.dart';
import '../../domain/usecases/audit_usecases.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';

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
