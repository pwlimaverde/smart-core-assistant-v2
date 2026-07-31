// This is a generated file - do not edit.
//
// Generated from queries/onboarding.proto.

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

import 'onboarding.pb.dart' as $0;

export 'onboarding.pb.dart';

@$pb.GrpcServiceName('smartcore.contracts.queries.OnboardingService')
class OnboardingServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  OnboardingServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.CheckSlugResponse> checkSlug(
    $0.CheckSlugRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$checkSlug, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListPublicPlansResponse> listPublicPlans(
    $0.ListPublicPlansRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPublicPlans, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListPaymentProvidersResponse> listPaymentProviders(
    $0.ListPaymentProvidersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listPaymentProviders, request, options: options);
  }

  $grpc.ResponseFuture<$0.StartSignupResponse> startSignup(
    $0.StartSignupRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$startSignup, request, options: options);
  }

  $grpc.ResponseFuture<$0.SelectPlanResponse> selectPlan(
    $0.SelectPlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$selectPlan, request, options: options);
  }

  $grpc.ResponseFuture<$0.ConfirmPaymentResponse> confirmPayment(
    $0.ConfirmPaymentRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$confirmPayment, request, options: options);
  }

  $grpc.ResponseFuture<$0.GetSignupStatusResponse> getSignupStatus(
    $0.GetSignupStatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getSignupStatus, request, options: options);
  }

  // method descriptors

  static final _$checkSlug =
      $grpc.ClientMethod<$0.CheckSlugRequest, $0.CheckSlugResponse>(
          '/smartcore.contracts.queries.OnboardingService/CheckSlug',
          ($0.CheckSlugRequest value) => value.writeToBuffer(),
          $0.CheckSlugResponse.fromBuffer);
  static final _$listPublicPlans =
      $grpc.ClientMethod<$0.ListPublicPlansRequest, $0.ListPublicPlansResponse>(
          '/smartcore.contracts.queries.OnboardingService/ListPublicPlans',
          ($0.ListPublicPlansRequest value) => value.writeToBuffer(),
          $0.ListPublicPlansResponse.fromBuffer);
  static final _$listPaymentProviders = $grpc.ClientMethod<
          $0.ListPaymentProvidersRequest, $0.ListPaymentProvidersResponse>(
      '/smartcore.contracts.queries.OnboardingService/ListPaymentProviders',
      ($0.ListPaymentProvidersRequest value) => value.writeToBuffer(),
      $0.ListPaymentProvidersResponse.fromBuffer);
  static final _$startSignup =
      $grpc.ClientMethod<$0.StartSignupRequest, $0.StartSignupResponse>(
          '/smartcore.contracts.queries.OnboardingService/StartSignup',
          ($0.StartSignupRequest value) => value.writeToBuffer(),
          $0.StartSignupResponse.fromBuffer);
  static final _$selectPlan =
      $grpc.ClientMethod<$0.SelectPlanRequest, $0.SelectPlanResponse>(
          '/smartcore.contracts.queries.OnboardingService/SelectPlan',
          ($0.SelectPlanRequest value) => value.writeToBuffer(),
          $0.SelectPlanResponse.fromBuffer);
  static final _$confirmPayment =
      $grpc.ClientMethod<$0.ConfirmPaymentRequest, $0.ConfirmPaymentResponse>(
          '/smartcore.contracts.queries.OnboardingService/ConfirmPayment',
          ($0.ConfirmPaymentRequest value) => value.writeToBuffer(),
          $0.ConfirmPaymentResponse.fromBuffer);
  static final _$getSignupStatus =
      $grpc.ClientMethod<$0.GetSignupStatusRequest, $0.GetSignupStatusResponse>(
          '/smartcore.contracts.queries.OnboardingService/GetSignupStatus',
          ($0.GetSignupStatusRequest value) => value.writeToBuffer(),
          $0.GetSignupStatusResponse.fromBuffer);
}

