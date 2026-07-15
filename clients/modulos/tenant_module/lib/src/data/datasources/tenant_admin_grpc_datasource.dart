import 'package:api_client/api_client.dart' as proto;
import 'package:domain_models/domain_models.dart';

import '../../domain/model/tenant_config.dart';
import '../../domain/model/tenant_invite.dart';
import '../../domain/model/tenant_user.dart';
import '../grpc_error_mapper.dart';

/// Fronteira RemoteOnly do painel do tenant — telas/usecases dependem só
/// desta interface (nunca do stub gRPC direto), permitindo trocar o transporte
/// sem tocar em UI (Ports & Adapters).
abstract interface class TenantAdminDataSource {
  Future<TenantInviteCreated> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  });

  Future<List<TenantInvite>> listInvites();

  Future<void> revokeInvite(String inviteId);

  Future<AcceptedTenantUser> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  });

  Future<List<TenantUser>> listTenantUsers();

  Future<void> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  });

  Future<TenantConfig> getMyTenantConfig();

  Future<void> updateMyTenantConfig(TenantConfig config);
}

final class TenantAdminGrpcDatasourceImpl implements TenantAdminDataSource {
  final proto.AdminServiceClient _client;

  const TenantAdminGrpcDatasourceImpl({required this._client});

  @override
  Future<TenantInviteCreated> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) async {
    try {
      final resp = await _client.createInvite(proto.CreateInviteRequest(
        email: email,
        name: name,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      ));
      final i = resp.invite;
      return TenantInviteCreated(
        id: i.id,
        tenantId: i.tenantId,
        email: i.email,
        name: i.name,
        role: i.role,
        token: i.token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(i.expiresAt.toInt()),
        used: i.used,
        createdAt: DateTime.fromMillisecondsSinceEpoch(i.createdAt.toInt()),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<TenantInvite>> listInvites() async {
    try {
      final resp = await _client.listInvites(proto.ListInvitesRequest());
      return resp.invites
          .map((i) => TenantInvite(
                id: i.id,
                email: i.email,
                name: i.name,
                role: i.role,
                modulePermissions: i.modulePermissions,
                flowPermissions: i.flowPermissions,
                expiresAt: DateTime.fromMillisecondsSinceEpoch(i.expiresAt.toInt()),
                used: i.used,
                revoked: i.revoked,
                createdAt: DateTime.fromMillisecondsSinceEpoch(i.createdAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    try {
      await _client.revokeInvite(proto.RevokeInviteRequest(inviteId: inviteId));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<AcceptedTenantUser> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final resp = await _client.acceptInvite(proto.AcceptInviteRequest(
        token: token,
        username: username,
        email: email,
        password: password,
      ));
      final u = resp.tenantUser;
      return AcceptedTenantUser(
        id: u.id,
        userId: u.userId,
        tenantId: u.tenantId,
        role: u.role,
        modulePermissions: u.modulePermissions,
        flowPermissions: u.flowPermissions,
        isActive: u.isActive,
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorValidation());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<TenantUser>> listTenantUsers() async {
    try {
      final resp = await _client.listTenantUsers(proto.ListTenantUsersRequest());
      return resp.users
          .map((u) => TenantUser(
                id: u.id,
                userId: u.userId,
                role: u.role,
                modulePermissions: u.modulePermissions,
                flowPermissions: u.flowPermissions,
                isActive: u.isActive,
                createdAt: DateTime.fromMillisecondsSinceEpoch(u.createdAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) async {
    try {
      await _client.updateTenantUser(proto.UpdateTenantUserRequest(
        userId: userId,
        setRole: role != null,
        role: role ?? '',
        setModulePermissions: modulePermissions != null,
        modulePermissions: modulePermissions ?? const [],
        setFlowPermissions: flowPermissions != null,
        flowPermissions: flowPermissions ?? const [],
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<TenantConfig> getMyTenantConfig() async {
    try {
      final resp = await _client.getMyTenantConfig(proto.GetMyTenantConfigRequest());
      final apiKeys = <String, String>{};
      for (final entry in resp.apiKeys) {
        apiKeys[entry.key] = entry.value;
      }
      return TenantConfig(
        dadosEmpresa: resp.dadosEmpresa,
        personaBot: resp.personaBot,
        botAgentName: resp.botAgentName,
        msgFallback: resp.msgFallback,
        msgSemInfo: resp.msgSemInfo,
        msgTransferencia: resp.msgTransferencia,
        llmClass: resp.llmClass,
        model: resp.model,
        llmTemperature: resp.llmTemperature,
        transcriptionProvider: resp.transcriptionProvider,
        transcriptionModel: resp.transcriptionModel,
        visionProvider: resp.visionProvider,
        visionModel: resp.visionModel,
        embeddingsClass: resp.embeddingsClass,
        embeddingsModel: resp.embeddingsModel,
        chunkSize: resp.chunkSize,
        chunkOverlap: resp.chunkOverlap,
        similarityThreshold: resp.similarityThreshold,
        vectorDistanceThreshold: resp.vectorDistanceThreshold,
        apiKeys: apiKeys,
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> updateMyTenantConfig(TenantConfig config) async {
    try {
      final apiKeysProto = <proto.ApiKeyEntry>[];
      config.apiKeys.forEach((k, v) {
        apiKeysProto.add(proto.ApiKeyEntry(key: k, value: v));
      });
      await _client.updateMyTenantConfig(proto.UpdateMyTenantConfigRequest(
        dadosEmpresa: config.dadosEmpresa,
        personaBot: config.personaBot,
        botAgentName: config.botAgentName,
        msgFallback: config.msgFallback,
        msgSemInfo: config.msgSemInfo,
        msgTransferencia: config.msgTransferencia,
        llmClass: config.llmClass,
        model: config.model,
        llmTemperature: config.llmTemperature,
        transcriptionProvider: config.transcriptionProvider,
        transcriptionModel: config.transcriptionModel,
        visionProvider: config.visionProvider,
        visionModel: config.visionModel,
        embeddingsClass: config.embeddingsClass,
        embeddingsModel: config.embeddingsModel,
        chunkSize: config.chunkSize,
        chunkOverlap: config.chunkOverlap,
        similarityThreshold: config.similarityThreshold,
        vectorDistanceThreshold: config.vectorDistanceThreshold,
        apiKeys: apiKeysProto,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }
}
