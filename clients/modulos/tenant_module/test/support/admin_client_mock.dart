import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:mocktail/mocktail.dart';

/// Mock do stub gRPC do admin — o único ponto trocado nos testes do módulo.
///
/// Montar a cadeia real (datasource → repositório → usecase → controller) sobre
/// ele faz cada teste cobrir também a conversão protobuf e o `mapError`, em vez
/// de só a orquestração de estado.
class MockAdminClient extends Mock implements proto.AdminServiceClient {}

Int64 ms(DateTime d) => Int64(d.millisecondsSinceEpoch);

/// Registra os fallbacks de todos os requests usados pelo módulo do tenant.
void registrarFallbacksDoTenant() {
  registerFallbackValue(proto.CreateInviteRequest());
  registerFallbackValue(proto.ListInvitesRequest());
  registerFallbackValue(proto.RevokeInviteRequest());
  registerFallbackValue(proto.ReenviarConviteRequest());
  registerFallbackValue(proto.AcceptInviteRequest());
  registerFallbackValue(proto.ListTenantUsersRequest());
  registerFallbackValue(proto.UpdateTenantUserRequest());
  registerFallbackValue(proto.GetMyTenantConfigRequest());
  registerFallbackValue(proto.UpdateMyTenantConfigRequest());
}

/// Convite recém-criado (resposta de `CreateInvite`, com token).
proto.TenantInviteCreated conviteCriadoProto({
  String id = 'inv-1',
  String email = 'convidado@exemplo.com',
  String token = 'token-secreto',
  DateTime? expiresAt,
}) => proto.TenantInviteCreated(
  id: id,
  tenantId: 'tenant-1',
  email: email,
  name: 'Convidado',
  role: 'atendente',
  token: token,
  used: false,
  createdAt: ms(DateTime(2026, 1, 1)),
  expiresAt: ms(expiresAt ?? DateTime(2026, 2, 1)),
);

/// Item da listagem de convites.
///
/// [expiresAt] é relativo ao relógio de propósito: "pendente" é um convite que
/// ainda não venceu, e uma data fixa no helper faria o teste passar até a data
/// chegar e falhar sozinho depois.
proto.TenantInviteItem conviteItemProto({
  String id = 'inv-1',
  String email = 'convidado@exemplo.com',
  bool used = false,
  bool revoked = false,
  DateTime? createdAt,
  DateTime? expiresAt,
  List<String> modulePermissions = const [],
  List<int> flowPermissions = const [],
}) => proto.TenantInviteItem(
  id: id,
  email: email,
  name: 'Convidado',
  role: 'atendente',
  used: used,
  revoked: revoked,
  modulePermissions: modulePermissions,
  flowPermissions: flowPermissions,
  createdAt: ms(createdAt ?? DateTime(2026, 1, 1)),
  expiresAt: ms(expiresAt ?? DateTime.now().add(const Duration(days: 30))),
);

/// Item da listagem de usuários do tenant.
proto.TenantUserItem usuarioItemProto({
  int id = 1,
  int userId = 10,
  String role = 'atendente',
  bool isActive = true,
  DateTime? createdAt,
  List<String> modulePermissions = const [],
  List<int> flowPermissions = const [],
}) => proto.TenantUserItem(
  id: id,
  userId: userId,
  role: role,
  isActive: isActive,
  modulePermissions: modulePermissions,
  flowPermissions: flowPermissions,
  createdAt: ms(createdAt ?? DateTime(2026, 1, 1)),
);
