// This is a generated file - do not edit.
//
// Generated from admin.proto.

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
}
