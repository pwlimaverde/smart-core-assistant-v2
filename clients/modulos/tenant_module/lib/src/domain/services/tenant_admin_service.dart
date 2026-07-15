import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';
import '../model/tenant_invite.dart';
import '../model/tenant_user.dart';

/// Serviço de domínio do painel do tenant (N3): convites, gestão de usuários
/// e configuração do próprio tenant. O `tenant_id` nunca é um parâmetro aqui —
/// o backend sempre o resolve a partir da sessão autenticada.
abstract interface class TenantAdminService {
  // --- N3.1: Convites ---
  Future<ReturnSuccessOrError<TenantInviteCreated>> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  });

  Future<ReturnSuccessOrError<List<TenantInvite>>> listInvites();

  Future<ReturnSuccessOrError<Unit>> revokeInvite(String inviteId);

  /// Rota pública (sem sessão) — o convidado ainda não tem conta.
  Future<ReturnSuccessOrError<AcceptedTenantUser>> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  });

  // --- N3.2: Gestão de usuários / flow_permissions ---
  Future<ReturnSuccessOrError<List<TenantUser>>> listTenantUsers();

  /// Campos `null` preservam o valor atual no backend (ver flags `set_*` do
  /// contrato). Só envie o que a UI realmente alterou.
  Future<ReturnSuccessOrError<Unit>> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  });

  // --- N3.3: Configuração do próprio tenant ---
  Future<ReturnSuccessOrError<TenantConfig>> getMyTenantConfig();

  Future<ReturnSuccessOrError<Unit>> updateMyTenantConfig(TenantConfig config);
}
