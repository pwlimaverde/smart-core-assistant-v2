import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:mocktail/mocktail.dart';

/// Mock do stub gRPC do admin — o único ponto trocado nos testes do módulo.
///
/// Os testes montam a cadeia real (`Datasource → Repository → Usecase`) sobre
/// ele, então exercitam também a conversão protobuf e o `mapError`, não apenas a
/// orquestração de estado.
class MockAdminClient extends Mock implements proto.AdminServiceClient {}

Int64 ms(DateTime d) => Int64(d.millisecondsSinceEpoch);

/// Fallbacks de todos os requests usados pelas oito features do admin.
void registrarFallbacksDoAdmin() {
  registerFallbackValue(proto.ListCoreSettingsRequest());
  registerFallbackValue(proto.UpsertCoreSettingRequest());
  registerFallbackValue(proto.DeleteCoreSettingRequest());
  registerFallbackValue(proto.GetTenantConfigRequest());
  registerFallbackValue(proto.UpdateTenantConfigRequest());
  registerFallbackValue(proto.ListTenantsRequest());
  registerFallbackValue(proto.GetTenantRequest());
  registerFallbackValue(proto.CreateTenantRequest());
  registerFallbackValue(proto.UpdateTenantRequest());
  registerFallbackValue(proto.SetTenantActiveRequest());
  registerFallbackValue(proto.GenerateAccessCodeRequest());
  registerFallbackValue(proto.ExportTenantsCsvRequest());
  registerFallbackValue(proto.ListPlansRequest());
  registerFallbackValue(proto.CreatePlanRequest());
  registerFallbackValue(proto.UpdatePlanRequest());
  registerFallbackValue(proto.ListSubscriptionsRequest());
  registerFallbackValue(proto.RegisterPaymentRequest());
  registerFallbackValue(proto.ListPaymentsRequest());
  // Vouchers de ativação (migration 0027).
  registerFallbackValue(proto.ListVouchersRequest());
  registerFallbackValue(proto.CreateVoucherRequest());
  registerFallbackValue(proto.RevokeVoucherRequest());
  registerFallbackValue(proto.ListVoucherRedemptionsRequest());
  registerFallbackValue(proto.ListFeatureFlagsRequest());
  registerFallbackValue(proto.SetFeatureFlagRequest());
  registerFallbackValue(proto.SetFeatureFlagOverrideRequest());
  registerFallbackValue(proto.QueryAuditLogRequest());
  registerFallbackValue(proto.GetServiceHealthRequest());
  registerFallbackValue(proto.GetDashboardSummaryRequest());
  registerFallbackValue(proto.TestEvolutionConnectionRequest());
}
