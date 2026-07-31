// This is a generated file - do not edit.
//
// Generated from queries/onboarding.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'onboarding.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'onboarding.pbenum.dart';

class CheckSlugRequest extends $pb.GeneratedMessage {
  factory CheckSlugRequest({
    $core.String? slug,
  }) {
    final result = create();
    if (slug != null) result.slug = slug;
    return result;
  }

  CheckSlugRequest._();

  factory CheckSlugRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CheckSlugRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckSlugRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'slug')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckSlugRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckSlugRequest copyWith(void Function(CheckSlugRequest) updates) =>
      super.copyWith((message) => updates(message as CheckSlugRequest))
          as CheckSlugRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CheckSlugRequest create() => CheckSlugRequest._();
  @$core.override
  CheckSlugRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CheckSlugRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckSlugRequest>(create);
  static CheckSlugRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get slug => $_getSZ(0);
  @$pb.TagNumber(1)
  set slug($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSlug() => $_has(0);
  @$pb.TagNumber(1)
  void clearSlug() => $_clearField(1);
}

class CheckSlugResponse extends $pb.GeneratedMessage {
  factory CheckSlugResponse({
    $core.bool? disponivel,
    $core.String? motivo,
    $core.String? mensagem,
  }) {
    final result = create();
    if (disponivel != null) result.disponivel = disponivel;
    if (motivo != null) result.motivo = motivo;
    if (mensagem != null) result.mensagem = mensagem;
    return result;
  }

  CheckSlugResponse._();

