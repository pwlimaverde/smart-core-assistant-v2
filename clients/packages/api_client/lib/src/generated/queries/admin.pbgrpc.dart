// This is a generated file - do not edit.
//
// Generated from queries/admin.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'admin.pb.dart' as $0;

export 'admin.pb.dart';

/// --- Serviço Admin ---
@$pb.GrpcServiceName('smartcore.contracts.queries.AdminService')
class AdminServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  AdminServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.ListCoreSettingsResponse> listCoreSettings(
    $0.ListCoreSettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listCoreSettings, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpsertCoreSettingResponse> upsertCoreSetting(
    $0.UpsertCoreSettingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$upsertCoreSetting, request, options: options);
  }

  $grpc.ResponseFuture<$0.DeleteCoreSettingResponse> deleteCoreSetting(
    $0.DeleteCoreSettingRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteCoreSetting, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantConfigResponse> getTenantConfig(
    $0.GetTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTenantConfig, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantConfigResponse> updateTenantConfig(
    $0.UpdateTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenantConfig, request, options: options);
  }

  /// Fase 2: Tenants
  $grpc.ResponseFuture<$0.ListTenantsResponse> listTenants(
    $0.ListTenantsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listTenants, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantResponse> getTenant(
    $0.GetTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateTenantResponse> createTenant(
    $0.CreateTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantResponse> updateTenant(
    $0.UpdateTenantRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenant, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetTenantActiveResponse> setTenantActive(
    $0.SetTenantActiveRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setTenantActive, request, options: options);
  }

  $grpc.ResponseFuture<$0.GenerateAccessCodeResponse> generateAccessCode(
    $0.GenerateAccessCodeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$generateAccessCode, request, options: options);
  }

  /// Fase 2: Billing
  $grpc.ResponseFuture<$0.ListPlansResponse> listPlans(
    $0.ListPlansRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPlans, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreatePlanResponse> createPlan(
    $0.CreatePlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createPlan, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdatePlanResponse> updatePlan(
    $0.UpdatePlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updatePlan, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListSubscriptionsResponse> listSubscriptions(
    $0.ListSubscriptionsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listSubscriptions, request, options: options);
  }

  $grpc.ResponseFuture<$0.RegisterPaymentResponse> registerPayment(
    $0.RegisterPaymentRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$registerPayment, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListPaymentsResponse> listPayments(
    $0.ListPaymentsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPayments, request, options: options);
  }

  /// Vouchers de ativação
  $grpc.ResponseFuture<$0.ListVouchersResponse> listVouchers(
    $0.ListVouchersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listVouchers, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateVoucherResponse> createVoucher(
    $0.CreateVoucherRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createVoucher, request, options: options);
  }

  $grpc.ResponseFuture<$0.RevokeVoucherResponse> revokeVoucher(
    $0.RevokeVoucherRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeVoucher, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListVoucherRedemptionsResponse>
      listVoucherRedemptions(
    $0.ListVoucherRedemptionsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listVoucherRedemptions, request,
        options: options);
  }

  /// Fase 3: Evolution Connection
  $grpc.ResponseFuture<$0.TestEvolutionConnectionResponse>
      testEvolutionConnection(
    $0.TestEvolutionConnectionRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$testEvolutionConnection, request,
        options: options);
  }

  /// Fase 4: Feature Flags
  $grpc.ResponseFuture<$0.ListFeatureFlagsResponse> listFeatureFlags(
    $0.ListFeatureFlagsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listFeatureFlags, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetFeatureFlagResponse> setFeatureFlag(
    $0.SetFeatureFlagRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setFeatureFlag, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetFeatureFlagOverrideResponse>
      setFeatureFlagOverride(
    $0.SetFeatureFlagOverrideRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setFeatureFlagOverride, request,
        options: options);
  }

  /// Fase 5: Auditoria & Saúde
  $grpc.ResponseFuture<$0.QueryAuditLogResponse> queryAuditLog(
    $0.QueryAuditLogRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$queryAuditLog, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetServiceHealthResponse> getServiceHealth(
    $0.GetServiceHealthRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getServiceHealth, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetDashboardSummaryResponse> getDashboardSummary(
    $0.GetDashboardSummaryRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getDashboardSummary, request, options: options);
  }

  $grpc.ResponseStream<$0.ExportTenantsCsvResponse> exportTenantsCsv(
    $0.ExportTenantsCsvRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$exportTenantsCsv, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Realtime
  $grpc.ResponseStream<$0.AtendimentoEvent> streamAtendimentos(
    $0.StreamAtendimentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamAtendimentos, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Fase 6: Operacional (fila/Kanban/chat — WS-6). RBAC fino por fluxo (flow_permissions)
  /// já é aplicado no data_postgres (WS-5a); estas rotas exigem só autenticação, não superuser.
  $grpc.ResponseFuture<$0.ListAtendimentosResponse> listAtendimentos(
    $0.ListAtendimentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listAtendimentos, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetThreadResponse> getThread(
    $0.GetThreadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getThread, request, options: options);
  }

  $grpc.ResponseFuture<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa(
    $0.MoveAtendimentoEtapaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$moveAtendimentoEtapa, request, options: options);
  }

  $grpc.ResponseFuture<$0.SendOutboundMessageResponse> sendOutboundMessage(
    $0.SendOutboundMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sendOutboundMessage, request, options: options);
  }

  /// Fase N3: Painel do Tenant. Exigem só autenticação (não superuser); o RBAC fino
  /// `tenant:admin` é aplicado no data_postgres. AcceptInvite é rota pública (sem sessão).
  $grpc.ResponseFuture<$0.CreateInviteResponse> createInvite(
    $0.CreateInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.AcceptInviteResponse> acceptInvite(
    $0.AcceptInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$acceptInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListInvitesResponse> listInvites(
    $0.ListInvitesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listInvites, request, options: options);
  }

  $grpc.ResponseFuture<$0.RevokeInviteResponse> revokeInvite(
    $0.RevokeInviteRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$revokeInvite, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListTenantUsersResponse> listTenantUsers(
    $0.ListTenantUsersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listTenantUsers, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantUserResponse> updateTenantUser(
    $0.UpdateTenantUserRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateTenantUser, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetTenantConfigResponse> getMyTenantConfig(
    $0.GetMyTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyTenantConfig, request, options: options);
  }

  $grpc.ResponseFuture<$0.UpdateTenantConfigResponse> updateMyTenantConfig(
    $0.UpdateMyTenantConfigRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyTenantConfig, request, options: options);
  }

  /// Configuração inicial guiada (passos 5 a 8)
  $grpc.ResponseFuture<$0.CreateMyWhatsappInstanceResponse>
      createMyWhatsappInstance(
    $0.CreateMyWhatsappInstanceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyWhatsappInstance, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus(
    $0.GetMyWhatsappInstanceStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyWhatsappInstanceStatus, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.CreateMyDepartamentoResponse> createMyDepartamento(
    $0.CreateMyDepartamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyDepartamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetMyBotPersonaResponse> setMyBotPersona(
    $0.SetMyBotPersonaRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setMyBotPersona, request, options: options);
  }

  $grpc.ResponseFuture<$0.SetOnboardingProgressResponse> setOnboardingProgress(
    $0.SetOnboardingProgressRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setOnboardingProgress, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetMyOnboardingProgressResponse>
      getMyOnboardingProgress(
    $0.GetMyOnboardingProgressRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyOnboardingProgress, request,
        options: options);
  }

  /// Treinamento da IA (o tenant treina o próprio assistente)
  $grpc.ResponseFuture<$0.MyTreinamentoResponse> createMyTreinamento(
    $0.CreateMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMyTreinamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyTreinamentosResponse> listMyTreinamentos(
    $0.ListMyTreinamentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyTreinamentos, request, options: options);
  }

  $grpc.ResponseFuture<$0.MyTreinamentoResponse> getMyTreinamento(
    $0.GetMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyTreinamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> finalizarMyTreinamento(
    $0.FinalizarMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$finalizarMyTreinamento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> removerMyTreinamento(
    $0.RemoverMyTreinamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removerMyTreinamento, request, options: options);
  }

  /// Gestão das conexões de WhatsApp DEPOIS de conectadas.
  ///
  /// O onboarding cria a primeira; sem estas, uma conexão que cai deixa o tenant
  /// sem saída — não há como ver o estado, reconectar nem trocar de aparelho.
  $grpc.ResponseFuture<$0.ListMyWhatsappInstancesResponse>
      listMyWhatsappInstances(
    $0.ListMyWhatsappInstancesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyWhatsappInstances, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> reconnectMyWhatsappInstance(
    $0.MyWhatsappInstanceIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$reconnectMyWhatsappInstance, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> deleteMyWhatsappInstance(
    $0.MyWhatsappInstanceIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$deleteMyWhatsappInstance, request,
        options: options);
  }

  /// Departamentos e atendentes — a estrutura para onde a fila manda conversa.
  $grpc.ResponseFuture<$0.ListMyDepartamentosResponse> listMyDepartamentos(
    $0.ListMyDepartamentosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyDepartamentos, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> updateMyDepartamento(
    $0.UpdateMyDepartamentoRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$updateMyDepartamento, request, options: options);
  }

  $grpc.ResponseFuture<$0.SimpleOkResponse> desativarMyDepartamento(
    $0.MyDepartamentoIdRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$desativarMyDepartamento, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ListMyAtendentesResponse> listMyAtendentes(
    $0.ListMyAtendentesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyAtendentes, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetMyPainelResponse> getMyPainel(
    $0.GetMyPainelRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMyPainel, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMyContatosResponse> listMyContatos(
    $0.ListMyContatosRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMyContatos, request, options: options);
  }

  // method descriptors

  static final _$listCoreSettings = $grpc.ClientMethod<
          $0.ListCoreSettingsRequest, $0.ListCoreSettingsResponse>(
      '/smartcore.contracts.queries.AdminService/ListCoreSettings',
      ($0.ListCoreSettingsRequest value) => value.writeToBuffer(),
      $0.ListCoreSettingsResponse.fromBuffer);
  static final _$upsertCoreSetting = $grpc.ClientMethod<
          $0.UpsertCoreSettingRequest, $0.UpsertCoreSettingResponse>(
      '/smartcore.contracts.queries.AdminService/UpsertCoreSetting',
      ($0.UpsertCoreSettingRequest value) => value.writeToBuffer(),
      $0.UpsertCoreSettingResponse.fromBuffer);
  static final _$deleteCoreSetting = $grpc.ClientMethod<
          $0.DeleteCoreSettingRequest, $0.DeleteCoreSettingResponse>(
      '/smartcore.contracts.queries.AdminService/DeleteCoreSetting',
      ($0.DeleteCoreSettingRequest value) => value.writeToBuffer(),
      $0.DeleteCoreSettingResponse.fromBuffer);
  static final _$getTenantConfig =
      $grpc.ClientMethod<$0.GetTenantConfigRequest, $0.GetTenantConfigResponse>(
          '/smartcore.contracts.queries.AdminService/GetTenantConfig',
          ($0.GetTenantConfigRequest value) => value.writeToBuffer(),
          $0.GetTenantConfigResponse.fromBuffer);
  static final _$updateTenantConfig = $grpc.ClientMethod<
          $0.UpdateTenantConfigRequest, $0.UpdateTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateTenantConfig',
      ($0.UpdateTenantConfigRequest value) => value.writeToBuffer(),
      $0.UpdateTenantConfigResponse.fromBuffer);
  static final _$listTenants =
      $grpc.ClientMethod<$0.ListTenantsRequest, $0.ListTenantsResponse>(
          '/smartcore.contracts.queries.AdminService/ListTenants',
          ($0.ListTenantsRequest value) => value.writeToBuffer(),
          $0.ListTenantsResponse.fromBuffer);
  static final _$getTenant =
      $grpc.ClientMethod<$0.GetTenantRequest, $0.GetTenantResponse>(
          '/smartcore.contracts.queries.AdminService/GetTenant',
          ($0.GetTenantRequest value) => value.writeToBuffer(),
          $0.GetTenantResponse.fromBuffer);
  static final _$createTenant =
      $grpc.ClientMethod<$0.CreateTenantRequest, $0.CreateTenantResponse>(
          '/smartcore.contracts.queries.AdminService/CreateTenant',
          ($0.CreateTenantRequest value) => value.writeToBuffer(),
          $0.CreateTenantResponse.fromBuffer);
  static final _$updateTenant =
      $grpc.ClientMethod<$0.UpdateTenantRequest, $0.UpdateTenantResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateTenant',
          ($0.UpdateTenantRequest value) => value.writeToBuffer(),
          $0.UpdateTenantResponse.fromBuffer);
  static final _$setTenantActive =
      $grpc.ClientMethod<$0.SetTenantActiveRequest, $0.SetTenantActiveResponse>(
          '/smartcore.contracts.queries.AdminService/SetTenantActive',
          ($0.SetTenantActiveRequest value) => value.writeToBuffer(),
          $0.SetTenantActiveResponse.fromBuffer);
  static final _$generateAccessCode = $grpc.ClientMethod<
          $0.GenerateAccessCodeRequest, $0.GenerateAccessCodeResponse>(
      '/smartcore.contracts.queries.AdminService/GenerateAccessCode',
      ($0.GenerateAccessCodeRequest value) => value.writeToBuffer(),
      $0.GenerateAccessCodeResponse.fromBuffer);
  static final _$listPlans =
      $grpc.ClientMethod<$0.ListPlansRequest, $0.ListPlansResponse>(
          '/smartcore.contracts.queries.AdminService/ListPlans',
          ($0.ListPlansRequest value) => value.writeToBuffer(),
          $0.ListPlansResponse.fromBuffer);
  static final _$createPlan =
      $grpc.ClientMethod<$0.CreatePlanRequest, $0.CreatePlanResponse>(
          '/smartcore.contracts.queries.AdminService/CreatePlan',
          ($0.CreatePlanRequest value) => value.writeToBuffer(),
          $0.CreatePlanResponse.fromBuffer);
  static final _$updatePlan =
      $grpc.ClientMethod<$0.UpdatePlanRequest, $0.UpdatePlanResponse>(
          '/smartcore.contracts.queries.AdminService/UpdatePlan',
          ($0.UpdatePlanRequest value) => value.writeToBuffer(),
          $0.UpdatePlanResponse.fromBuffer);
  static final _$listSubscriptions = $grpc.ClientMethod<
          $0.ListSubscriptionsRequest, $0.ListSubscriptionsResponse>(
      '/smartcore.contracts.queries.AdminService/ListSubscriptions',
      ($0.ListSubscriptionsRequest value) => value.writeToBuffer(),
      $0.ListSubscriptionsResponse.fromBuffer);
  static final _$registerPayment =
      $grpc.ClientMethod<$0.RegisterPaymentRequest, $0.RegisterPaymentResponse>(
          '/smartcore.contracts.queries.AdminService/RegisterPayment',
          ($0.RegisterPaymentRequest value) => value.writeToBuffer(),
          $0.RegisterPaymentResponse.fromBuffer);
  static final _$listPayments =
      $grpc.ClientMethod<$0.ListPaymentsRequest, $0.ListPaymentsResponse>(
          '/smartcore.contracts.queries.AdminService/ListPayments',
          ($0.ListPaymentsRequest value) => value.writeToBuffer(),
          $0.ListPaymentsResponse.fromBuffer);
  static final _$listVouchers =
      $grpc.ClientMethod<$0.ListVouchersRequest, $0.ListVouchersResponse>(
          '/smartcore.contracts.queries.AdminService/ListVouchers',
          ($0.ListVouchersRequest value) => value.writeToBuffer(),
          $0.ListVouchersResponse.fromBuffer);
  static final _$createVoucher =
      $grpc.ClientMethod<$0.CreateVoucherRequest, $0.CreateVoucherResponse>(
          '/smartcore.contracts.queries.AdminService/CreateVoucher',
          ($0.CreateVoucherRequest value) => value.writeToBuffer(),
          $0.CreateVoucherResponse.fromBuffer);
  static final _$revokeVoucher =
      $grpc.ClientMethod<$0.RevokeVoucherRequest, $0.RevokeVoucherResponse>(
          '/smartcore.contracts.queries.AdminService/RevokeVoucher',
          ($0.RevokeVoucherRequest value) => value.writeToBuffer(),
          $0.RevokeVoucherResponse.fromBuffer);
  static final _$listVoucherRedemptions = $grpc.ClientMethod<
          $0.ListVoucherRedemptionsRequest, $0.ListVoucherRedemptionsResponse>(
      '/smartcore.contracts.queries.AdminService/ListVoucherRedemptions',
      ($0.ListVoucherRedemptionsRequest value) => value.writeToBuffer(),
      $0.ListVoucherRedemptionsResponse.fromBuffer);
  static final _$testEvolutionConnection = $grpc.ClientMethod<
          $0.TestEvolutionConnectionRequest,
          $0.TestEvolutionConnectionResponse>(
      '/smartcore.contracts.queries.AdminService/TestEvolutionConnection',
      ($0.TestEvolutionConnectionRequest value) => value.writeToBuffer(),
      $0.TestEvolutionConnectionResponse.fromBuffer);
  static final _$listFeatureFlags = $grpc.ClientMethod<
          $0.ListFeatureFlagsRequest, $0.ListFeatureFlagsResponse>(
      '/smartcore.contracts.queries.AdminService/ListFeatureFlags',
      ($0.ListFeatureFlagsRequest value) => value.writeToBuffer(),
      $0.ListFeatureFlagsResponse.fromBuffer);
  static final _$setFeatureFlag =
      $grpc.ClientMethod<$0.SetFeatureFlagRequest, $0.SetFeatureFlagResponse>(
          '/smartcore.contracts.queries.AdminService/SetFeatureFlag',
          ($0.SetFeatureFlagRequest value) => value.writeToBuffer(),
          $0.SetFeatureFlagResponse.fromBuffer);
  static final _$setFeatureFlagOverride = $grpc.ClientMethod<
          $0.SetFeatureFlagOverrideRequest, $0.SetFeatureFlagOverrideResponse>(
      '/smartcore.contracts.queries.AdminService/SetFeatureFlagOverride',
      ($0.SetFeatureFlagOverrideRequest value) => value.writeToBuffer(),
      $0.SetFeatureFlagOverrideResponse.fromBuffer);
  static final _$queryAuditLog =
      $grpc.ClientMethod<$0.QueryAuditLogRequest, $0.QueryAuditLogResponse>(
          '/smartcore.contracts.queries.AdminService/QueryAuditLog',
          ($0.QueryAuditLogRequest value) => value.writeToBuffer(),
          $0.QueryAuditLogResponse.fromBuffer);
  static final _$getServiceHealth = $grpc.ClientMethod<
          $0.GetServiceHealthRequest, $0.GetServiceHealthResponse>(
      '/smartcore.contracts.queries.AdminService/GetServiceHealth',
      ($0.GetServiceHealthRequest value) => value.writeToBuffer(),
      $0.GetServiceHealthResponse.fromBuffer);
  static final _$getDashboardSummary = $grpc.ClientMethod<
          $0.GetDashboardSummaryRequest, $0.GetDashboardSummaryResponse>(
      '/smartcore.contracts.queries.AdminService/GetDashboardSummary',
      ($0.GetDashboardSummaryRequest value) => value.writeToBuffer(),
      $0.GetDashboardSummaryResponse.fromBuffer);
  static final _$exportTenantsCsv = $grpc.ClientMethod<
          $0.ExportTenantsCsvRequest, $0.ExportTenantsCsvResponse>(
      '/smartcore.contracts.queries.AdminService/ExportTenantsCsv',
      ($0.ExportTenantsCsvRequest value) => value.writeToBuffer(),
      $0.ExportTenantsCsvResponse.fromBuffer);
  static final _$streamAtendimentos =
      $grpc.ClientMethod<$0.StreamAtendimentosRequest, $0.AtendimentoEvent>(
          '/smartcore.contracts.queries.AdminService/StreamAtendimentos',
          ($0.StreamAtendimentosRequest value) => value.writeToBuffer(),
          $0.AtendimentoEvent.fromBuffer);
  static final _$listAtendimentos = $grpc.ClientMethod<
          $0.ListAtendimentosRequest, $0.ListAtendimentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListAtendimentos',
      ($0.ListAtendimentosRequest value) => value.writeToBuffer(),
      $0.ListAtendimentosResponse.fromBuffer);
  static final _$getThread =
      $grpc.ClientMethod<$0.GetThreadRequest, $0.GetThreadResponse>(
          '/smartcore.contracts.queries.AdminService/GetThread',
          ($0.GetThreadRequest value) => value.writeToBuffer(),
          $0.GetThreadResponse.fromBuffer);
  static final _$moveAtendimentoEtapa = $grpc.ClientMethod<
          $0.MoveAtendimentoEtapaRequest, $0.MoveAtendimentoEtapaResponse>(
      '/smartcore.contracts.queries.AdminService/MoveAtendimentoEtapa',
      ($0.MoveAtendimentoEtapaRequest value) => value.writeToBuffer(),
      $0.MoveAtendimentoEtapaResponse.fromBuffer);
  static final _$sendOutboundMessage = $grpc.ClientMethod<
          $0.SendOutboundMessageRequest, $0.SendOutboundMessageResponse>(
      '/smartcore.contracts.queries.AdminService/SendOutboundMessage',
      ($0.SendOutboundMessageRequest value) => value.writeToBuffer(),
      $0.SendOutboundMessageResponse.fromBuffer);
  static final _$createInvite =
      $grpc.ClientMethod<$0.CreateInviteRequest, $0.CreateInviteResponse>(
          '/smartcore.contracts.queries.AdminService/CreateInvite',
          ($0.CreateInviteRequest value) => value.writeToBuffer(),
          $0.CreateInviteResponse.fromBuffer);
  static final _$acceptInvite =
      $grpc.ClientMethod<$0.AcceptInviteRequest, $0.AcceptInviteResponse>(
          '/smartcore.contracts.queries.AdminService/AcceptInvite',
          ($0.AcceptInviteRequest value) => value.writeToBuffer(),
          $0.AcceptInviteResponse.fromBuffer);
  static final _$listInvites =
      $grpc.ClientMethod<$0.ListInvitesRequest, $0.ListInvitesResponse>(
          '/smartcore.contracts.queries.AdminService/ListInvites',
          ($0.ListInvitesRequest value) => value.writeToBuffer(),
          $0.ListInvitesResponse.fromBuffer);
  static final _$revokeInvite =
      $grpc.ClientMethod<$0.RevokeInviteRequest, $0.RevokeInviteResponse>(
          '/smartcore.contracts.queries.AdminService/RevokeInvite',
          ($0.RevokeInviteRequest value) => value.writeToBuffer(),
          $0.RevokeInviteResponse.fromBuffer);
  static final _$listTenantUsers =
      $grpc.ClientMethod<$0.ListTenantUsersRequest, $0.ListTenantUsersResponse>(
          '/smartcore.contracts.queries.AdminService/ListTenantUsers',
          ($0.ListTenantUsersRequest value) => value.writeToBuffer(),
          $0.ListTenantUsersResponse.fromBuffer);
  static final _$updateTenantUser = $grpc.ClientMethod<
          $0.UpdateTenantUserRequest, $0.UpdateTenantUserResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateTenantUser',
      ($0.UpdateTenantUserRequest value) => value.writeToBuffer(),
      $0.UpdateTenantUserResponse.fromBuffer);
  static final _$getMyTenantConfig = $grpc.ClientMethod<
          $0.GetMyTenantConfigRequest, $0.GetTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyTenantConfig',
      ($0.GetMyTenantConfigRequest value) => value.writeToBuffer(),
      $0.GetTenantConfigResponse.fromBuffer);
  static final _$updateMyTenantConfig = $grpc.ClientMethod<
          $0.UpdateMyTenantConfigRequest, $0.UpdateTenantConfigResponse>(
      '/smartcore.contracts.queries.AdminService/UpdateMyTenantConfig',
      ($0.UpdateMyTenantConfigRequest value) => value.writeToBuffer(),
      $0.UpdateTenantConfigResponse.fromBuffer);
  static final _$createMyWhatsappInstance = $grpc.ClientMethod<
          $0.CreateMyWhatsappInstanceRequest,
          $0.CreateMyWhatsappInstanceResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyWhatsappInstance',
      ($0.CreateMyWhatsappInstanceRequest value) => value.writeToBuffer(),
      $0.CreateMyWhatsappInstanceResponse.fromBuffer);
  static final _$getMyWhatsappInstanceStatus = $grpc.ClientMethod<
          $0.GetMyWhatsappInstanceStatusRequest,
          $0.GetMyWhatsappInstanceStatusResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyWhatsappInstanceStatus',
      ($0.GetMyWhatsappInstanceStatusRequest value) => value.writeToBuffer(),
      $0.GetMyWhatsappInstanceStatusResponse.fromBuffer);
  static final _$createMyDepartamento = $grpc.ClientMethod<
          $0.CreateMyDepartamentoRequest, $0.CreateMyDepartamentoResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyDepartamento',
      ($0.CreateMyDepartamentoRequest value) => value.writeToBuffer(),
      $0.CreateMyDepartamentoResponse.fromBuffer);
  static final _$setMyBotPersona =
      $grpc.ClientMethod<$0.SetMyBotPersonaRequest, $0.SetMyBotPersonaResponse>(
          '/smartcore.contracts.queries.AdminService/SetMyBotPersona',
          ($0.SetMyBotPersonaRequest value) => value.writeToBuffer(),
          $0.SetMyBotPersonaResponse.fromBuffer);
  static final _$setOnboardingProgress = $grpc.ClientMethod<
          $0.SetOnboardingProgressRequest, $0.SetOnboardingProgressResponse>(
      '/smartcore.contracts.queries.AdminService/SetOnboardingProgress',
      ($0.SetOnboardingProgressRequest value) => value.writeToBuffer(),
      $0.SetOnboardingProgressResponse.fromBuffer);
  static final _$getMyOnboardingProgress = $grpc.ClientMethod<
          $0.GetMyOnboardingProgressRequest,
          $0.GetMyOnboardingProgressResponse>(
      '/smartcore.contracts.queries.AdminService/GetMyOnboardingProgress',
      ($0.GetMyOnboardingProgressRequest value) => value.writeToBuffer(),
      $0.GetMyOnboardingProgressResponse.fromBuffer);
  static final _$createMyTreinamento = $grpc.ClientMethod<
          $0.CreateMyTreinamentoRequest, $0.MyTreinamentoResponse>(
      '/smartcore.contracts.queries.AdminService/CreateMyTreinamento',
      ($0.CreateMyTreinamentoRequest value) => value.writeToBuffer(),
      $0.MyTreinamentoResponse.fromBuffer);
  static final _$listMyTreinamentos = $grpc.ClientMethod<
          $0.ListMyTreinamentosRequest, $0.ListMyTreinamentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyTreinamentos',
      ($0.ListMyTreinamentosRequest value) => value.writeToBuffer(),
      $0.ListMyTreinamentosResponse.fromBuffer);
  static final _$getMyTreinamento =
      $grpc.ClientMethod<$0.GetMyTreinamentoRequest, $0.MyTreinamentoResponse>(
          '/smartcore.contracts.queries.AdminService/GetMyTreinamento',
          ($0.GetMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.MyTreinamentoResponse.fromBuffer);
  static final _$finalizarMyTreinamento =
      $grpc.ClientMethod<$0.FinalizarMyTreinamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/FinalizarMyTreinamento',
          ($0.FinalizarMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$removerMyTreinamento =
      $grpc.ClientMethod<$0.RemoverMyTreinamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/RemoverMyTreinamento',
          ($0.RemoverMyTreinamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyWhatsappInstances = $grpc.ClientMethod<
          $0.ListMyWhatsappInstancesRequest,
          $0.ListMyWhatsappInstancesResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyWhatsappInstances',
      ($0.ListMyWhatsappInstancesRequest value) => value.writeToBuffer(),
      $0.ListMyWhatsappInstancesResponse.fromBuffer);
  static final _$reconnectMyWhatsappInstance = $grpc.ClientMethod<
          $0.MyWhatsappInstanceIdRequest, $0.SimpleOkResponse>(
      '/smartcore.contracts.queries.AdminService/ReconnectMyWhatsappInstance',
      ($0.MyWhatsappInstanceIdRequest value) => value.writeToBuffer(),
      $0.SimpleOkResponse.fromBuffer);
  static final _$deleteMyWhatsappInstance =
      $grpc.ClientMethod<$0.MyWhatsappInstanceIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DeleteMyWhatsappInstance',
          ($0.MyWhatsappInstanceIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyDepartamentos = $grpc.ClientMethod<
          $0.ListMyDepartamentosRequest, $0.ListMyDepartamentosResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyDepartamentos',
      ($0.ListMyDepartamentosRequest value) => value.writeToBuffer(),
      $0.ListMyDepartamentosResponse.fromBuffer);
  static final _$updateMyDepartamento =
      $grpc.ClientMethod<$0.UpdateMyDepartamentoRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/UpdateMyDepartamento',
          ($0.UpdateMyDepartamentoRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$desativarMyDepartamento =
      $grpc.ClientMethod<$0.MyDepartamentoIdRequest, $0.SimpleOkResponse>(
          '/smartcore.contracts.queries.AdminService/DesativarMyDepartamento',
          ($0.MyDepartamentoIdRequest value) => value.writeToBuffer(),
          $0.SimpleOkResponse.fromBuffer);
  static final _$listMyAtendentes = $grpc.ClientMethod<
          $0.ListMyAtendentesRequest, $0.ListMyAtendentesResponse>(
      '/smartcore.contracts.queries.AdminService/ListMyAtendentes',
      ($0.ListMyAtendentesRequest value) => value.writeToBuffer(),
      $0.ListMyAtendentesResponse.fromBuffer);
  static final _$getMyPainel =
      $grpc.ClientMethod<$0.GetMyPainelRequest, $0.GetMyPainelResponse>(
          '/smartcore.contracts.queries.AdminService/GetMyPainel',
          ($0.GetMyPainelRequest value) => value.writeToBuffer(),
          $0.GetMyPainelResponse.fromBuffer);
  static final _$listMyContatos =
      $grpc.ClientMethod<$0.ListMyContatosRequest, $0.ListMyContatosResponse>(
          '/smartcore.contracts.queries.AdminService/ListMyContatos',
          ($0.ListMyContatosRequest value) => value.writeToBuffer(),
          $0.ListMyContatosResponse.fromBuffer);
}

@$pb.GrpcServiceName('smartcore.contracts.queries.AdminService')
abstract class AdminServiceBase extends $grpc.Service {
  $core.String get $name => 'smartcore.contracts.queries.AdminService';

  AdminServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ListCoreSettingsRequest,
            $0.ListCoreSettingsResponse>(
        'ListCoreSettings',
        listCoreSettings_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListCoreSettingsRequest.fromBuffer(value),
        ($0.ListCoreSettingsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpsertCoreSettingRequest,
            $0.UpsertCoreSettingResponse>(
        'UpsertCoreSetting',
        upsertCoreSetting_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpsertCoreSettingRequest.fromBuffer(value),
        ($0.UpsertCoreSettingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DeleteCoreSettingRequest,
            $0.DeleteCoreSettingResponse>(
        'DeleteCoreSetting',
        deleteCoreSetting_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.DeleteCoreSettingRequest.fromBuffer(value),
        ($0.DeleteCoreSettingResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetTenantConfigRequest,
            $0.GetTenantConfigResponse>(
        'GetTenantConfig',
        getTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetTenantConfigRequest.fromBuffer(value),
        ($0.GetTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateTenantConfigRequest,
            $0.UpdateTenantConfigResponse>(
        'UpdateTenantConfig',
        updateTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateTenantConfigRequest.fromBuffer(value),
        ($0.UpdateTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListTenantsRequest, $0.ListTenantsResponse>(
            'ListTenants',
            listTenants_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListTenantsRequest.fromBuffer(value),
            ($0.ListTenantsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetTenantRequest, $0.GetTenantResponse>(
        'GetTenant',
        getTenant_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetTenantRequest.fromBuffer(value),
        ($0.GetTenantResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateTenantRequest, $0.CreateTenantResponse>(
            'CreateTenant',
            createTenant_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateTenantRequest.fromBuffer(value),
            ($0.CreateTenantResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UpdateTenantRequest, $0.UpdateTenantResponse>(
            'UpdateTenant',
            updateTenant_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UpdateTenantRequest.fromBuffer(value),
            ($0.UpdateTenantResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetTenantActiveRequest,
            $0.SetTenantActiveResponse>(
        'SetTenantActive',
        setTenantActive_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetTenantActiveRequest.fromBuffer(value),
        ($0.SetTenantActiveResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GenerateAccessCodeRequest,
            $0.GenerateAccessCodeResponse>(
        'GenerateAccessCode',
        generateAccessCode_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GenerateAccessCodeRequest.fromBuffer(value),
        ($0.GenerateAccessCodeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListPlansRequest, $0.ListPlansResponse>(
        'ListPlans',
        listPlans_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ListPlansRequest.fromBuffer(value),
        ($0.ListPlansResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreatePlanRequest, $0.CreatePlanResponse>(
        'CreatePlan',
        createPlan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CreatePlanRequest.fromBuffer(value),
        ($0.CreatePlanResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdatePlanRequest, $0.UpdatePlanResponse>(
        'UpdatePlan',
        updatePlan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.UpdatePlanRequest.fromBuffer(value),
        ($0.UpdatePlanResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListSubscriptionsRequest,
            $0.ListSubscriptionsResponse>(
        'ListSubscriptions',
        listSubscriptions_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListSubscriptionsRequest.fromBuffer(value),
        ($0.ListSubscriptionsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RegisterPaymentRequest,
            $0.RegisterPaymentResponse>(
        'RegisterPayment',
        registerPayment_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RegisterPaymentRequest.fromBuffer(value),
        ($0.RegisterPaymentResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListPaymentsRequest, $0.ListPaymentsResponse>(
            'ListPayments',
            listPayments_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListPaymentsRequest.fromBuffer(value),
            ($0.ListPaymentsResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListVouchersRequest, $0.ListVouchersResponse>(
            'ListVouchers',
            listVouchers_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListVouchersRequest.fromBuffer(value),
            ($0.ListVouchersResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateVoucherRequest, $0.CreateVoucherResponse>(
            'CreateVoucher',
            createVoucher_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateVoucherRequest.fromBuffer(value),
            ($0.CreateVoucherResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RevokeVoucherRequest, $0.RevokeVoucherResponse>(
            'RevokeVoucher',
            revokeVoucher_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RevokeVoucherRequest.fromBuffer(value),
            ($0.RevokeVoucherResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListVoucherRedemptionsRequest,
            $0.ListVoucherRedemptionsResponse>(
        'ListVoucherRedemptions',
        listVoucherRedemptions_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListVoucherRedemptionsRequest.fromBuffer(value),
        ($0.ListVoucherRedemptionsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.TestEvolutionConnectionRequest,
            $0.TestEvolutionConnectionResponse>(
        'TestEvolutionConnection',
        testEvolutionConnection_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.TestEvolutionConnectionRequest.fromBuffer(value),
        ($0.TestEvolutionConnectionResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListFeatureFlagsRequest,
            $0.ListFeatureFlagsResponse>(
        'ListFeatureFlags',
        listFeatureFlags_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListFeatureFlagsRequest.fromBuffer(value),
        ($0.ListFeatureFlagsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetFeatureFlagRequest,
            $0.SetFeatureFlagResponse>(
        'SetFeatureFlag',
        setFeatureFlag_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetFeatureFlagRequest.fromBuffer(value),
        ($0.SetFeatureFlagResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetFeatureFlagOverrideRequest,
            $0.SetFeatureFlagOverrideResponse>(
        'SetFeatureFlagOverride',
        setFeatureFlagOverride_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetFeatureFlagOverrideRequest.fromBuffer(value),
        ($0.SetFeatureFlagOverrideResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.QueryAuditLogRequest, $0.QueryAuditLogResponse>(
            'QueryAuditLog',
            queryAuditLog_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.QueryAuditLogRequest.fromBuffer(value),
            ($0.QueryAuditLogResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetServiceHealthRequest,
            $0.GetServiceHealthResponse>(
        'GetServiceHealth',
        getServiceHealth_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetServiceHealthRequest.fromBuffer(value),
        ($0.GetServiceHealthResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetDashboardSummaryRequest,
            $0.GetDashboardSummaryResponse>(
        'GetDashboardSummary',
        getDashboardSummary_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetDashboardSummaryRequest.fromBuffer(value),
        ($0.GetDashboardSummaryResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ExportTenantsCsvRequest,
            $0.ExportTenantsCsvResponse>(
        'ExportTenantsCsv',
        exportTenantsCsv_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.ExportTenantsCsvRequest.fromBuffer(value),
        ($0.ExportTenantsCsvResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.StreamAtendimentosRequest, $0.AtendimentoEvent>(
            'StreamAtendimentos',
            streamAtendimentos_Pre,
            false,
            true,
            ($core.List<$core.int> value) =>
                $0.StreamAtendimentosRequest.fromBuffer(value),
            ($0.AtendimentoEvent value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListAtendimentosRequest,
            $0.ListAtendimentosResponse>(
        'ListAtendimentos',
        listAtendimentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListAtendimentosRequest.fromBuffer(value),
        ($0.ListAtendimentosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetThreadRequest, $0.GetThreadResponse>(
        'GetThread',
        getThread_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.GetThreadRequest.fromBuffer(value),
        ($0.GetThreadResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MoveAtendimentoEtapaRequest,
            $0.MoveAtendimentoEtapaResponse>(
        'MoveAtendimentoEtapa',
        moveAtendimentoEtapa_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MoveAtendimentoEtapaRequest.fromBuffer(value),
        ($0.MoveAtendimentoEtapaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SendOutboundMessageRequest,
            $0.SendOutboundMessageResponse>(
        'SendOutboundMessage',
        sendOutboundMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SendOutboundMessageRequest.fromBuffer(value),
        ($0.SendOutboundMessageResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateInviteRequest, $0.CreateInviteResponse>(
            'CreateInvite',
            createInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateInviteRequest.fromBuffer(value),
            ($0.CreateInviteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.AcceptInviteRequest, $0.AcceptInviteResponse>(
            'AcceptInvite',
            acceptInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.AcceptInviteRequest.fromBuffer(value),
            ($0.AcceptInviteResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListInvitesRequest, $0.ListInvitesResponse>(
            'ListInvites',
            listInvites_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListInvitesRequest.fromBuffer(value),
            ($0.ListInvitesResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.RevokeInviteRequest, $0.RevokeInviteResponse>(
            'RevokeInvite',
            revokeInvite_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.RevokeInviteRequest.fromBuffer(value),
            ($0.RevokeInviteResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListTenantUsersRequest,
            $0.ListTenantUsersResponse>(
        'ListTenantUsers',
        listTenantUsers_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListTenantUsersRequest.fromBuffer(value),
        ($0.ListTenantUsersResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateTenantUserRequest,
            $0.UpdateTenantUserResponse>(
        'UpdateTenantUser',
        updateTenantUser_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateTenantUserRequest.fromBuffer(value),
        ($0.UpdateTenantUserResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyTenantConfigRequest,
            $0.GetTenantConfigResponse>(
        'GetMyTenantConfig',
        getMyTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyTenantConfigRequest.fromBuffer(value),
        ($0.GetTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateMyTenantConfigRequest,
            $0.UpdateTenantConfigResponse>(
        'UpdateMyTenantConfig',
        updateMyTenantConfig_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateMyTenantConfigRequest.fromBuffer(value),
        ($0.UpdateTenantConfigResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyWhatsappInstanceRequest,
            $0.CreateMyWhatsappInstanceResponse>(
        'CreateMyWhatsappInstance',
        createMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyWhatsappInstanceRequest.fromBuffer(value),
        ($0.CreateMyWhatsappInstanceResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyWhatsappInstanceStatusRequest,
            $0.GetMyWhatsappInstanceStatusResponse>(
        'GetMyWhatsappInstanceStatus',
        getMyWhatsappInstanceStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyWhatsappInstanceStatusRequest.fromBuffer(value),
        ($0.GetMyWhatsappInstanceStatusResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyDepartamentoRequest,
            $0.CreateMyDepartamentoResponse>(
        'CreateMyDepartamento',
        createMyDepartamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyDepartamentoRequest.fromBuffer(value),
        ($0.CreateMyDepartamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetMyBotPersonaRequest,
            $0.SetMyBotPersonaResponse>(
        'SetMyBotPersona',
        setMyBotPersona_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetMyBotPersonaRequest.fromBuffer(value),
        ($0.SetMyBotPersonaResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetOnboardingProgressRequest,
            $0.SetOnboardingProgressResponse>(
        'SetOnboardingProgress',
        setOnboardingProgress_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetOnboardingProgressRequest.fromBuffer(value),
        ($0.SetOnboardingProgressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyOnboardingProgressRequest,
            $0.GetMyOnboardingProgressResponse>(
        'GetMyOnboardingProgress',
        getMyOnboardingProgress_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyOnboardingProgressRequest.fromBuffer(value),
        ($0.GetMyOnboardingProgressResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateMyTreinamentoRequest,
            $0.MyTreinamentoResponse>(
        'CreateMyTreinamento',
        createMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMyTreinamentoRequest.fromBuffer(value),
        ($0.MyTreinamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyTreinamentosRequest,
            $0.ListMyTreinamentosResponse>(
        'ListMyTreinamentos',
        listMyTreinamentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyTreinamentosRequest.fromBuffer(value),
        ($0.ListMyTreinamentosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetMyTreinamentoRequest,
            $0.MyTreinamentoResponse>(
        'GetMyTreinamento',
        getMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetMyTreinamentoRequest.fromBuffer(value),
        ($0.MyTreinamentoResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.FinalizarMyTreinamentoRequest,
            $0.SimpleOkResponse>(
        'FinalizarMyTreinamento',
        finalizarMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.FinalizarMyTreinamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RemoverMyTreinamentoRequest,
            $0.SimpleOkResponse>(
        'RemoverMyTreinamento',
        removerMyTreinamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RemoverMyTreinamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyWhatsappInstancesRequest,
            $0.ListMyWhatsappInstancesResponse>(
        'ListMyWhatsappInstances',
        listMyWhatsappInstances_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyWhatsappInstancesRequest.fromBuffer(value),
        ($0.ListMyWhatsappInstancesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyWhatsappInstanceIdRequest,
            $0.SimpleOkResponse>(
        'ReconnectMyWhatsappInstance',
        reconnectMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyWhatsappInstanceIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MyWhatsappInstanceIdRequest,
            $0.SimpleOkResponse>(
        'DeleteMyWhatsappInstance',
        deleteMyWhatsappInstance_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MyWhatsappInstanceIdRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyDepartamentosRequest,
            $0.ListMyDepartamentosResponse>(
        'ListMyDepartamentos',
        listMyDepartamentos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyDepartamentosRequest.fromBuffer(value),
        ($0.ListMyDepartamentosResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UpdateMyDepartamentoRequest,
            $0.SimpleOkResponse>(
        'UpdateMyDepartamento',
        updateMyDepartamento_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpdateMyDepartamentoRequest.fromBuffer(value),
        ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.MyDepartamentoIdRequest, $0.SimpleOkResponse>(
            'DesativarMyDepartamento',
            desativarMyDepartamento_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.MyDepartamentoIdRequest.fromBuffer(value),
            ($0.SimpleOkResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyAtendentesRequest,
            $0.ListMyAtendentesResponse>(
        'ListMyAtendentes',
        listMyAtendentes_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyAtendentesRequest.fromBuffer(value),
        ($0.ListMyAtendentesResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetMyPainelRequest, $0.GetMyPainelResponse>(
            'GetMyPainel',
            getMyPainel_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetMyPainelRequest.fromBuffer(value),
            ($0.GetMyPainelResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListMyContatosRequest,
            $0.ListMyContatosResponse>(
        'ListMyContatos',
        listMyContatos_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListMyContatosRequest.fromBuffer(value),
        ($0.ListMyContatosResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.ListCoreSettingsResponse> listCoreSettings_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListCoreSettingsRequest> $request) async {
    return listCoreSettings($call, await $request);
  }

  $async.Future<$0.ListCoreSettingsResponse> listCoreSettings(
      $grpc.ServiceCall call, $0.ListCoreSettingsRequest request);

  $async.Future<$0.UpsertCoreSettingResponse> upsertCoreSetting_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpsertCoreSettingRequest> $request) async {
    return upsertCoreSetting($call, await $request);
  }

  $async.Future<$0.UpsertCoreSettingResponse> upsertCoreSetting(
      $grpc.ServiceCall call, $0.UpsertCoreSettingRequest request);

  $async.Future<$0.DeleteCoreSettingResponse> deleteCoreSetting_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.DeleteCoreSettingRequest> $request) async {
    return deleteCoreSetting($call, await $request);
  }

  $async.Future<$0.DeleteCoreSettingResponse> deleteCoreSetting(
      $grpc.ServiceCall call, $0.DeleteCoreSettingRequest request);

  $async.Future<$0.GetTenantConfigResponse> getTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetTenantConfigRequest> $request) async {
    return getTenantConfig($call, await $request);
  }

  $async.Future<$0.GetTenantConfigResponse> getTenantConfig(
      $grpc.ServiceCall call, $0.GetTenantConfigRequest request);

  $async.Future<$0.UpdateTenantConfigResponse> updateTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantConfigRequest> $request) async {
    return updateTenantConfig($call, await $request);
  }

  $async.Future<$0.UpdateTenantConfigResponse> updateTenantConfig(
      $grpc.ServiceCall call, $0.UpdateTenantConfigRequest request);

  $async.Future<$0.ListTenantsResponse> listTenants_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListTenantsRequest> $request) async {
    return listTenants($call, await $request);
  }

  $async.Future<$0.ListTenantsResponse> listTenants(
      $grpc.ServiceCall call, $0.ListTenantsRequest request);

  $async.Future<$0.GetTenantResponse> getTenant_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetTenantRequest> $request) async {
    return getTenant($call, await $request);
  }

  $async.Future<$0.GetTenantResponse> getTenant(
      $grpc.ServiceCall call, $0.GetTenantRequest request);

  $async.Future<$0.CreateTenantResponse> createTenant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateTenantRequest> $request) async {
    return createTenant($call, await $request);
  }

  $async.Future<$0.CreateTenantResponse> createTenant(
      $grpc.ServiceCall call, $0.CreateTenantRequest request);

  $async.Future<$0.UpdateTenantResponse> updateTenant_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantRequest> $request) async {
    return updateTenant($call, await $request);
  }

  $async.Future<$0.UpdateTenantResponse> updateTenant(
      $grpc.ServiceCall call, $0.UpdateTenantRequest request);

  $async.Future<$0.SetTenantActiveResponse> setTenantActive_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetTenantActiveRequest> $request) async {
    return setTenantActive($call, await $request);
  }

  $async.Future<$0.SetTenantActiveResponse> setTenantActive(
      $grpc.ServiceCall call, $0.SetTenantActiveRequest request);

  $async.Future<$0.GenerateAccessCodeResponse> generateAccessCode_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GenerateAccessCodeRequest> $request) async {
    return generateAccessCode($call, await $request);
  }

  $async.Future<$0.GenerateAccessCodeResponse> generateAccessCode(
      $grpc.ServiceCall call, $0.GenerateAccessCodeRequest request);

  $async.Future<$0.ListPlansResponse> listPlans_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListPlansRequest> $request) async {
    return listPlans($call, await $request);
  }

  $async.Future<$0.ListPlansResponse> listPlans(
      $grpc.ServiceCall call, $0.ListPlansRequest request);

  $async.Future<$0.CreatePlanResponse> createPlan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreatePlanRequest> $request) async {
    return createPlan($call, await $request);
  }

  $async.Future<$0.CreatePlanResponse> createPlan(
      $grpc.ServiceCall call, $0.CreatePlanRequest request);

  $async.Future<$0.UpdatePlanResponse> updatePlan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpdatePlanRequest> $request) async {
    return updatePlan($call, await $request);
  }

  $async.Future<$0.UpdatePlanResponse> updatePlan(
      $grpc.ServiceCall call, $0.UpdatePlanRequest request);

  $async.Future<$0.ListSubscriptionsResponse> listSubscriptions_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListSubscriptionsRequest> $request) async {
    return listSubscriptions($call, await $request);
  }

  $async.Future<$0.ListSubscriptionsResponse> listSubscriptions(
      $grpc.ServiceCall call, $0.ListSubscriptionsRequest request);

  $async.Future<$0.RegisterPaymentResponse> registerPayment_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RegisterPaymentRequest> $request) async {
    return registerPayment($call, await $request);
  }

  $async.Future<$0.RegisterPaymentResponse> registerPayment(
      $grpc.ServiceCall call, $0.RegisterPaymentRequest request);

  $async.Future<$0.ListPaymentsResponse> listPayments_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListPaymentsRequest> $request) async {
    return listPayments($call, await $request);
  }

  $async.Future<$0.ListPaymentsResponse> listPayments(
      $grpc.ServiceCall call, $0.ListPaymentsRequest request);

  $async.Future<$0.ListVouchersResponse> listVouchers_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListVouchersRequest> $request) async {
    return listVouchers($call, await $request);
  }

  $async.Future<$0.ListVouchersResponse> listVouchers(
      $grpc.ServiceCall call, $0.ListVouchersRequest request);

  $async.Future<$0.CreateVoucherResponse> createVoucher_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateVoucherRequest> $request) async {
    return createVoucher($call, await $request);
  }

  $async.Future<$0.CreateVoucherResponse> createVoucher(
      $grpc.ServiceCall call, $0.CreateVoucherRequest request);

  $async.Future<$0.RevokeVoucherResponse> revokeVoucher_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RevokeVoucherRequest> $request) async {
    return revokeVoucher($call, await $request);
  }

  $async.Future<$0.RevokeVoucherResponse> revokeVoucher(
      $grpc.ServiceCall call, $0.RevokeVoucherRequest request);

  $async.Future<$0.ListVoucherRedemptionsResponse> listVoucherRedemptions_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListVoucherRedemptionsRequest> $request) async {
    return listVoucherRedemptions($call, await $request);
  }

  $async.Future<$0.ListVoucherRedemptionsResponse> listVoucherRedemptions(
      $grpc.ServiceCall call, $0.ListVoucherRedemptionsRequest request);

  $async.Future<$0.TestEvolutionConnectionResponse> testEvolutionConnection_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.TestEvolutionConnectionRequest> $request) async {
    return testEvolutionConnection($call, await $request);
  }

  $async.Future<$0.TestEvolutionConnectionResponse> testEvolutionConnection(
      $grpc.ServiceCall call, $0.TestEvolutionConnectionRequest request);

  $async.Future<$0.ListFeatureFlagsResponse> listFeatureFlags_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListFeatureFlagsRequest> $request) async {
    return listFeatureFlags($call, await $request);
  }

  $async.Future<$0.ListFeatureFlagsResponse> listFeatureFlags(
      $grpc.ServiceCall call, $0.ListFeatureFlagsRequest request);

  $async.Future<$0.SetFeatureFlagResponse> setFeatureFlag_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetFeatureFlagRequest> $request) async {
    return setFeatureFlag($call, await $request);
  }

  $async.Future<$0.SetFeatureFlagResponse> setFeatureFlag(
      $grpc.ServiceCall call, $0.SetFeatureFlagRequest request);

  $async.Future<$0.SetFeatureFlagOverrideResponse> setFeatureFlagOverride_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetFeatureFlagOverrideRequest> $request) async {
    return setFeatureFlagOverride($call, await $request);
  }

  $async.Future<$0.SetFeatureFlagOverrideResponse> setFeatureFlagOverride(
      $grpc.ServiceCall call, $0.SetFeatureFlagOverrideRequest request);

  $async.Future<$0.QueryAuditLogResponse> queryAuditLog_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.QueryAuditLogRequest> $request) async {
    return queryAuditLog($call, await $request);
  }

  $async.Future<$0.QueryAuditLogResponse> queryAuditLog(
      $grpc.ServiceCall call, $0.QueryAuditLogRequest request);

  $async.Future<$0.GetServiceHealthResponse> getServiceHealth_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetServiceHealthRequest> $request) async {
    return getServiceHealth($call, await $request);
  }

  $async.Future<$0.GetServiceHealthResponse> getServiceHealth(
      $grpc.ServiceCall call, $0.GetServiceHealthRequest request);

  $async.Future<$0.GetDashboardSummaryResponse> getDashboardSummary_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetDashboardSummaryRequest> $request) async {
    return getDashboardSummary($call, await $request);
  }

  $async.Future<$0.GetDashboardSummaryResponse> getDashboardSummary(
      $grpc.ServiceCall call, $0.GetDashboardSummaryRequest request);

  $async.Stream<$0.ExportTenantsCsvResponse> exportTenantsCsv_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ExportTenantsCsvRequest> $request) async* {
    yield* exportTenantsCsv($call, await $request);
  }

  $async.Stream<$0.ExportTenantsCsvResponse> exportTenantsCsv(
      $grpc.ServiceCall call, $0.ExportTenantsCsvRequest request);

  $async.Stream<$0.AtendimentoEvent> streamAtendimentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.StreamAtendimentosRequest> $request) async* {
    yield* streamAtendimentos($call, await $request);
  }

  $async.Stream<$0.AtendimentoEvent> streamAtendimentos(
      $grpc.ServiceCall call, $0.StreamAtendimentosRequest request);

  $async.Future<$0.ListAtendimentosResponse> listAtendimentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListAtendimentosRequest> $request) async {
    return listAtendimentos($call, await $request);
  }

  $async.Future<$0.ListAtendimentosResponse> listAtendimentos(
      $grpc.ServiceCall call, $0.ListAtendimentosRequest request);

  $async.Future<$0.GetThreadResponse> getThread_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetThreadRequest> $request) async {
    return getThread($call, await $request);
  }

  $async.Future<$0.GetThreadResponse> getThread(
      $grpc.ServiceCall call, $0.GetThreadRequest request);

  $async.Future<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MoveAtendimentoEtapaRequest> $request) async {
    return moveAtendimentoEtapa($call, await $request);
  }

  $async.Future<$0.MoveAtendimentoEtapaResponse> moveAtendimentoEtapa(
      $grpc.ServiceCall call, $0.MoveAtendimentoEtapaRequest request);

  $async.Future<$0.SendOutboundMessageResponse> sendOutboundMessage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SendOutboundMessageRequest> $request) async {
    return sendOutboundMessage($call, await $request);
  }

  $async.Future<$0.SendOutboundMessageResponse> sendOutboundMessage(
      $grpc.ServiceCall call, $0.SendOutboundMessageRequest request);

  $async.Future<$0.CreateInviteResponse> createInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateInviteRequest> $request) async {
    return createInvite($call, await $request);
  }

  $async.Future<$0.CreateInviteResponse> createInvite(
      $grpc.ServiceCall call, $0.CreateInviteRequest request);

  $async.Future<$0.AcceptInviteResponse> acceptInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.AcceptInviteRequest> $request) async {
    return acceptInvite($call, await $request);
  }

  $async.Future<$0.AcceptInviteResponse> acceptInvite(
      $grpc.ServiceCall call, $0.AcceptInviteRequest request);

  $async.Future<$0.ListInvitesResponse> listInvites_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ListInvitesRequest> $request) async {
    return listInvites($call, await $request);
  }

  $async.Future<$0.ListInvitesResponse> listInvites(
      $grpc.ServiceCall call, $0.ListInvitesRequest request);

  $async.Future<$0.RevokeInviteResponse> revokeInvite_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RevokeInviteRequest> $request) async {
    return revokeInvite($call, await $request);
  }

  $async.Future<$0.RevokeInviteResponse> revokeInvite(
      $grpc.ServiceCall call, $0.RevokeInviteRequest request);

  $async.Future<$0.ListTenantUsersResponse> listTenantUsers_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListTenantUsersRequest> $request) async {
    return listTenantUsers($call, await $request);
  }

  $async.Future<$0.ListTenantUsersResponse> listTenantUsers(
      $grpc.ServiceCall call, $0.ListTenantUsersRequest request);

  $async.Future<$0.UpdateTenantUserResponse> updateTenantUser_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateTenantUserRequest> $request) async {
    return updateTenantUser($call, await $request);
  }

  $async.Future<$0.UpdateTenantUserResponse> updateTenantUser(
      $grpc.ServiceCall call, $0.UpdateTenantUserRequest request);

  $async.Future<$0.GetTenantConfigResponse> getMyTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyTenantConfigRequest> $request) async {
    return getMyTenantConfig($call, await $request);
  }

  $async.Future<$0.GetTenantConfigResponse> getMyTenantConfig(
      $grpc.ServiceCall call, $0.GetMyTenantConfigRequest request);

  $async.Future<$0.UpdateTenantConfigResponse> updateMyTenantConfig_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyTenantConfigRequest> $request) async {
    return updateMyTenantConfig($call, await $request);
  }

  $async.Future<$0.UpdateTenantConfigResponse> updateMyTenantConfig(
      $grpc.ServiceCall call, $0.UpdateMyTenantConfigRequest request);

  $async.Future<$0.CreateMyWhatsappInstanceResponse>
      createMyWhatsappInstance_Pre($grpc.ServiceCall $call,
          $async.Future<$0.CreateMyWhatsappInstanceRequest> $request) async {
    return createMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.CreateMyWhatsappInstanceResponse> createMyWhatsappInstance(
      $grpc.ServiceCall call, $0.CreateMyWhatsappInstanceRequest request);

  $async.Future<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus_Pre($grpc.ServiceCall $call,
          $async.Future<$0.GetMyWhatsappInstanceStatusRequest> $request) async {
    return getMyWhatsappInstanceStatus($call, await $request);
  }

  $async.Future<$0.GetMyWhatsappInstanceStatusResponse>
      getMyWhatsappInstanceStatus($grpc.ServiceCall call,
          $0.GetMyWhatsappInstanceStatusRequest request);

  $async.Future<$0.CreateMyDepartamentoResponse> createMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyDepartamentoRequest> $request) async {
    return createMyDepartamento($call, await $request);
  }

  $async.Future<$0.CreateMyDepartamentoResponse> createMyDepartamento(
      $grpc.ServiceCall call, $0.CreateMyDepartamentoRequest request);

  $async.Future<$0.SetMyBotPersonaResponse> setMyBotPersona_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetMyBotPersonaRequest> $request) async {
    return setMyBotPersona($call, await $request);
  }

  $async.Future<$0.SetMyBotPersonaResponse> setMyBotPersona(
      $grpc.ServiceCall call, $0.SetMyBotPersonaRequest request);

  $async.Future<$0.SetOnboardingProgressResponse> setOnboardingProgress_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetOnboardingProgressRequest> $request) async {
    return setOnboardingProgress($call, await $request);
  }

  $async.Future<$0.SetOnboardingProgressResponse> setOnboardingProgress(
      $grpc.ServiceCall call, $0.SetOnboardingProgressRequest request);

  $async.Future<$0.GetMyOnboardingProgressResponse> getMyOnboardingProgress_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyOnboardingProgressRequest> $request) async {
    return getMyOnboardingProgress($call, await $request);
  }

  $async.Future<$0.GetMyOnboardingProgressResponse> getMyOnboardingProgress(
      $grpc.ServiceCall call, $0.GetMyOnboardingProgressRequest request);

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMyTreinamentoRequest> $request) async {
    return createMyTreinamento($call, await $request);
  }

  $async.Future<$0.MyTreinamentoResponse> createMyTreinamento(
      $grpc.ServiceCall call, $0.CreateMyTreinamentoRequest request);

  $async.Future<$0.ListMyTreinamentosResponse> listMyTreinamentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyTreinamentosRequest> $request) async {
    return listMyTreinamentos($call, await $request);
  }

  $async.Future<$0.ListMyTreinamentosResponse> listMyTreinamentos(
      $grpc.ServiceCall call, $0.ListMyTreinamentosRequest request);

  $async.Future<$0.MyTreinamentoResponse> getMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetMyTreinamentoRequest> $request) async {
    return getMyTreinamento($call, await $request);
  }

  $async.Future<$0.MyTreinamentoResponse> getMyTreinamento(
      $grpc.ServiceCall call, $0.GetMyTreinamentoRequest request);

  $async.Future<$0.SimpleOkResponse> finalizarMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.FinalizarMyTreinamentoRequest> $request) async {
    return finalizarMyTreinamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> finalizarMyTreinamento(
      $grpc.ServiceCall call, $0.FinalizarMyTreinamentoRequest request);

  $async.Future<$0.SimpleOkResponse> removerMyTreinamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RemoverMyTreinamentoRequest> $request) async {
    return removerMyTreinamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> removerMyTreinamento(
      $grpc.ServiceCall call, $0.RemoverMyTreinamentoRequest request);

  $async.Future<$0.ListMyWhatsappInstancesResponse> listMyWhatsappInstances_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyWhatsappInstancesRequest> $request) async {
    return listMyWhatsappInstances($call, await $request);
  }

  $async.Future<$0.ListMyWhatsappInstancesResponse> listMyWhatsappInstances(
      $grpc.ServiceCall call, $0.ListMyWhatsappInstancesRequest request);

  $async.Future<$0.SimpleOkResponse> reconnectMyWhatsappInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyWhatsappInstanceIdRequest> $request) async {
    return reconnectMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> reconnectMyWhatsappInstance(
      $grpc.ServiceCall call, $0.MyWhatsappInstanceIdRequest request);

  $async.Future<$0.SimpleOkResponse> deleteMyWhatsappInstance_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyWhatsappInstanceIdRequest> $request) async {
    return deleteMyWhatsappInstance($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> deleteMyWhatsappInstance(
      $grpc.ServiceCall call, $0.MyWhatsappInstanceIdRequest request);

  $async.Future<$0.ListMyDepartamentosResponse> listMyDepartamentos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyDepartamentosRequest> $request) async {
    return listMyDepartamentos($call, await $request);
  }

  $async.Future<$0.ListMyDepartamentosResponse> listMyDepartamentos(
      $grpc.ServiceCall call, $0.ListMyDepartamentosRequest request);

  $async.Future<$0.SimpleOkResponse> updateMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.UpdateMyDepartamentoRequest> $request) async {
    return updateMyDepartamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> updateMyDepartamento(
      $grpc.ServiceCall call, $0.UpdateMyDepartamentoRequest request);

  $async.Future<$0.SimpleOkResponse> desativarMyDepartamento_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MyDepartamentoIdRequest> $request) async {
    return desativarMyDepartamento($call, await $request);
  }

  $async.Future<$0.SimpleOkResponse> desativarMyDepartamento(
      $grpc.ServiceCall call, $0.MyDepartamentoIdRequest request);

  $async.Future<$0.ListMyAtendentesResponse> listMyAtendentes_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyAtendentesRequest> $request) async {
    return listMyAtendentes($call, await $request);
  }

  $async.Future<$0.ListMyAtendentesResponse> listMyAtendentes(
      $grpc.ServiceCall call, $0.ListMyAtendentesRequest request);

  $async.Future<$0.GetMyPainelResponse> getMyPainel_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetMyPainelRequest> $request) async {
    return getMyPainel($call, await $request);
  }

  $async.Future<$0.GetMyPainelResponse> getMyPainel(
      $grpc.ServiceCall call, $0.GetMyPainelRequest request);

  $async.Future<$0.ListMyContatosResponse> listMyContatos_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMyContatosRequest> $request) async {
    return listMyContatos($call, await $request);
  }

  $async.Future<$0.ListMyContatosResponse> listMyContatos(
      $grpc.ServiceCall call, $0.ListMyContatosRequest request);
}