@$pb.GrpcServiceName('smartcore.contracts.queries.OnboardingService')
abstract class OnboardingServiceBase extends $grpc.Service {
  $core.String get $name => 'smartcore.contracts.queries.OnboardingService';

  OnboardingServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.CheckSlugRequest, $0.CheckSlugResponse>(
        'CheckSlug',
        checkSlug_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CheckSlugRequest.fromBuffer(value),
        ($0.CheckSlugResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListPublicPlansRequest,
            $0.ListPublicPlansResponse>(
        'ListPublicPlans',
        listPublicPlans_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListPublicPlansRequest.fromBuffer(value),
        ($0.ListPublicPlansResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListPaymentProvidersRequest,
            $0.ListPaymentProvidersResponse>(
        'ListPaymentProviders',
        listPaymentProviders_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListPaymentProvidersRequest.fromBuffer(value),
        ($0.ListPaymentProvidersResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.StartSignupRequest, $0.StartSignupResponse>(
            'StartSignup',
            startSignup_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.StartSignupRequest.fromBuffer(value),
            ($0.StartSignupResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SelectPlanRequest, $0.SelectPlanResponse>(
        'SelectPlan',
        selectPlan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SelectPlanRequest.fromBuffer(value),
        ($0.SelectPlanResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ConfirmPaymentRequest,
            $0.ConfirmPaymentResponse>(
        'ConfirmPayment',
        confirmPayment_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ConfirmPaymentRequest.fromBuffer(value),
        ($0.ConfirmPaymentResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetSignupStatusRequest,
            $0.GetSignupStatusResponse>(
        'GetSignupStatus',
        getSignupStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetSignupStatusRequest.fromBuffer(value),
        ($0.GetSignupStatusResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.CheckSlugResponse> checkSlug_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CheckSlugRequest> $request) async {
    return checkSlug($call, await $request);
  }

  $async.Future<$0.CheckSlugResponse> checkSlug(
      $grpc.ServiceCall call, $0.CheckSlugRequest request);

  $async.Future<$0.ListPublicPlansResponse> listPublicPlans_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListPublicPlansRequest> $request) async {
    return listPublicPlans($call, await $request);
  }

  $async.Future<$0.ListPublicPlansResponse> listPublicPlans(
      $grpc.ServiceCall call, $0.ListPublicPlansRequest request);

  $async.Future<$0.ListPaymentProvidersResponse> listPaymentProviders_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListPaymentProvidersRequest> $request) async {
    return listPaymentProviders($call, await $request);
  }

  $async.Future<$0.ListPaymentProvidersResponse> listPaymentProviders(
      $grpc.ServiceCall call, $0.ListPaymentProvidersRequest request);

  $async.Future<$0.StartSignupResponse> startSignup_Pre($grpc.ServiceCall $call,
      $async.Future<$0.StartSignupRequest> $request) async {
    return startSignup($call, await $request);
  }

  $async.Future<$0.StartSignupResponse> startSignup(
      $grpc.ServiceCall call, $0.StartSignupRequest request);

  $async.Future<$0.SelectPlanResponse> selectPlan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SelectPlanRequest> $request) async {
    return selectPlan($call, await $request);
  }

  $async.Future<$0.SelectPlanResponse> selectPlan(
      $grpc.ServiceCall call, $0.SelectPlanRequest request);

  $async.Future<$0.ConfirmPaymentResponse> confirmPayment_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ConfirmPaymentRequest> $request) async {
    return confirmPayment($call, await $request);
  }

  $async.Future<$0.ConfirmPaymentResponse> confirmPayment(
      $grpc.ServiceCall call, $0.ConfirmPaymentRequest request);

  $async.Future<$0.GetSignupStatusResponse> getSignupStatus_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.GetSignupStatusRequest> $request) async {
    return getSignupStatus($call, await $request);
  }

  $async.Future<$0.GetSignupStatusResponse> getSignupStatus(
      $grpc.ServiceCall call, $0.GetSignupStatusRequest request);
}