  factory CheckSlugResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CheckSlugResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CheckSlugResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'disponivel')
    ..aOS(2, _omitFieldNames ? '' : 'motivo')
    ..aOS(3, _omitFieldNames ? '' : 'mensagem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckSlugResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CheckSlugResponse copyWith(void Function(CheckSlugResponse) updates) =>
      super.copyWith((message) => updates(message as CheckSlugResponse))
          as CheckSlugResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CheckSlugResponse create() => CheckSlugResponse._();
  @$core.override
  CheckSlugResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CheckSlugResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CheckSlugResponse>(create);
  static CheckSlugResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get disponivel => $_getBF(0);
  @$pb.TagNumber(1)
  set disponivel($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDisponivel() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisponivel() => $_clearField(1);

  /// `em_uso`, `reservado` ou `invalido` — estável, para o cliente decidir o
  /// realce do campo sem casar strings de mensagem.
  @$pb.TagNumber(2)
  $core.String get motivo => $_getSZ(1);
  @$pb.TagNumber(2)
  set motivo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMotivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearMotivo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mensagem => $_getSZ(2);
  @$pb.TagNumber(3)
  set mensagem($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMensagem() => $_has(2);
  @$pb.TagNumber(3)
  void clearMensagem() => $_clearField(3);
}

class PublicPlan extends $pb.GeneratedMessage {
  factory PublicPlan({
    $core.int? id,
    $core.String? name,
    $core.String? description,
    $core.String? price,
    $core.int? maxInstances,
    $core.int? maxDepartments,
    $core.int? maxFluxos,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (price != null) result.price = price;
    if (maxInstances != null) result.maxInstances = maxInstances;
    if (maxDepartments != null) result.maxDepartments = maxDepartments;
    if (maxFluxos != null) result.maxFluxos = maxFluxos;
    return result;
  }

  PublicPlan._();

  factory PublicPlan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PublicPlan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PublicPlan',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'price')
    ..aI(5, _omitFieldNames ? '' : 'maxInstances')
    ..aI(6, _omitFieldNames ? '' : 'maxDepartments')
    ..aI(7, _omitFieldNames ? '' : 'maxFluxos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicPlan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PublicPlan copyWith(void Function(PublicPlan) updates) =>
      super.copyWith((message) => updates(message as PublicPlan)) as PublicPlan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PublicPlan create() => PublicPlan._();
  @$core.override
  PublicPlan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PublicPlan getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PublicPlan>(create);
  static PublicPlan? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  /// Vazio = preço ainda não definido (diferente de "gratuito").
  @$pb.TagNumber(4)
  $core.String get price => $_getSZ(3);
  @$pb.TagNumber(4)
  set price($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrice() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrice() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxInstances => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxInstances($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxInstances() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxInstances() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxDepartments => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxDepartments($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxDepartments() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxDepartments() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get maxFluxos => $_getIZ(6);
  @$pb.TagNumber(7)
  set maxFluxos($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxFluxos() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxFluxos() => $_clearField(7);
}

class ListPublicPlansRequest extends $pb.GeneratedMessage {
  factory ListPublicPlansRequest() => create();

  ListPublicPlansRequest._();

  factory ListPublicPlansRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPublicPlansRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPublicPlansRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPublicPlansRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPublicPlansRequest copyWith(
          void Function(ListPublicPlansRequest) updates) =>
      super.copyWith((message) => updates(message as ListPublicPlansRequest))
          as ListPublicPlansRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPublicPlansRequest create() => ListPublicPlansRequest._();
  @$core.override
  ListPublicPlansRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPublicPlansRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPublicPlansRequest>(create);
  static ListPublicPlansRequest? _defaultInstance;
}

class ListPublicPlansResponse extends $pb.GeneratedMessage {
  factory ListPublicPlansResponse({
    $core.Iterable<PublicPlan>? planos,
  }) {
    final result = create();
    if (planos != null) result.planos.addAll(planos);
    return result;
  }

  ListPublicPlansResponse._();

  factory ListPublicPlansResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPublicPlansResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPublicPlansResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<PublicPlan>(1, _omitFieldNames ? '' : 'planos',
        subBuilder: PublicPlan.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPublicPlansResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPublicPlansResponse copyWith(
          void Function(ListPublicPlansResponse) updates) =>
      super.copyWith((message) => updates(message as ListPublicPlansResponse))
          as ListPublicPlansResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPublicPlansResponse create() => ListPublicPlansResponse._();
  @$core.override
  ListPublicPlansResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPublicPlansResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPublicPlansResponse>(create);
  static ListPublicPlansResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PublicPlan> get planos => $_getList(0);
}

class StartSignupRequest extends $pb.GeneratedMessage {
  factory StartSignupRequest({
    $core.String? name,
    $core.String? slug,
    $core.String? email,
    $core.String? username,
    $core.String? password,
    $core.String? phone,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (slug != null) result.slug = slug;
    if (email != null) result.email = email;
    if (username != null) result.username = username;
    if (password != null) result.password = password;
    if (phone != null) result.phone = phone;
    return result;
  }

  StartSignupRequest._();

  factory StartSignupRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartSignupRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartSignupRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'slug')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'username')
    ..aOS(5, _omitFieldNames ? '' : 'password')
    ..aOS(6, _omitFieldNames ? '' : 'phone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartSignupRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartSignupRequest copyWith(void Function(StartSignupRequest) updates) =>
      super.copyWith((message) => updates(message as StartSignupRequest))
          as StartSignupRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartSignupRequest create() => StartSignupRequest._();
  @$core.override
  StartSignupRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartSignupRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartSignupRequest>(create);
  static StartSignupRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get slug => $_getSZ(1);
  @$pb.TagNumber(2)
  set slug($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSlug() => $_has(1);
  @$pb.TagNumber(2)
  void clearSlug() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  /// Vazio = usa o e-mail como nome de usuário.
  @$pb.TagNumber(4)
  $core.String get username => $_getSZ(3);
  @$pb.TagNumber(4)
  set username($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUsername() => $_has(3);
  @$pb.TagNumber(4)
  void clearUsername() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get password => $_getSZ(4);
  @$pb.TagNumber(5)
  set password($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPassword() => $_has(4);
  @$pb.TagNumber(5)
  void clearPassword() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get phone => $_getSZ(5);
  @$pb.TagNumber(6)
  set phone($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPhone() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhone() => $_clearField(6);
}

class StartSignupResponse extends $pb.GeneratedMessage {
  factory StartSignupResponse({
    $core.String? tenantId,
    $core.String? signupToken,
    $core.int? proximoPasso,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (signupToken != null) result.signupToken = signupToken;
    if (proximoPasso != null) result.proximoPasso = proximoPasso;
    return result;
  }

  StartSignupResponse._();

  factory StartSignupResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartSignupResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartSignupResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'signupToken')
    ..aI(3, _omitFieldNames ? '' : 'proximoPasso')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartSignupResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartSignupResponse copyWith(void Function(StartSignupResponse) updates) =>
      super.copyWith((message) => updates(message as StartSignupResponse))
          as StartSignupResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartSignupResponse create() => StartSignupResponse._();
  @$core.override
  StartSignupResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartSignupResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartSignupResponse>(create);
  static StartSignupResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  /// Autoriza os passos seguintes. Guardado pelo cliente até o fim do cadastro.
  @$pb.TagNumber(2)
  $core.String get signupToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set signupToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSignupToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignupToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get proximoPasso => $_getIZ(2);
  @$pb.TagNumber(3)
  set proximoPasso($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProximoPasso() => $_has(2);
  @$pb.TagNumber(3)
  void clearProximoPasso() => $_clearField(3);
}

class SelectPlanRequest extends $pb.GeneratedMessage {
  factory SelectPlanRequest({
    $core.String? tenantId,
    $core.String? signupToken,
    $core.int? planId,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (signupToken != null) result.signupToken = signupToken;
    if (planId != null) result.planId = planId;
    return result;
  }

  SelectPlanRequest._();

  factory SelectPlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SelectPlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SelectPlanRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'signupToken')
    ..aI(3, _omitFieldNames ? '' : 'planId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectPlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectPlanRequest copyWith(void Function(SelectPlanRequest) updates) =>
      super.copyWith((message) => updates(message as SelectPlanRequest))
          as SelectPlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SelectPlanRequest create() => SelectPlanRequest._();
  @$core.override
  SelectPlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SelectPlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SelectPlanRequest>(create);
  static SelectPlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get signupToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set signupToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSignupToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignupToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get planId => $_getIZ(2);
  @$pb.TagNumber(3)
  set planId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlanId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlanId() => $_clearField(3);
}

class SelectPlanResponse extends $pb.GeneratedMessage {
  factory SelectPlanResponse({
    $core.int? proximoPasso,
  }) {
    final result = create();
    if (proximoPasso != null) result.proximoPasso = proximoPasso;
    return result;
  }

  SelectPlanResponse._();

  factory SelectPlanResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SelectPlanResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SelectPlanResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'proximoPasso')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectPlanResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectPlanResponse copyWith(void Function(SelectPlanResponse) updates) =>
      super.copyWith((message) => updates(message as SelectPlanResponse))
          as SelectPlanResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SelectPlanResponse create() => SelectPlanResponse._();
  @$core.override
  SelectPlanResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SelectPlanResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SelectPlanResponse>(create);
  static SelectPlanResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get proximoPasso => $_getIZ(0);
  @$pb.TagNumber(1)
  set proximoPasso($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProximoPasso() => $_has(0);
  @$pb.TagNumber(1)
  void clearProximoPasso() => $_clearField(1);
}

/// Tudo que o cliente precisa para desenhar a opção — sem conhecer provedor
/// algum por nome. É isto que faz a tela sobreviver à entrada de um gateway.
class PaymentProvider extends $pb.GeneratedMessage {
  factory PaymentProvider({
    $core.String? id,
    $core.String? rotulo,
    $core.String? instrucao,
    $core.bool? requerCredencial,
    $core.String? rotuloCredencial,
    ModoConfirmacao? modo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (rotulo != null) result.rotulo = rotulo;
    if (instrucao != null) result.instrucao = instrucao;
    if (requerCredencial != null) result.requerCredencial = requerCredencial;
    if (rotuloCredencial != null) result.rotuloCredencial = rotuloCredencial;
    if (modo != null) result.modo = modo;
    return result;
  }

  PaymentProvider._();

  factory PaymentProvider.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PaymentProvider.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PaymentProvider',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'rotulo')
    ..aOS(3, _omitFieldNames ? '' : 'instrucao')
    ..aOB(4, _omitFieldNames ? '' : 'requerCredencial')
    ..aOS(5, _omitFieldNames ? '' : 'rotuloCredencial')
    ..aE<ModoConfirmacao>(6, _omitFieldNames ? '' : 'modo',
        enumValues: ModoConfirmacao.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PaymentProvider clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PaymentProvider copyWith(void Function(PaymentProvider) updates) =>
      super.copyWith((message) => updates(message as PaymentProvider))
          as PaymentProvider;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PaymentProvider create() => PaymentProvider._();
  @$core.override
  PaymentProvider createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PaymentProvider getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PaymentProvider>(create);
  static PaymentProvider? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get rotulo => $_getSZ(1);
  @$pb.TagNumber(2)
  set rotulo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRotulo() => $_has(1);
  @$pb.TagNumber(2)
  void clearRotulo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get instrucao => $_getSZ(2);
  @$pb.TagNumber(3)
  set instrucao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInstrucao() => $_has(2);
  @$pb.TagNumber(3)
  void clearInstrucao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get requerCredencial => $_getBF(3);
  @$pb.TagNumber(4)
  set requerCredencial($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequerCredencial() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequerCredencial() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get rotuloCredencial => $_getSZ(4);
  @$pb.TagNumber(5)
  set rotuloCredencial($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRotuloCredencial() => $_has(4);
  @$pb.TagNumber(5)
  void clearRotuloCredencial() => $_clearField(5);

  @$pb.TagNumber(6)
  ModoConfirmacao get modo => $_getN(5);
  @$pb.TagNumber(6)
  set modo(ModoConfirmacao value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasModo() => $_has(5);
  @$pb.TagNumber(6)
  void clearModo() => $_clearField(6);
}

class ListPaymentProvidersRequest extends $pb.GeneratedMessage {
  factory ListPaymentProvidersRequest() => create();

  ListPaymentProvidersRequest._();

  factory ListPaymentProvidersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPaymentProvidersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPaymentProvidersRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentProvidersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentProvidersRequest copyWith(
          void Function(ListPaymentProvidersRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListPaymentProvidersRequest))
          as ListPaymentProvidersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPaymentProvidersRequest create() =>
      ListPaymentProvidersRequest._();
  @$core.override
  ListPaymentProvidersRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPaymentProvidersRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPaymentProvidersRequest>(create);
  static ListPaymentProvidersRequest? _defaultInstance;
}

class ListPaymentProvidersResponse extends $pb.GeneratedMessage {
  factory ListPaymentProvidersResponse({
    $core.Iterable<PaymentProvider>? provedores,
  }) {
    final result = create();
    if (provedores != null) result.provedores.addAll(provedores);
    return result;
  }

  ListPaymentProvidersResponse._();

  factory ListPaymentProvidersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPaymentProvidersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPaymentProvidersResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<PaymentProvider>(1, _omitFieldNames ? '' : 'provedores',
        subBuilder: PaymentProvider.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentProvidersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentProvidersResponse copyWith(
          void Function(ListPaymentProvidersResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListPaymentProvidersResponse))
          as ListPaymentProvidersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPaymentProvidersResponse create() =>
      ListPaymentProvidersResponse._();
  @$core.override
  ListPaymentProvidersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPaymentProvidersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPaymentProvidersResponse>(create);
  static ListPaymentProvidersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PaymentProvider> get provedores => $_getList(0);
}

class ConfirmPaymentRequest extends $pb.GeneratedMessage {
  factory ConfirmPaymentRequest({
    $core.String? tenantId,
    $core.String? signupToken,
    $core.String? provedor,
    $core.String? credencial,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (signupToken != null) result.signupToken = signupToken;
    if (provedor != null) result.provedor = provedor;
    if (credencial != null) result.credencial = credencial;
    return result;
  }

  ConfirmPaymentRequest._();

  factory ConfirmPaymentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfirmPaymentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmPaymentRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'signupToken')
    ..aOS(3, _omitFieldNames ? '' : 'provedor')
    ..aOS(4, _omitFieldNames ? '' : 'credencial')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPaymentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPaymentRequest copyWith(
          void Function(ConfirmPaymentRequest) updates) =>
      super.copyWith((message) => updates(message as ConfirmPaymentRequest))
          as ConfirmPaymentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmPaymentRequest create() => ConfirmPaymentRequest._();
  @$core.override
  ConfirmPaymentRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfirmPaymentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmPaymentRequest>(create);
  static ConfirmPaymentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get signupToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set signupToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSignupToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignupToken() => $_clearField(2);

  /// `id` de um PaymentProvider (ex.: `voucher`).
  @$pb.TagNumber(3)
  $core.String get provedor => $_getSZ(2);
  @$pb.TagNumber(3)
  set provedor($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProvedor() => $_has(2);
  @$pb.TagNumber(3)
  void clearProvedor() => $_clearField(3);

  /// O que o usuário digitou, quando o provedor pede algo (o código do voucher).
  @$pb.TagNumber(4)
  $core.String get credencial => $_getSZ(3);
  @$pb.TagNumber(4)
  set credencial($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCredencial() => $_has(3);
  @$pb.TagNumber(4)
  void clearCredencial() => $_clearField(4);
}

class ConfirmPaymentResponse extends $pb.GeneratedMessage {
  factory ConfirmPaymentResponse({
    $core.bool? confirmado,
    $core.String? urlRedirecionamento,
    $core.String? motivo,
    $core.String? mensagem,
  }) {
    final result = create();
    if (confirmado != null) result.confirmado = confirmado;
    if (urlRedirecionamento != null)
      result.urlRedirecionamento = urlRedirecionamento;
    if (motivo != null) result.motivo = motivo;
    if (mensagem != null) result.mensagem = mensagem;
    return result;
  }

  ConfirmPaymentResponse._();

  factory ConfirmPaymentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfirmPaymentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmPaymentResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'confirmado')
    ..aOS(2, _omitFieldNames ? '' : 'urlRedirecionamento')
    ..aOS(3, _omitFieldNames ? '' : 'motivo')
    ..aOS(4, _omitFieldNames ? '' : 'mensagem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPaymentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmPaymentResponse copyWith(
          void Function(ConfirmPaymentResponse) updates) =>
      super.copyWith((message) => updates(message as ConfirmPaymentResponse))
          as ConfirmPaymentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmPaymentResponse create() => ConfirmPaymentResponse._();
  @$core.override
  ConfirmPaymentResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfirmPaymentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmPaymentResponse>(create);
  static ConfirmPaymentResponse? _defaultInstance;

  /// true = assinatura ativa; o cliente pode seguir para o login.
  @$pb.TagNumber(1)
  $core.bool get confirmado => $_getBF(0);
  @$pb.TagNumber(1)
  set confirmado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfirmado() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfirmado() => $_clearField(1);

  /// Preenchida quando o provedor exige concluir o pagamento fora do app.
  @$pb.TagNumber(2)
  $core.String get urlRedirecionamento => $_getSZ(1);
  @$pb.TagNumber(2)
  set urlRedirecionamento($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrlRedirecionamento() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrlRedirecionamento() => $_clearField(2);

  /// false + mensagem = recusa de negócio (código inválido, expirado...).
  @$pb.TagNumber(3)
  $core.String get motivo => $_getSZ(2);
  @$pb.TagNumber(3)
  set motivo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMotivo() => $_has(2);
  @$pb.TagNumber(3)
  void clearMotivo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get mensagem => $_getSZ(3);
  @$pb.TagNumber(4)
  set mensagem($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMensagem() => $_has(3);
  @$pb.TagNumber(4)
  void clearMensagem() => $_clearField(4);
}

class GetSignupStatusRequest extends $pb.GeneratedMessage {
  factory GetSignupStatusRequest({
    $core.String? tenantId,
    $core.String? signupToken,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (signupToken != null) result.signupToken = signupToken;
    return result;
  }

  GetSignupStatusRequest._();

  factory GetSignupStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetSignupStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSignupStatusRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'signupToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSignupStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSignupStatusRequest copyWith(
          void Function(GetSignupStatusRequest) updates) =>
      super.copyWith((message) => updates(message as GetSignupStatusRequest))
          as GetSignupStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSignupStatusRequest create() => GetSignupStatusRequest._();
  @$core.override
  GetSignupStatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetSignupStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSignupStatusRequest>(create);
  static GetSignupStatusRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get signupToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set signupToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSignupToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignupToken() => $_clearField(2);
}

class GetSignupStatusResponse extends $pb.GeneratedMessage {
  factory GetSignupStatusResponse({
    $core.int? passo,
    $core.int? planId,
    $core.String? statusAssinatura,
    $core.bool? tenantAtivo,
    $fixnum.Int64? periodoFim,
  }) {
    final result = create();
    if (passo != null) result.passo = passo;
    if (planId != null) result.planId = planId;
    if (statusAssinatura != null) result.statusAssinatura = statusAssinatura;
    if (tenantAtivo != null) result.tenantAtivo = tenantAtivo;
    if (periodoFim != null) result.periodoFim = periodoFim;
    return result;
  }

  GetSignupStatusResponse._();

  factory GetSignupStatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetSignupStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSignupStatusResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'passo')
    ..aI(2, _omitFieldNames ? '' : 'planId')
    ..aOS(3, _omitFieldNames ? '' : 'statusAssinatura')
    ..aOB(4, _omitFieldNames ? '' : 'tenantAtivo')
    ..aInt64(5, _omitFieldNames ? '' : 'periodoFim')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSignupStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSignupStatusResponse copyWith(
          void Function(GetSignupStatusResponse) updates) =>
      super.copyWith((message) => updates(message as GetSignupStatusResponse))
          as GetSignupStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSignupStatusResponse create() => GetSignupStatusResponse._();
  @$core.override
  GetSignupStatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetSignupStatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSignupStatusResponse>(create);
  static GetSignupStatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get passo => $_getIZ(0);
  @$pb.TagNumber(1)
  set passo($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasso() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasso() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get planId => $_getIZ(1);
  @$pb.TagNumber(2)
  set planId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPlanId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlanId() => $_clearField(2);

  /// Mesmo vocabulário de tenants_subscription.status: PENDING_PAYMENT, ACTIVE...
  @$pb.TagNumber(3)
  $core.String get statusAssinatura => $_getSZ(2);
  @$pb.TagNumber(3)
  set statusAssinatura($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatusAssinatura() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatusAssinatura() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get tenantAtivo => $_getBF(3);
  @$pb.TagNumber(4)
  set tenantAtivo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTenantAtivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearTenantAtivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get periodoFim => $_getI64(4);
  @$pb.TagNumber(5)
  set periodoFim($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPeriodoFim() => $_has(4);
  @$pb.TagNumber(5)
  void clearPeriodoFim() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
