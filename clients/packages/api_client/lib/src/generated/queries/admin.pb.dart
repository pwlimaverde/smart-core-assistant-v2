// This is a generated file - do not edit.
//
// Generated from queries/admin.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// --- Configurações Globais (CoreSettings) ---
class CoreSetting extends $pb.GeneratedMessage {
  factory CoreSetting({
    $core.String? key,
    $core.String? value,
    $core.bool? encrypted,
    $core.String? description,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    if (encrypted != null) result.encrypted = encrypted;
    if (description != null) result.description = description;
    return result;
  }

  CoreSetting._();

  factory CoreSetting.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CoreSetting.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CoreSetting',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..aOB(3, _omitFieldNames ? '' : 'encrypted')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CoreSetting clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CoreSetting copyWith(void Function(CoreSetting) updates) =>
      super.copyWith((message) => updates(message as CoreSetting))
          as CoreSetting;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CoreSetting create() => CoreSetting._();
  @$core.override
  CoreSetting createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CoreSetting getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CoreSetting>(create);
  static CoreSetting? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get encrypted => $_getBF(2);
  @$pb.TagNumber(3)
  set encrypted($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEncrypted() => $_has(2);
  @$pb.TagNumber(3)
  void clearEncrypted() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);
}

class ListCoreSettingsRequest extends $pb.GeneratedMessage {
  factory ListCoreSettingsRequest() => create();

  ListCoreSettingsRequest._();

  factory ListCoreSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListCoreSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListCoreSettingsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListCoreSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListCoreSettingsRequest copyWith(
          void Function(ListCoreSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as ListCoreSettingsRequest))
          as ListCoreSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListCoreSettingsRequest create() => ListCoreSettingsRequest._();
  @$core.override
  ListCoreSettingsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListCoreSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListCoreSettingsRequest>(create);
  static ListCoreSettingsRequest? _defaultInstance;
}

class ListCoreSettingsResponse extends $pb.GeneratedMessage {
  factory ListCoreSettingsResponse({
    $core.Iterable<CoreSetting>? settings,
  }) {
    final result = create();
    if (settings != null) result.settings.addAll(settings);
    return result;
  }

  ListCoreSettingsResponse._();

  factory ListCoreSettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListCoreSettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListCoreSettingsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<CoreSetting>(1, _omitFieldNames ? '' : 'settings',
        subBuilder: CoreSetting.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListCoreSettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListCoreSettingsResponse copyWith(
          void Function(ListCoreSettingsResponse) updates) =>
      super.copyWith((message) => updates(message as ListCoreSettingsResponse))
          as ListCoreSettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListCoreSettingsResponse create() => ListCoreSettingsResponse._();
  @$core.override
  ListCoreSettingsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListCoreSettingsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListCoreSettingsResponse>(create);
  static ListCoreSettingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<CoreSetting> get settings => $_getList(0);
}

class UpsertCoreSettingRequest extends $pb.GeneratedMessage {
  factory UpsertCoreSettingRequest({
    $core.String? key,
    $core.String? value,
    $core.bool? encrypted,
    $core.String? description,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    if (encrypted != null) result.encrypted = encrypted;
    if (description != null) result.description = description;
    return result;
  }

  UpsertCoreSettingRequest._();

  factory UpsertCoreSettingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpsertCoreSettingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpsertCoreSettingRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..aOB(3, _omitFieldNames ? '' : 'encrypted')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertCoreSettingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertCoreSettingRequest copyWith(
          void Function(UpsertCoreSettingRequest) updates) =>
      super.copyWith((message) => updates(message as UpsertCoreSettingRequest))
          as UpsertCoreSettingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpsertCoreSettingRequest create() => UpsertCoreSettingRequest._();
  @$core.override
  UpsertCoreSettingRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpsertCoreSettingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpsertCoreSettingRequest>(create);
  static UpsertCoreSettingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get encrypted => $_getBF(2);
  @$pb.TagNumber(3)
  set encrypted($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEncrypted() => $_has(2);
  @$pb.TagNumber(3)
  void clearEncrypted() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);
}

class UpsertCoreSettingResponse extends $pb.GeneratedMessage {
  factory UpsertCoreSettingResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  UpsertCoreSettingResponse._();

  factory UpsertCoreSettingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpsertCoreSettingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpsertCoreSettingResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertCoreSettingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertCoreSettingResponse copyWith(
          void Function(UpsertCoreSettingResponse) updates) =>
      super.copyWith((message) => updates(message as UpsertCoreSettingResponse))
          as UpsertCoreSettingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpsertCoreSettingResponse create() => UpsertCoreSettingResponse._();
  @$core.override
  UpsertCoreSettingResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpsertCoreSettingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpsertCoreSettingResponse>(create);
  static UpsertCoreSettingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class DeleteCoreSettingRequest extends $pb.GeneratedMessage {
  factory DeleteCoreSettingRequest({
    $core.String? key,
  }) {
    final result = create();
    if (key != null) result.key = key;
    return result;
  }

  DeleteCoreSettingRequest._();

  factory DeleteCoreSettingRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeleteCoreSettingRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteCoreSettingRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCoreSettingRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCoreSettingRequest copyWith(
          void Function(DeleteCoreSettingRequest) updates) =>
      super.copyWith((message) => updates(message as DeleteCoreSettingRequest))
          as DeleteCoreSettingRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteCoreSettingRequest create() => DeleteCoreSettingRequest._();
  @$core.override
  DeleteCoreSettingRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeleteCoreSettingRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteCoreSettingRequest>(create);
  static DeleteCoreSettingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);
}

class DeleteCoreSettingResponse extends $pb.GeneratedMessage {
  factory DeleteCoreSettingResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  DeleteCoreSettingResponse._();

  factory DeleteCoreSettingResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeleteCoreSettingResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteCoreSettingResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCoreSettingResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCoreSettingResponse copyWith(
          void Function(DeleteCoreSettingResponse) updates) =>
      super.copyWith((message) => updates(message as DeleteCoreSettingResponse))
          as DeleteCoreSettingResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteCoreSettingResponse create() => DeleteCoreSettingResponse._();
  @$core.override
  DeleteCoreSettingResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeleteCoreSettingResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteCoreSettingResponse>(create);
  static DeleteCoreSettingResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

/// --- Entrada de Chave de API ---
class ApiKeyEntry extends $pb.GeneratedMessage {
  factory ApiKeyEntry({
    $core.String? key,
    $core.String? value,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    return result;
  }

  ApiKeyEntry._();

  factory ApiKeyEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ApiKeyEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApiKeyEntry',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiKeyEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiKeyEntry copyWith(void Function(ApiKeyEntry) updates) =>
      super.copyWith((message) => updates(message as ApiKeyEntry))
          as ApiKeyEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ApiKeyEntry create() => ApiKeyEntry._();
  @$core.override
  ApiKeyEntry createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ApiKeyEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ApiKeyEntry>(create);
  static ApiKeyEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

/// --- Configurações de Tenant (TenantConfig) ---
class GetTenantConfigRequest extends $pb.GeneratedMessage {
  factory GetTenantConfigRequest({
    $core.String? tenantId,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  GetTenantConfigRequest._();

  factory GetTenantConfigRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetTenantConfigRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTenantConfigRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantConfigRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantConfigRequest copyWith(
          void Function(GetTenantConfigRequest) updates) =>
      super.copyWith((message) => updates(message as GetTenantConfigRequest))
          as GetTenantConfigRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetTenantConfigRequest create() => GetTenantConfigRequest._();
  @$core.override
  GetTenantConfigRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetTenantConfigRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTenantConfigRequest>(create);
  static GetTenantConfigRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);
}

class GetTenantConfigResponse extends $pb.GeneratedMessage {
  factory GetTenantConfigResponse({
    $core.String? dadosEmpresa,
    $core.String? personaBot,
    $core.String? botAgentName,
    $core.String? msgFallback,
    $core.String? msgSemInfo,
    $core.String? msgTransferencia,
    $core.String? llmClass,
    $core.String? model,
    $core.String? llmTemperature,
    $core.String? transcriptionProvider,
    $core.String? transcriptionModel,
    $core.String? visionProvider,
    $core.String? visionModel,
    $core.String? embeddingsClass,
    $core.String? embeddingsModel,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.String? similarityThreshold,
    $core.String? vectorDistanceThreshold,
    $core.Iterable<ApiKeyEntry>? apiKeys,
  }) {
    final result = create();
    if (dadosEmpresa != null) result.dadosEmpresa = dadosEmpresa;
    if (personaBot != null) result.personaBot = personaBot;
    if (botAgentName != null) result.botAgentName = botAgentName;
    if (msgFallback != null) result.msgFallback = msgFallback;
    if (msgSemInfo != null) result.msgSemInfo = msgSemInfo;
    if (msgTransferencia != null) result.msgTransferencia = msgTransferencia;
    if (llmClass != null) result.llmClass = llmClass;
    if (model != null) result.model = model;
    if (llmTemperature != null) result.llmTemperature = llmTemperature;
    if (transcriptionProvider != null)
      result.transcriptionProvider = transcriptionProvider;
    if (transcriptionModel != null)
      result.transcriptionModel = transcriptionModel;
    if (visionProvider != null) result.visionProvider = visionProvider;
    if (visionModel != null) result.visionModel = visionModel;
    if (embeddingsClass != null) result.embeddingsClass = embeddingsClass;
    if (embeddingsModel != null) result.embeddingsModel = embeddingsModel;
    if (chunkSize != null) result.chunkSize = chunkSize;
    if (chunkOverlap != null) result.chunkOverlap = chunkOverlap;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (vectorDistanceThreshold != null)
      result.vectorDistanceThreshold = vectorDistanceThreshold;
    if (apiKeys != null) result.apiKeys.addAll(apiKeys);
    return result;
  }

  GetTenantConfigResponse._();

  factory GetTenantConfigResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetTenantConfigResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTenantConfigResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dadosEmpresa')
    ..aOS(2, _omitFieldNames ? '' : 'personaBot')
    ..aOS(3, _omitFieldNames ? '' : 'botAgentName')
    ..aOS(4, _omitFieldNames ? '' : 'msgFallback')
    ..aOS(5, _omitFieldNames ? '' : 'msgSemInfo')
    ..aOS(6, _omitFieldNames ? '' : 'msgTransferencia')
    ..aOS(7, _omitFieldNames ? '' : 'llmClass')
    ..aOS(8, _omitFieldNames ? '' : 'model')
    ..aOS(9, _omitFieldNames ? '' : 'llmTemperature')
    ..aOS(10, _omitFieldNames ? '' : 'transcriptionProvider')
    ..aOS(11, _omitFieldNames ? '' : 'transcriptionModel')
    ..aOS(12, _omitFieldNames ? '' : 'visionProvider')
    ..aOS(13, _omitFieldNames ? '' : 'visionModel')
    ..aOS(14, _omitFieldNames ? '' : 'embeddingsClass')
    ..aOS(15, _omitFieldNames ? '' : 'embeddingsModel')
    ..aI(16, _omitFieldNames ? '' : 'chunkSize')
    ..aI(17, _omitFieldNames ? '' : 'chunkOverlap')
    ..aOS(18, _omitFieldNames ? '' : 'similarityThreshold')
    ..aOS(19, _omitFieldNames ? '' : 'vectorDistanceThreshold')
    ..pPM<ApiKeyEntry>(20, _omitFieldNames ? '' : 'apiKeys',
        subBuilder: ApiKeyEntry.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantConfigResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantConfigResponse copyWith(
          void Function(GetTenantConfigResponse) updates) =>
      super.copyWith((message) => updates(message as GetTenantConfigResponse))
          as GetTenantConfigResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetTenantConfigResponse create() => GetTenantConfigResponse._();
  @$core.override
  GetTenantConfigResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetTenantConfigResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTenantConfigResponse>(create);
  static GetTenantConfigResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get dadosEmpresa => $_getSZ(0);
  @$pb.TagNumber(1)
  set dadosEmpresa($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDadosEmpresa() => $_has(0);
  @$pb.TagNumber(1)
  void clearDadosEmpresa() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get personaBot => $_getSZ(1);
  @$pb.TagNumber(2)
  set personaBot($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPersonaBot() => $_has(1);
  @$pb.TagNumber(2)
  void clearPersonaBot() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get botAgentName => $_getSZ(2);
  @$pb.TagNumber(3)
  set botAgentName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBotAgentName() => $_has(2);
  @$pb.TagNumber(3)
  void clearBotAgentName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get msgFallback => $_getSZ(3);
  @$pb.TagNumber(4)
  set msgFallback($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMsgFallback() => $_has(3);
  @$pb.TagNumber(4)
  void clearMsgFallback() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get msgSemInfo => $_getSZ(4);
  @$pb.TagNumber(5)
  set msgSemInfo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMsgSemInfo() => $_has(4);
  @$pb.TagNumber(5)
  void clearMsgSemInfo() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get msgTransferencia => $_getSZ(5);
  @$pb.TagNumber(6)
  set msgTransferencia($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMsgTransferencia() => $_has(5);
  @$pb.TagNumber(6)
  void clearMsgTransferencia() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get llmClass => $_getSZ(6);
  @$pb.TagNumber(7)
  set llmClass($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLlmClass() => $_has(6);
  @$pb.TagNumber(7)
  void clearLlmClass() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get model => $_getSZ(7);
  @$pb.TagNumber(8)
  set model($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasModel() => $_has(7);
  @$pb.TagNumber(8)
  void clearModel() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get llmTemperature => $_getSZ(8);
  @$pb.TagNumber(9)
  set llmTemperature($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLlmTemperature() => $_has(8);
  @$pb.TagNumber(9)
  void clearLlmTemperature() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get transcriptionProvider => $_getSZ(9);
  @$pb.TagNumber(10)
  set transcriptionProvider($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasTranscriptionProvider() => $_has(9);
  @$pb.TagNumber(10)
  void clearTranscriptionProvider() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get transcriptionModel => $_getSZ(10);
  @$pb.TagNumber(11)
  set transcriptionModel($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTranscriptionModel() => $_has(10);
  @$pb.TagNumber(11)
  void clearTranscriptionModel() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get visionProvider => $_getSZ(11);
  @$pb.TagNumber(12)
  set visionProvider($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasVisionProvider() => $_has(11);
  @$pb.TagNumber(12)
  void clearVisionProvider() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get visionModel => $_getSZ(12);
  @$pb.TagNumber(13)
  set visionModel($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasVisionModel() => $_has(12);
  @$pb.TagNumber(13)
  void clearVisionModel() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get embeddingsClass => $_getSZ(13);
  @$pb.TagNumber(14)
  set embeddingsClass($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasEmbeddingsClass() => $_has(13);
  @$pb.TagNumber(14)
  void clearEmbeddingsClass() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get embeddingsModel => $_getSZ(14);
  @$pb.TagNumber(15)
  set embeddingsModel($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasEmbeddingsModel() => $_has(14);
  @$pb.TagNumber(15)
  void clearEmbeddingsModel() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get chunkSize => $_getIZ(15);
  @$pb.TagNumber(16)
  set chunkSize($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasChunkSize() => $_has(15);
  @$pb.TagNumber(16)
  void clearChunkSize() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get chunkOverlap => $_getIZ(16);
  @$pb.TagNumber(17)
  set chunkOverlap($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasChunkOverlap() => $_has(16);
  @$pb.TagNumber(17)
  void clearChunkOverlap() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get similarityThreshold => $_getSZ(17);
  @$pb.TagNumber(18)
  set similarityThreshold($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasSimilarityThreshold() => $_has(17);
  @$pb.TagNumber(18)
  void clearSimilarityThreshold() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get vectorDistanceThreshold => $_getSZ(18);
  @$pb.TagNumber(19)
  set vectorDistanceThreshold($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasVectorDistanceThreshold() => $_has(18);
  @$pb.TagNumber(19)
  void clearVectorDistanceThreshold() => $_clearField(19);

  @$pb.TagNumber(20)
  $pb.PbList<ApiKeyEntry> get apiKeys => $_getList(19);
}

class UpdateTenantConfigRequest extends $pb.GeneratedMessage {
  factory UpdateTenantConfigRequest({
    $core.String? tenantId,
    $core.String? dadosEmpresa,
    $core.String? personaBot,
    $core.String? botAgentName,
    $core.String? msgFallback,
    $core.String? msgSemInfo,
    $core.String? msgTransferencia,
    $core.String? llmClass,
    $core.String? model,
    $core.String? llmTemperature,
    $core.String? transcriptionProvider,
    $core.String? transcriptionModel,
    $core.String? visionProvider,
    $core.String? visionModel,
    $core.String? embeddingsClass,
    $core.String? embeddingsModel,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.String? similarityThreshold,
    $core.String? vectorDistanceThreshold,
    $core.Iterable<ApiKeyEntry>? apiKeys,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (dadosEmpresa != null) result.dadosEmpresa = dadosEmpresa;
    if (personaBot != null) result.personaBot = personaBot;
    if (botAgentName != null) result.botAgentName = botAgentName;
    if (msgFallback != null) result.msgFallback = msgFallback;
    if (msgSemInfo != null) result.msgSemInfo = msgSemInfo;
    if (msgTransferencia != null) result.msgTransferencia = msgTransferencia;
    if (llmClass != null) result.llmClass = llmClass;
    if (model != null) result.model = model;
    if (llmTemperature != null) result.llmTemperature = llmTemperature;
    if (transcriptionProvider != null)
      result.transcriptionProvider = transcriptionProvider;
    if (transcriptionModel != null)
      result.transcriptionModel = transcriptionModel;
    if (visionProvider != null) result.visionProvider = visionProvider;
    if (visionModel != null) result.visionModel = visionModel;
    if (embeddingsClass != null) result.embeddingsClass = embeddingsClass;
    if (embeddingsModel != null) result.embeddingsModel = embeddingsModel;
    if (chunkSize != null) result.chunkSize = chunkSize;
    if (chunkOverlap != null) result.chunkOverlap = chunkOverlap;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (vectorDistanceThreshold != null)
      result.vectorDistanceThreshold = vectorDistanceThreshold;
    if (apiKeys != null) result.apiKeys.addAll(apiKeys);
    return result;
  }

  UpdateTenantConfigRequest._();

  factory UpdateTenantConfigRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantConfigRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantConfigRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'dadosEmpresa')
    ..aOS(3, _omitFieldNames ? '' : 'personaBot')
    ..aOS(4, _omitFieldNames ? '' : 'botAgentName')
    ..aOS(5, _omitFieldNames ? '' : 'msgFallback')
    ..aOS(6, _omitFieldNames ? '' : 'msgSemInfo')
    ..aOS(7, _omitFieldNames ? '' : 'msgTransferencia')
    ..aOS(8, _omitFieldNames ? '' : 'llmClass')
    ..aOS(9, _omitFieldNames ? '' : 'model')
    ..aOS(10, _omitFieldNames ? '' : 'llmTemperature')
    ..aOS(11, _omitFieldNames ? '' : 'transcriptionProvider')
    ..aOS(12, _omitFieldNames ? '' : 'transcriptionModel')
    ..aOS(13, _omitFieldNames ? '' : 'visionProvider')
    ..aOS(14, _omitFieldNames ? '' : 'visionModel')
    ..aOS(15, _omitFieldNames ? '' : 'embeddingsClass')
    ..aOS(16, _omitFieldNames ? '' : 'embeddingsModel')
    ..aI(17, _omitFieldNames ? '' : 'chunkSize')
    ..aI(18, _omitFieldNames ? '' : 'chunkOverlap')
    ..aOS(19, _omitFieldNames ? '' : 'similarityThreshold')
    ..aOS(20, _omitFieldNames ? '' : 'vectorDistanceThreshold')
    ..pPM<ApiKeyEntry>(21, _omitFieldNames ? '' : 'apiKeys',
        subBuilder: ApiKeyEntry.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantConfigRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantConfigRequest copyWith(
          void Function(UpdateTenantConfigRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateTenantConfigRequest))
          as UpdateTenantConfigRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantConfigRequest create() => UpdateTenantConfigRequest._();
  @$core.override
  UpdateTenantConfigRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantConfigRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantConfigRequest>(create);
  static UpdateTenantConfigRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get dadosEmpresa => $_getSZ(1);
  @$pb.TagNumber(2)
  set dadosEmpresa($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDadosEmpresa() => $_has(1);
  @$pb.TagNumber(2)
  void clearDadosEmpresa() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get personaBot => $_getSZ(2);
  @$pb.TagNumber(3)
  set personaBot($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPersonaBot() => $_has(2);
  @$pb.TagNumber(3)
  void clearPersonaBot() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get botAgentName => $_getSZ(3);
  @$pb.TagNumber(4)
  set botAgentName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBotAgentName() => $_has(3);
  @$pb.TagNumber(4)
  void clearBotAgentName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get msgFallback => $_getSZ(4);
  @$pb.TagNumber(5)
  set msgFallback($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMsgFallback() => $_has(4);
  @$pb.TagNumber(5)
  void clearMsgFallback() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get msgSemInfo => $_getSZ(5);
  @$pb.TagNumber(6)
  set msgSemInfo($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMsgSemInfo() => $_has(5);
  @$pb.TagNumber(6)
  void clearMsgSemInfo() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get msgTransferencia => $_getSZ(6);
  @$pb.TagNumber(7)
  set msgTransferencia($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMsgTransferencia() => $_has(6);
  @$pb.TagNumber(7)
  void clearMsgTransferencia() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get llmClass => $_getSZ(7);
  @$pb.TagNumber(8)
  set llmClass($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLlmClass() => $_has(7);
  @$pb.TagNumber(8)
  void clearLlmClass() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get model => $_getSZ(8);
  @$pb.TagNumber(9)
  set model($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasModel() => $_has(8);
  @$pb.TagNumber(9)
  void clearModel() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get llmTemperature => $_getSZ(9);
  @$pb.TagNumber(10)
  set llmTemperature($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasLlmTemperature() => $_has(9);
  @$pb.TagNumber(10)
  void clearLlmTemperature() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get transcriptionProvider => $_getSZ(10);
  @$pb.TagNumber(11)
  set transcriptionProvider($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTranscriptionProvider() => $_has(10);
  @$pb.TagNumber(11)
  void clearTranscriptionProvider() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get transcriptionModel => $_getSZ(11);
  @$pb.TagNumber(12)
  set transcriptionModel($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasTranscriptionModel() => $_has(11);
  @$pb.TagNumber(12)
  void clearTranscriptionModel() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get visionProvider => $_getSZ(12);
  @$pb.TagNumber(13)
  set visionProvider($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasVisionProvider() => $_has(12);
  @$pb.TagNumber(13)
  void clearVisionProvider() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get visionModel => $_getSZ(13);
  @$pb.TagNumber(14)
  set visionModel($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasVisionModel() => $_has(13);
  @$pb.TagNumber(14)
  void clearVisionModel() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get embeddingsClass => $_getSZ(14);
  @$pb.TagNumber(15)
  set embeddingsClass($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasEmbeddingsClass() => $_has(14);
  @$pb.TagNumber(15)
  void clearEmbeddingsClass() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get embeddingsModel => $_getSZ(15);
  @$pb.TagNumber(16)
  set embeddingsModel($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasEmbeddingsModel() => $_has(15);
  @$pb.TagNumber(16)
  void clearEmbeddingsModel() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get chunkSize => $_getIZ(16);
  @$pb.TagNumber(17)
  set chunkSize($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasChunkSize() => $_has(16);
  @$pb.TagNumber(17)
  void clearChunkSize() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.int get chunkOverlap => $_getIZ(17);
  @$pb.TagNumber(18)
  set chunkOverlap($core.int value) => $_setSignedInt32(17, value);
  @$pb.TagNumber(18)
  $core.bool hasChunkOverlap() => $_has(17);
  @$pb.TagNumber(18)
  void clearChunkOverlap() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get similarityThreshold => $_getSZ(18);
  @$pb.TagNumber(19)
  set similarityThreshold($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasSimilarityThreshold() => $_has(18);
  @$pb.TagNumber(19)
  void clearSimilarityThreshold() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.String get vectorDistanceThreshold => $_getSZ(19);
  @$pb.TagNumber(20)
  set vectorDistanceThreshold($core.String value) => $_setString(19, value);
  @$pb.TagNumber(20)
  $core.bool hasVectorDistanceThreshold() => $_has(19);
  @$pb.TagNumber(20)
  void clearVectorDistanceThreshold() => $_clearField(20);

  @$pb.TagNumber(21)
  $pb.PbList<ApiKeyEntry> get apiKeys => $_getList(20);
}

class UpdateTenantConfigResponse extends $pb.GeneratedMessage {
  factory UpdateTenantConfigResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  UpdateTenantConfigResponse._();

  factory UpdateTenantConfigResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantConfigResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantConfigResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantConfigResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantConfigResponse copyWith(
          void Function(UpdateTenantConfigResponse) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateTenantConfigResponse))
          as UpdateTenantConfigResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantConfigResponse create() => UpdateTenantConfigResponse._();
  @$core.override
  UpdateTenantConfigResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantConfigResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantConfigResponse>(create);
  static UpdateTenantConfigResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class Tenant extends $pb.GeneratedMessage {
  factory Tenant({
    $core.String? id,
    $core.String? name,
    $core.String? slug,
    $core.String? apiKey,
    $core.int? ownerId,
    $core.String? email,
    $core.String? phone,
    $core.bool? active,
    $core.bool? setupCompleted,
    $core.int? onboardingStep,
    $core.String? accessCode,
    $fixnum.Int64? createdAt,
    $fixnum.Int64? updatedAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (slug != null) result.slug = slug;
    if (apiKey != null) result.apiKey = apiKey;
    if (ownerId != null) result.ownerId = ownerId;
    if (email != null) result.email = email;
    if (phone != null) result.phone = phone;
    if (active != null) result.active = active;
    if (setupCompleted != null) result.setupCompleted = setupCompleted;
    if (onboardingStep != null) result.onboardingStep = onboardingStep;
    if (accessCode != null) result.accessCode = accessCode;
    if (createdAt != null) result.createdAt = createdAt;
    if (updatedAt != null) result.updatedAt = updatedAt;
    return result;
  }

  Tenant._();

  factory Tenant.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Tenant.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Tenant',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'slug')
    ..aOS(4, _omitFieldNames ? '' : 'apiKey')
    ..aI(5, _omitFieldNames ? '' : 'ownerId')
    ..aOS(6, _omitFieldNames ? '' : 'email')
    ..aOS(7, _omitFieldNames ? '' : 'phone')
    ..aOB(8, _omitFieldNames ? '' : 'active')
    ..aOB(9, _omitFieldNames ? '' : 'setupCompleted')
    ..aI(10, _omitFieldNames ? '' : 'onboardingStep')
    ..aOS(11, _omitFieldNames ? '' : 'accessCode')
    ..aInt64(12, _omitFieldNames ? '' : 'createdAt')
    ..aInt64(13, _omitFieldNames ? '' : 'updatedAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tenant clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tenant copyWith(void Function(Tenant) updates) =>
      super.copyWith((message) => updates(message as Tenant)) as Tenant;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Tenant create() => Tenant._();
  @$core.override
  Tenant createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Tenant getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Tenant>(create);
  static Tenant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
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
  $core.String get slug => $_getSZ(2);
  @$pb.TagNumber(3)
  set slug($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSlug() => $_has(2);
  @$pb.TagNumber(3)
  void clearSlug() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get apiKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set apiKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasApiKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearApiKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get ownerId => $_getIZ(4);
  @$pb.TagNumber(5)
  set ownerId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOwnerId() => $_has(4);
  @$pb.TagNumber(5)
  void clearOwnerId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get email => $_getSZ(5);
  @$pb.TagNumber(6)
  set email($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEmail() => $_has(5);
  @$pb.TagNumber(6)
  void clearEmail() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get phone => $_getSZ(6);
  @$pb.TagNumber(7)
  set phone($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPhone() => $_has(6);
  @$pb.TagNumber(7)
  void clearPhone() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get active => $_getBF(7);
  @$pb.TagNumber(8)
  set active($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasActive() => $_has(7);
  @$pb.TagNumber(8)
  void clearActive() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get setupCompleted => $_getBF(8);
  @$pb.TagNumber(9)
  set setupCompleted($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSetupCompleted() => $_has(8);
  @$pb.TagNumber(9)
  void clearSetupCompleted() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get onboardingStep => $_getIZ(9);
  @$pb.TagNumber(10)
  set onboardingStep($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasOnboardingStep() => $_has(9);
  @$pb.TagNumber(10)
  void clearOnboardingStep() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get accessCode => $_getSZ(10);
  @$pb.TagNumber(11)
  set accessCode($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAccessCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearAccessCode() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get createdAt => $_getI64(11);
  @$pb.TagNumber(12)
  set createdAt($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCreatedAt() => $_has(11);
  @$pb.TagNumber(12)
  void clearCreatedAt() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get updatedAt => $_getI64(12);
  @$pb.TagNumber(13)
  set updatedAt($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasUpdatedAt() => $_has(12);
  @$pb.TagNumber(13)
  void clearUpdatedAt() => $_clearField(13);
}

class Plan extends $pb.GeneratedMessage {
  factory Plan({
    $core.int? id,
    $core.String? name,
    $core.String? description,
    $core.String? price,
    $core.int? maxInstances,
    $core.int? maxDepartments,
    $core.bool? active,
    $fixnum.Int64? createdAt,
    $core.int? maxFluxos,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (price != null) result.price = price;
    if (maxInstances != null) result.maxInstances = maxInstances;
    if (maxDepartments != null) result.maxDepartments = maxDepartments;
    if (active != null) result.active = active;
    if (createdAt != null) result.createdAt = createdAt;
    if (maxFluxos != null) result.maxFluxos = maxFluxos;
    return result;
  }

  Plan._();

  factory Plan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Plan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Plan',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'price')
    ..aI(5, _omitFieldNames ? '' : 'maxInstances')
    ..aI(6, _omitFieldNames ? '' : 'maxDepartments')
    ..aOB(7, _omitFieldNames ? '' : 'active')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAt')
    ..aI(9, _omitFieldNames ? '' : 'maxFluxos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Plan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Plan copyWith(void Function(Plan) updates) =>
      super.copyWith((message) => updates(message as Plan)) as Plan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Plan create() => Plan._();
  @$core.override
  Plan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Plan getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Plan>(create);
  static Plan? _defaultInstance;

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
  $core.bool get active => $_getBF(6);
  @$pb.TagNumber(7)
  set active($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasActive() => $_has(6);
  @$pb.TagNumber(7)
  void clearActive() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAt => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAt($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAt() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get maxFluxos => $_getIZ(8);
  @$pb.TagNumber(9)
  set maxFluxos($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMaxFluxos() => $_has(8);
  @$pb.TagNumber(9)
  void clearMaxFluxos() => $_clearField(9);
}

class Subscription extends $pb.GeneratedMessage {
  factory Subscription({
    $core.int? id,
    $core.String? tenantId,
    $core.int? planId,
    $core.String? status,
    $fixnum.Int64? currentPeriodStart,
    $fixnum.Int64? currentPeriodEnd,
    $core.String? paymentGateway,
    $core.String? externalCustomerId,
    $core.String? externalSubscriptionId,
    $fixnum.Int64? updatedAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (tenantId != null) result.tenantId = tenantId;
    if (planId != null) result.planId = planId;
    if (status != null) result.status = status;
    if (currentPeriodStart != null)
      result.currentPeriodStart = currentPeriodStart;
    if (currentPeriodEnd != null) result.currentPeriodEnd = currentPeriodEnd;
    if (paymentGateway != null) result.paymentGateway = paymentGateway;
    if (externalCustomerId != null)
      result.externalCustomerId = externalCustomerId;
    if (externalSubscriptionId != null)
      result.externalSubscriptionId = externalSubscriptionId;
    if (updatedAt != null) result.updatedAt = updatedAt;
    return result;
  }

  Subscription._();

  factory Subscription.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Subscription.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Subscription',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'tenantId')
    ..aI(3, _omitFieldNames ? '' : 'planId')
    ..aOS(4, _omitFieldNames ? '' : 'status')
    ..aInt64(5, _omitFieldNames ? '' : 'currentPeriodStart')
    ..aInt64(6, _omitFieldNames ? '' : 'currentPeriodEnd')
    ..aOS(7, _omitFieldNames ? '' : 'paymentGateway')
    ..aOS(8, _omitFieldNames ? '' : 'externalCustomerId')
    ..aOS(9, _omitFieldNames ? '' : 'externalSubscriptionId')
    ..aInt64(10, _omitFieldNames ? '' : 'updatedAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Subscription clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Subscription copyWith(void Function(Subscription) updates) =>
      super.copyWith((message) => updates(message as Subscription))
          as Subscription;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Subscription create() => Subscription._();
  @$core.override
  Subscription createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Subscription getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Subscription>(create);
  static Subscription? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tenantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tenantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTenantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTenantId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get planId => $_getIZ(2);
  @$pb.TagNumber(3)
  set planId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlanId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlanId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get status => $_getSZ(3);
  @$pb.TagNumber(4)
  set status($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get currentPeriodStart => $_getI64(4);
  @$pb.TagNumber(5)
  set currentPeriodStart($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrentPeriodStart() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrentPeriodStart() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get currentPeriodEnd => $_getI64(5);
  @$pb.TagNumber(6)
  set currentPeriodEnd($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCurrentPeriodEnd() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrentPeriodEnd() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get paymentGateway => $_getSZ(6);
  @$pb.TagNumber(7)
  set paymentGateway($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPaymentGateway() => $_has(6);
  @$pb.TagNumber(7)
  void clearPaymentGateway() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get externalCustomerId => $_getSZ(7);
  @$pb.TagNumber(8)
  set externalCustomerId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExternalCustomerId() => $_has(7);
  @$pb.TagNumber(8)
  void clearExternalCustomerId() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get externalSubscriptionId => $_getSZ(8);
  @$pb.TagNumber(9)
  set externalSubscriptionId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasExternalSubscriptionId() => $_has(8);
  @$pb.TagNumber(9)
  void clearExternalSubscriptionId() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get updatedAt => $_getI64(9);
  @$pb.TagNumber(10)
  set updatedAt($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasUpdatedAt() => $_has(9);
  @$pb.TagNumber(10)
  void clearUpdatedAt() => $_clearField(10);
}

class PaymentRecord extends $pb.GeneratedMessage {
  factory PaymentRecord({
    $core.int? id,
    $core.String? tenantId,
    $core.String? amount,
    $core.String? paymentDate,
    $core.String? paymentMethod,
    $core.String? periodStart,
    $core.String? periodEnd,
    $core.String? notes,
    $core.int? recordedById,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (tenantId != null) result.tenantId = tenantId;
    if (amount != null) result.amount = amount;
    if (paymentDate != null) result.paymentDate = paymentDate;
    if (paymentMethod != null) result.paymentMethod = paymentMethod;
    if (periodStart != null) result.periodStart = periodStart;
    if (periodEnd != null) result.periodEnd = periodEnd;
    if (notes != null) result.notes = notes;
    if (recordedById != null) result.recordedById = recordedById;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  PaymentRecord._();

  factory PaymentRecord.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PaymentRecord.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PaymentRecord',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'tenantId')
    ..aOS(3, _omitFieldNames ? '' : 'amount')
    ..aOS(4, _omitFieldNames ? '' : 'paymentDate')
    ..aOS(5, _omitFieldNames ? '' : 'paymentMethod')
    ..aOS(6, _omitFieldNames ? '' : 'periodStart')
    ..aOS(7, _omitFieldNames ? '' : 'periodEnd')
    ..aOS(8, _omitFieldNames ? '' : 'notes')
    ..aI(9, _omitFieldNames ? '' : 'recordedById')
    ..aInt64(10, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PaymentRecord clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PaymentRecord copyWith(void Function(PaymentRecord) updates) =>
      super.copyWith((message) => updates(message as PaymentRecord))
          as PaymentRecord;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PaymentRecord create() => PaymentRecord._();
  @$core.override
  PaymentRecord createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PaymentRecord getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PaymentRecord>(create);
  static PaymentRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tenantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tenantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTenantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTenantId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get amount => $_getSZ(2);
  @$pb.TagNumber(3)
  set amount($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmount() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get paymentDate => $_getSZ(3);
  @$pb.TagNumber(4)
  set paymentDate($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPaymentDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearPaymentDate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get paymentMethod => $_getSZ(4);
  @$pb.TagNumber(5)
  set paymentMethod($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPaymentMethod() => $_has(4);
  @$pb.TagNumber(5)
  void clearPaymentMethod() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get periodStart => $_getSZ(5);
  @$pb.TagNumber(6)
  set periodStart($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPeriodStart() => $_has(5);
  @$pb.TagNumber(6)
  void clearPeriodStart() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get periodEnd => $_getSZ(6);
  @$pb.TagNumber(7)
  set periodEnd($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPeriodEnd() => $_has(6);
  @$pb.TagNumber(7)
  void clearPeriodEnd() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get notes => $_getSZ(7);
  @$pb.TagNumber(8)
  set notes($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNotes() => $_has(7);
  @$pb.TagNumber(8)
  void clearNotes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get recordedById => $_getIZ(8);
  @$pb.TagNumber(9)
  set recordedById($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRecordedById() => $_has(8);
  @$pb.TagNumber(9)
  void clearRecordedById() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get createdAt => $_getI64(9);
  @$pb.TagNumber(10)
  set createdAt($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedAt() => $_clearField(10);
}

class ListTenantsRequest extends $pb.GeneratedMessage {
  factory ListTenantsRequest() => create();

  ListTenantsRequest._();

  factory ListTenantsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTenantsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTenantsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantsRequest copyWith(void Function(ListTenantsRequest) updates) =>
      super.copyWith((message) => updates(message as ListTenantsRequest))
          as ListTenantsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTenantsRequest create() => ListTenantsRequest._();
  @$core.override
  ListTenantsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTenantsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTenantsRequest>(create);
  static ListTenantsRequest? _defaultInstance;
}

class ListTenantsResponse extends $pb.GeneratedMessage {
  factory ListTenantsResponse({
    $core.Iterable<Tenant>? tenants,
  }) {
    final result = create();
    if (tenants != null) result.tenants.addAll(tenants);
    return result;
  }

  ListTenantsResponse._();

  factory ListTenantsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTenantsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTenantsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<Tenant>(1, _omitFieldNames ? '' : 'tenants',
        subBuilder: Tenant.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantsResponse copyWith(void Function(ListTenantsResponse) updates) =>
      super.copyWith((message) => updates(message as ListTenantsResponse))
          as ListTenantsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTenantsResponse create() => ListTenantsResponse._();
  @$core.override
  ListTenantsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTenantsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTenantsResponse>(create);
  static ListTenantsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Tenant> get tenants => $_getList(0);
}

class GetTenantRequest extends $pb.GeneratedMessage {
  factory GetTenantRequest({
    $core.String? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  GetTenantRequest._();

  factory GetTenantRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetTenantRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTenantRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantRequest copyWith(void Function(GetTenantRequest) updates) =>
      super.copyWith((message) => updates(message as GetTenantRequest))
          as GetTenantRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetTenantRequest create() => GetTenantRequest._();
  @$core.override
  GetTenantRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetTenantRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTenantRequest>(create);
  static GetTenantRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class GetTenantResponse extends $pb.GeneratedMessage {
  factory GetTenantResponse({
    Tenant? tenant,
  }) {
    final result = create();
    if (tenant != null) result.tenant = tenant;
    return result;
  }

  GetTenantResponse._();

  factory GetTenantResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetTenantResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetTenantResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Tenant>(1, _omitFieldNames ? '' : 'tenant', subBuilder: Tenant.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetTenantResponse copyWith(void Function(GetTenantResponse) updates) =>
      super.copyWith((message) => updates(message as GetTenantResponse))
          as GetTenantResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetTenantResponse create() => GetTenantResponse._();
  @$core.override
  GetTenantResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetTenantResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetTenantResponse>(create);
  static GetTenantResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Tenant get tenant => $_getN(0);
  @$pb.TagNumber(1)
  set tenant(Tenant value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTenant() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenant() => $_clearField(1);
  @$pb.TagNumber(1)
  Tenant ensureTenant() => $_ensure(0);
}

class CreateTenantRequest extends $pb.GeneratedMessage {
  factory CreateTenantRequest({
    $core.String? name,
    $core.String? slug,
    $core.int? ownerId,
    $core.String? email,
    $core.String? phone,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (slug != null) result.slug = slug;
    if (ownerId != null) result.ownerId = ownerId;
    if (email != null) result.email = email;
    if (phone != null) result.phone = phone;
    return result;
  }

  CreateTenantRequest._();

  factory CreateTenantRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateTenantRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateTenantRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'slug')
    ..aI(3, _omitFieldNames ? '' : 'ownerId')
    ..aOS(4, _omitFieldNames ? '' : 'email')
    ..aOS(5, _omitFieldNames ? '' : 'phone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTenantRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTenantRequest copyWith(void Function(CreateTenantRequest) updates) =>
      super.copyWith((message) => updates(message as CreateTenantRequest))
          as CreateTenantRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateTenantRequest create() => CreateTenantRequest._();
  @$core.override
  CreateTenantRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateTenantRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateTenantRequest>(create);
  static CreateTenantRequest? _defaultInstance;

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
  $core.int get ownerId => $_getIZ(2);
  @$pb.TagNumber(3)
  set ownerId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOwnerId() => $_has(2);
  @$pb.TagNumber(3)
  void clearOwnerId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get email => $_getSZ(3);
  @$pb.TagNumber(4)
  set email($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmail() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get phone => $_getSZ(4);
  @$pb.TagNumber(5)
  set phone($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPhone() => $_has(4);
  @$pb.TagNumber(5)
  void clearPhone() => $_clearField(5);
}

class CreateTenantResponse extends $pb.GeneratedMessage {
  factory CreateTenantResponse({
    Tenant? tenant,
  }) {
    final result = create();
    if (tenant != null) result.tenant = tenant;
    return result;
  }

  CreateTenantResponse._();

  factory CreateTenantResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateTenantResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateTenantResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Tenant>(1, _omitFieldNames ? '' : 'tenant', subBuilder: Tenant.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTenantResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTenantResponse copyWith(void Function(CreateTenantResponse) updates) =>
      super.copyWith((message) => updates(message as CreateTenantResponse))
          as CreateTenantResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateTenantResponse create() => CreateTenantResponse._();
  @$core.override
  CreateTenantResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateTenantResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateTenantResponse>(create);
  static CreateTenantResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Tenant get tenant => $_getN(0);
  @$pb.TagNumber(1)
  set tenant(Tenant value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTenant() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenant() => $_clearField(1);
  @$pb.TagNumber(1)
  Tenant ensureTenant() => $_ensure(0);
}

class UpdateTenantRequest extends $pb.GeneratedMessage {
  factory UpdateTenantRequest({
    $core.String? id,
    $core.String? name,
    $core.String? slug,
    $core.int? ownerId,
    $core.String? email,
    $core.String? phone,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (slug != null) result.slug = slug;
    if (ownerId != null) result.ownerId = ownerId;
    if (email != null) result.email = email;
    if (phone != null) result.phone = phone;
    return result;
  }

  UpdateTenantRequest._();

  factory UpdateTenantRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'slug')
    ..aI(4, _omitFieldNames ? '' : 'ownerId')
    ..aOS(5, _omitFieldNames ? '' : 'email')
    ..aOS(6, _omitFieldNames ? '' : 'phone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantRequest copyWith(void Function(UpdateTenantRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateTenantRequest))
          as UpdateTenantRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantRequest create() => UpdateTenantRequest._();
  @$core.override
  UpdateTenantRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantRequest>(create);
  static UpdateTenantRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
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
  $core.String get slug => $_getSZ(2);
  @$pb.TagNumber(3)
  set slug($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSlug() => $_has(2);
  @$pb.TagNumber(3)
  void clearSlug() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get ownerId => $_getIZ(3);
  @$pb.TagNumber(4)
  set ownerId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOwnerId() => $_has(3);
  @$pb.TagNumber(4)
  void clearOwnerId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get email => $_getSZ(4);
  @$pb.TagNumber(5)
  set email($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEmail() => $_has(4);
  @$pb.TagNumber(5)
  void clearEmail() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get phone => $_getSZ(5);
  @$pb.TagNumber(6)
  set phone($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPhone() => $_has(5);
  @$pb.TagNumber(6)
  void clearPhone() => $_clearField(6);
}

class UpdateTenantResponse extends $pb.GeneratedMessage {
  factory UpdateTenantResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  UpdateTenantResponse._();

  factory UpdateTenantResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantResponse copyWith(void Function(UpdateTenantResponse) updates) =>
      super.copyWith((message) => updates(message as UpdateTenantResponse))
          as UpdateTenantResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantResponse create() => UpdateTenantResponse._();
  @$core.override
  UpdateTenantResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantResponse>(create);
  static UpdateTenantResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class SetTenantActiveRequest extends $pb.GeneratedMessage {
  factory SetTenantActiveRequest({
    $core.String? id,
    $core.bool? active,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (active != null) result.active = active;
    return result;
  }

  SetTenantActiveRequest._();

  factory SetTenantActiveRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetTenantActiveRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetTenantActiveRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'active')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetTenantActiveRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetTenantActiveRequest copyWith(
          void Function(SetTenantActiveRequest) updates) =>
      super.copyWith((message) => updates(message as SetTenantActiveRequest))
          as SetTenantActiveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetTenantActiveRequest create() => SetTenantActiveRequest._();
  @$core.override
  SetTenantActiveRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetTenantActiveRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetTenantActiveRequest>(create);
  static SetTenantActiveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get active => $_getBF(1);
  @$pb.TagNumber(2)
  set active($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasActive() => $_has(1);
  @$pb.TagNumber(2)
  void clearActive() => $_clearField(2);
}

class SetTenantActiveResponse extends $pb.GeneratedMessage {
  factory SetTenantActiveResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  SetTenantActiveResponse._();

  factory SetTenantActiveResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetTenantActiveResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetTenantActiveResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetTenantActiveResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetTenantActiveResponse copyWith(
          void Function(SetTenantActiveResponse) updates) =>
      super.copyWith((message) => updates(message as SetTenantActiveResponse))
          as SetTenantActiveResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetTenantActiveResponse create() => SetTenantActiveResponse._();
  @$core.override
  SetTenantActiveResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetTenantActiveResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetTenantActiveResponse>(create);
  static SetTenantActiveResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class GenerateAccessCodeRequest extends $pb.GeneratedMessage {
  factory GenerateAccessCodeRequest({
    $core.String? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  GenerateAccessCodeRequest._();

  factory GenerateAccessCodeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GenerateAccessCodeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GenerateAccessCodeRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerateAccessCodeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerateAccessCodeRequest copyWith(
          void Function(GenerateAccessCodeRequest) updates) =>
      super.copyWith((message) => updates(message as GenerateAccessCodeRequest))
          as GenerateAccessCodeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerateAccessCodeRequest create() => GenerateAccessCodeRequest._();
  @$core.override
  GenerateAccessCodeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GenerateAccessCodeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GenerateAccessCodeRequest>(create);
  static GenerateAccessCodeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class GenerateAccessCodeResponse extends $pb.GeneratedMessage {
  factory GenerateAccessCodeResponse({
    $core.String? accessCode,
  }) {
    final result = create();
    if (accessCode != null) result.accessCode = accessCode;
    return result;
  }

  GenerateAccessCodeResponse._();

  factory GenerateAccessCodeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GenerateAccessCodeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GenerateAccessCodeResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accessCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerateAccessCodeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerateAccessCodeResponse copyWith(
          void Function(GenerateAccessCodeResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GenerateAccessCodeResponse))
          as GenerateAccessCodeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerateAccessCodeResponse create() => GenerateAccessCodeResponse._();
  @$core.override
  GenerateAccessCodeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GenerateAccessCodeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GenerateAccessCodeResponse>(create);
  static GenerateAccessCodeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accessCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set accessCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccessCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccessCode() => $_clearField(1);
}

class ListPlansRequest extends $pb.GeneratedMessage {
  factory ListPlansRequest() => create();

  ListPlansRequest._();

  factory ListPlansRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPlansRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPlansRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansRequest copyWith(void Function(ListPlansRequest) updates) =>
      super.copyWith((message) => updates(message as ListPlansRequest))
          as ListPlansRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPlansRequest create() => ListPlansRequest._();
  @$core.override
  ListPlansRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPlansRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPlansRequest>(create);
  static ListPlansRequest? _defaultInstance;
}

class ListPlansResponse extends $pb.GeneratedMessage {
  factory ListPlansResponse({
    $core.Iterable<Plan>? plans,
  }) {
    final result = create();
    if (plans != null) result.plans.addAll(plans);
    return result;
  }

  ListPlansResponse._();

  factory ListPlansResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPlansResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPlansResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<Plan>(1, _omitFieldNames ? '' : 'plans', subBuilder: Plan.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansResponse copyWith(void Function(ListPlansResponse) updates) =>
      super.copyWith((message) => updates(message as ListPlansResponse))
          as ListPlansResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPlansResponse create() => ListPlansResponse._();
  @$core.override
  ListPlansResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPlansResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPlansResponse>(create);
  static ListPlansResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Plan> get plans => $_getList(0);
}

class CreatePlanRequest extends $pb.GeneratedMessage {
  factory CreatePlanRequest({
    $core.String? name,
    $core.String? description,
    $core.String? price,
    $core.int? maxInstances,
    $core.int? maxDepartments,
    $core.int? maxFluxos,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (price != null) result.price = price;
    if (maxInstances != null) result.maxInstances = maxInstances;
    if (maxDepartments != null) result.maxDepartments = maxDepartments;
    if (maxFluxos != null) result.maxFluxos = maxFluxos;
    return result;
  }

  CreatePlanRequest._();

  factory CreatePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreatePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreatePlanRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..aOS(3, _omitFieldNames ? '' : 'price')
    ..aI(4, _omitFieldNames ? '' : 'maxInstances')
    ..aI(5, _omitFieldNames ? '' : 'maxDepartments')
    ..aI(6, _omitFieldNames ? '' : 'maxFluxos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanRequest copyWith(void Function(CreatePlanRequest) updates) =>
      super.copyWith((message) => updates(message as CreatePlanRequest))
          as CreatePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreatePlanRequest create() => CreatePlanRequest._();
  @$core.override
  CreatePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreatePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreatePlanRequest>(create);
  static CreatePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get price => $_getSZ(2);
  @$pb.TagNumber(3)
  set price($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPrice() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrice() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxInstances => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxInstances($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxInstances() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxInstances() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxDepartments => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxDepartments($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxDepartments() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxDepartments() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get maxFluxos => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxFluxos($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxFluxos() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxFluxos() => $_clearField(6);
}

class CreatePlanResponse extends $pb.GeneratedMessage {
  factory CreatePlanResponse({
    Plan? plan,
  }) {
    final result = create();
    if (plan != null) result.plan = plan;
    return result;
  }

  CreatePlanResponse._();

  factory CreatePlanResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreatePlanResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreatePlanResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Plan>(1, _omitFieldNames ? '' : 'plan', subBuilder: Plan.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanResponse copyWith(void Function(CreatePlanResponse) updates) =>
      super.copyWith((message) => updates(message as CreatePlanResponse))
          as CreatePlanResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreatePlanResponse create() => CreatePlanResponse._();
  @$core.override
  CreatePlanResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreatePlanResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreatePlanResponse>(create);
  static CreatePlanResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Plan get plan => $_getN(0);
  @$pb.TagNumber(1)
  set plan(Plan value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlan() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlan() => $_clearField(1);
  @$pb.TagNumber(1)
  Plan ensurePlan() => $_ensure(0);
}

class UpdatePlanRequest extends $pb.GeneratedMessage {
  factory UpdatePlanRequest({
    $core.int? id,
    $core.String? name,
    $core.String? description,
    $core.String? price,
    $core.int? maxInstances,
    $core.int? maxDepartments,
    $core.bool? active,
    $core.int? maxFluxos,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (price != null) result.price = price;
    if (maxInstances != null) result.maxInstances = maxInstances;
    if (maxDepartments != null) result.maxDepartments = maxDepartments;
    if (active != null) result.active = active;
    if (maxFluxos != null) result.maxFluxos = maxFluxos;
    return result;
  }

  UpdatePlanRequest._();

  factory UpdatePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdatePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdatePlanRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'price')
    ..aI(5, _omitFieldNames ? '' : 'maxInstances')
    ..aI(6, _omitFieldNames ? '' : 'maxDepartments')
    ..aOB(7, _omitFieldNames ? '' : 'active')
    ..aI(8, _omitFieldNames ? '' : 'maxFluxos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanRequest copyWith(void Function(UpdatePlanRequest) updates) =>
      super.copyWith((message) => updates(message as UpdatePlanRequest))
          as UpdatePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdatePlanRequest create() => UpdatePlanRequest._();
  @$core.override
  UpdatePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdatePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdatePlanRequest>(create);
  static UpdatePlanRequest? _defaultInstance;

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
  $core.bool get active => $_getBF(6);
  @$pb.TagNumber(7)
  set active($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasActive() => $_has(6);
  @$pb.TagNumber(7)
  void clearActive() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxFluxos => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxFluxos($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxFluxos() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxFluxos() => $_clearField(8);
}

class UpdatePlanResponse extends $pb.GeneratedMessage {
  factory UpdatePlanResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  UpdatePlanResponse._();

  factory UpdatePlanResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdatePlanResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdatePlanResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanResponse copyWith(void Function(UpdatePlanResponse) updates) =>
      super.copyWith((message) => updates(message as UpdatePlanResponse))
          as UpdatePlanResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdatePlanResponse create() => UpdatePlanResponse._();
  @$core.override
  UpdatePlanResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdatePlanResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdatePlanResponse>(create);
  static UpdatePlanResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class Voucher extends $pb.GeneratedMessage {
  factory Voucher({
    $core.String? id,
    $core.String? codigo,
    $core.String? descricao,
    $core.int? planId,
    $core.String? planName,
    $core.int? duracaoDias,
    $core.int? maxResgates,
    $core.int? resgatesUsados,
    $fixnum.Int64? validoDe,
    $fixnum.Int64? validoAte,
    $fixnum.Int64? revogadoEm,
    $core.String? motivoRevogacao,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (codigo != null) result.codigo = codigo;
    if (descricao != null) result.descricao = descricao;
    if (planId != null) result.planId = planId;
    if (planName != null) result.planName = planName;
    if (duracaoDias != null) result.duracaoDias = duracaoDias;
    if (maxResgates != null) result.maxResgates = maxResgates;
    if (resgatesUsados != null) result.resgatesUsados = resgatesUsados;
    if (validoDe != null) result.validoDe = validoDe;
    if (validoAte != null) result.validoAte = validoAte;
    if (revogadoEm != null) result.revogadoEm = revogadoEm;
    if (motivoRevogacao != null) result.motivoRevogacao = motivoRevogacao;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  Voucher._();

  factory Voucher.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Voucher.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Voucher',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'codigo')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aI(4, _omitFieldNames ? '' : 'planId')
    ..aOS(5, _omitFieldNames ? '' : 'planName')
    ..aI(6, _omitFieldNames ? '' : 'duracaoDias')
    ..aI(7, _omitFieldNames ? '' : 'maxResgates')
    ..aI(8, _omitFieldNames ? '' : 'resgatesUsados')
    ..aInt64(9, _omitFieldNames ? '' : 'validoDe')
    ..aInt64(10, _omitFieldNames ? '' : 'validoAte')
    ..aInt64(11, _omitFieldNames ? '' : 'revogadoEm')
    ..aOS(12, _omitFieldNames ? '' : 'motivoRevogacao')
    ..aInt64(13, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Voucher clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Voucher copyWith(void Function(Voucher) updates) =>
      super.copyWith((message) => updates(message as Voucher)) as Voucher;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Voucher create() => Voucher._();
  @$core.override
  Voucher createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Voucher getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Voucher>(create);
  static Voucher? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get codigo => $_getSZ(1);
  @$pb.TagNumber(2)
  set codigo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCodigo() => $_has(1);
  @$pb.TagNumber(2)
  void clearCodigo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get planId => $_getIZ(3);
  @$pb.TagNumber(4)
  set planId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPlanId() => $_has(3);
  @$pb.TagNumber(4)
  void clearPlanId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get planName => $_getSZ(4);
  @$pb.TagNumber(5)
  set planName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPlanName() => $_has(4);
  @$pb.TagNumber(5)
  void clearPlanName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get duracaoDias => $_getIZ(5);
  @$pb.TagNumber(6)
  set duracaoDias($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDuracaoDias() => $_has(5);
  @$pb.TagNumber(6)
  void clearDuracaoDias() => $_clearField(6);

  /// 0 = ilimitado.
  @$pb.TagNumber(7)
  $core.int get maxResgates => $_getIZ(6);
  @$pb.TagNumber(7)
  set maxResgates($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxResgates() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxResgates() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get resgatesUsados => $_getIZ(7);
  @$pb.TagNumber(8)
  set resgatesUsados($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasResgatesUsados() => $_has(7);
  @$pb.TagNumber(8)
  void clearResgatesUsados() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get validoDe => $_getI64(8);
  @$pb.TagNumber(9)
  set validoDe($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasValidoDe() => $_has(8);
  @$pb.TagNumber(9)
  void clearValidoDe() => $_clearField(9);

  /// 0 = não expira sozinho.
  @$pb.TagNumber(10)
  $fixnum.Int64 get validoAte => $_getI64(9);
  @$pb.TagNumber(10)
  set validoAte($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasValidoAte() => $_has(9);
  @$pb.TagNumber(10)
  void clearValidoAte() => $_clearField(10);

  /// 0 = não revogado. Revogar bloqueia NOVOS resgates e preserva as
  /// assinaturas já concedidas.
  @$pb.TagNumber(11)
  $fixnum.Int64 get revogadoEm => $_getI64(10);
  @$pb.TagNumber(11)
  set revogadoEm($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRevogadoEm() => $_has(10);
  @$pb.TagNumber(11)
  void clearRevogadoEm() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get motivoRevogacao => $_getSZ(11);
  @$pb.TagNumber(12)
  set motivoRevogacao($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMotivoRevogacao() => $_has(11);
  @$pb.TagNumber(12)
  void clearMotivoRevogacao() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get createdAt => $_getI64(12);
  @$pb.TagNumber(13)
  set createdAt($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasCreatedAt() => $_has(12);
  @$pb.TagNumber(13)
  void clearCreatedAt() => $_clearField(13);
}

class VoucherRedemption extends $pb.GeneratedMessage {
  factory VoucherRedemption({
    $core.String? id,
    $core.String? voucherId,
    $core.String? tenantId,
    $core.int? planId,
    $fixnum.Int64? periodoInicio,
    $fixnum.Int64? periodoFim,
    $core.String? ip,
    $fixnum.Int64? redeemedAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (voucherId != null) result.voucherId = voucherId;
    if (tenantId != null) result.tenantId = tenantId;
    if (planId != null) result.planId = planId;
    if (periodoInicio != null) result.periodoInicio = periodoInicio;
    if (periodoFim != null) result.periodoFim = periodoFim;
    if (ip != null) result.ip = ip;
    if (redeemedAt != null) result.redeemedAt = redeemedAt;
    return result;
  }

  VoucherRedemption._();

  factory VoucherRedemption.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoucherRedemption.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoucherRedemption',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'voucherId')
    ..aOS(3, _omitFieldNames ? '' : 'tenantId')
    ..aI(4, _omitFieldNames ? '' : 'planId')
    ..aInt64(5, _omitFieldNames ? '' : 'periodoInicio')
    ..aInt64(6, _omitFieldNames ? '' : 'periodoFim')
    ..aOS(7, _omitFieldNames ? '' : 'ip')
    ..aInt64(8, _omitFieldNames ? '' : 'redeemedAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoucherRedemption clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoucherRedemption copyWith(void Function(VoucherRedemption) updates) =>
      super.copyWith((message) => updates(message as VoucherRedemption))
          as VoucherRedemption;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoucherRedemption create() => VoucherRedemption._();
  @$core.override
  VoucherRedemption createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoucherRedemption getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoucherRedemption>(create);
  static VoucherRedemption? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get voucherId => $_getSZ(1);
  @$pb.TagNumber(2)
  set voucherId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVoucherId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVoucherId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tenantId => $_getSZ(2);
  @$pb.TagNumber(3)
  set tenantId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTenantId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTenantId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get planId => $_getIZ(3);
  @$pb.TagNumber(4)
  set planId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPlanId() => $_has(3);
  @$pb.TagNumber(4)
  void clearPlanId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get periodoInicio => $_getI64(4);
  @$pb.TagNumber(5)
  set periodoInicio($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPeriodoInicio() => $_has(4);
  @$pb.TagNumber(5)
  void clearPeriodoInicio() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get periodoFim => $_getI64(5);
  @$pb.TagNumber(6)
  set periodoFim($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPeriodoFim() => $_has(5);
  @$pb.TagNumber(6)
  void clearPeriodoFim() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get ip => $_getSZ(6);
  @$pb.TagNumber(7)
  set ip($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIp() => $_has(6);
  @$pb.TagNumber(7)
  void clearIp() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get redeemedAt => $_getI64(7);
  @$pb.TagNumber(8)
  set redeemedAt($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRedeemedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearRedeemedAt() => $_clearField(8);
}

class ListVouchersRequest extends $pb.GeneratedMessage {
  factory ListVouchersRequest() => create();

  ListVouchersRequest._();

  factory ListVouchersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListVouchersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListVouchersRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVouchersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVouchersRequest copyWith(void Function(ListVouchersRequest) updates) =>
      super.copyWith((message) => updates(message as ListVouchersRequest))
          as ListVouchersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListVouchersRequest create() => ListVouchersRequest._();
  @$core.override
  ListVouchersRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListVouchersRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListVouchersRequest>(create);
  static ListVouchersRequest? _defaultInstance;
}

class ListVouchersResponse extends $pb.GeneratedMessage {
  factory ListVouchersResponse({
    $core.Iterable<Voucher>? vouchers,
  }) {
    final result = create();
    if (vouchers != null) result.vouchers.addAll(vouchers);
    return result;
  }

  ListVouchersResponse._();

  factory ListVouchersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListVouchersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListVouchersResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<Voucher>(1, _omitFieldNames ? '' : 'vouchers',
        subBuilder: Voucher.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVouchersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVouchersResponse copyWith(void Function(ListVouchersResponse) updates) =>
      super.copyWith((message) => updates(message as ListVouchersResponse))
          as ListVouchersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListVouchersResponse create() => ListVouchersResponse._();
  @$core.override
  ListVouchersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListVouchersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListVouchersResponse>(create);
  static ListVouchersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Voucher> get vouchers => $_getList(0);
}

class CreateVoucherRequest extends $pb.GeneratedMessage {
  factory CreateVoucherRequest({
    $core.String? codigo,
    $core.String? descricao,
    $core.int? planId,
    $core.int? duracaoDias,
    $core.int? maxResgates,
    $core.String? validoAte,
  }) {
    final result = create();
    if (codigo != null) result.codigo = codigo;
    if (descricao != null) result.descricao = descricao;
    if (planId != null) result.planId = planId;
    if (duracaoDias != null) result.duracaoDias = duracaoDias;
    if (maxResgates != null) result.maxResgates = maxResgates;
    if (validoAte != null) result.validoAte = validoAte;
    return result;
  }

  CreateVoucherRequest._();

  factory CreateVoucherRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateVoucherRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateVoucherRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'codigo')
    ..aOS(2, _omitFieldNames ? '' : 'descricao')
    ..aI(3, _omitFieldNames ? '' : 'planId')
    ..aI(4, _omitFieldNames ? '' : 'duracaoDias')
    ..aI(5, _omitFieldNames ? '' : 'maxResgates')
    ..aOS(6, _omitFieldNames ? '' : 'validoAte')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateVoucherRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateVoucherRequest copyWith(void Function(CreateVoucherRequest) updates) =>
      super.copyWith((message) => updates(message as CreateVoucherRequest))
          as CreateVoucherRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateVoucherRequest create() => CreateVoucherRequest._();
  @$core.override
  CreateVoucherRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateVoucherRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateVoucherRequest>(create);
  static CreateVoucherRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get codigo => $_getSZ(0);
  @$pb.TagNumber(1)
  set codigo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCodigo() => $_has(0);
  @$pb.TagNumber(1)
  void clearCodigo() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get descricao => $_getSZ(1);
  @$pb.TagNumber(2)
  set descricao($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescricao() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescricao() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get planId => $_getIZ(2);
  @$pb.TagNumber(3)
  set planId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlanId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlanId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get duracaoDias => $_getIZ(3);
  @$pb.TagNumber(4)
  set duracaoDias($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDuracaoDias() => $_has(3);
  @$pb.TagNumber(4)
  void clearDuracaoDias() => $_clearField(4);

  /// 0 = ilimitado (campanha aberta). O cliente sempre envia o valor escolhido
  /// na tela; o padrão da tela é 1, o mais conservador.
  @$pb.TagNumber(5)
  $core.int get maxResgates => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxResgates($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxResgates() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxResgates() => $_clearField(5);

  /// RFC 3339; vazio = sem expiração.
  @$pb.TagNumber(6)
  $core.String get validoAte => $_getSZ(5);
  @$pb.TagNumber(6)
  set validoAte($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasValidoAte() => $_has(5);
  @$pb.TagNumber(6)
  void clearValidoAte() => $_clearField(6);
}

class CreateVoucherResponse extends $pb.GeneratedMessage {
  factory CreateVoucherResponse({
    Voucher? voucher,
  }) {
    final result = create();
    if (voucher != null) result.voucher = voucher;
    return result;
  }

  CreateVoucherResponse._();

  factory CreateVoucherResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateVoucherResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateVoucherResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Voucher>(1, _omitFieldNames ? '' : 'voucher',
        subBuilder: Voucher.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateVoucherResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateVoucherResponse copyWith(
          void Function(CreateVoucherResponse) updates) =>
      super.copyWith((message) => updates(message as CreateVoucherResponse))
          as CreateVoucherResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateVoucherResponse create() => CreateVoucherResponse._();
  @$core.override
  CreateVoucherResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateVoucherResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateVoucherResponse>(create);
  static CreateVoucherResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Voucher get voucher => $_getN(0);
  @$pb.TagNumber(1)
  set voucher(Voucher value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasVoucher() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoucher() => $_clearField(1);
  @$pb.TagNumber(1)
  Voucher ensureVoucher() => $_ensure(0);
}

class RevokeVoucherRequest extends $pb.GeneratedMessage {
  factory RevokeVoucherRequest({
    $core.String? voucherId,
    $core.String? motivo,
  }) {
    final result = create();
    if (voucherId != null) result.voucherId = voucherId;
    if (motivo != null) result.motivo = motivo;
    return result;
  }

  RevokeVoucherRequest._();

  factory RevokeVoucherRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeVoucherRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeVoucherRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voucherId')
    ..aOS(2, _omitFieldNames ? '' : 'motivo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeVoucherRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeVoucherRequest copyWith(void Function(RevokeVoucherRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeVoucherRequest))
          as RevokeVoucherRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeVoucherRequest create() => RevokeVoucherRequest._();
  @$core.override
  RevokeVoucherRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeVoucherRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeVoucherRequest>(create);
  static RevokeVoucherRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get voucherId => $_getSZ(0);
  @$pb.TagNumber(1)
  set voucherId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVoucherId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoucherId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get motivo => $_getSZ(1);
  @$pb.TagNumber(2)
  set motivo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMotivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearMotivo() => $_clearField(2);
}

class RevokeVoucherResponse extends $pb.GeneratedMessage {
  factory RevokeVoucherResponse({
    $core.bool? revogado,
  }) {
    final result = create();
    if (revogado != null) result.revogado = revogado;
    return result;
  }

  RevokeVoucherResponse._();

  factory RevokeVoucherResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeVoucherResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeVoucherResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'revogado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeVoucherResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeVoucherResponse copyWith(
          void Function(RevokeVoucherResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeVoucherResponse))
          as RevokeVoucherResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeVoucherResponse create() => RevokeVoucherResponse._();
  @$core.override
  RevokeVoucherResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeVoucherResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeVoucherResponse>(create);
  static RevokeVoucherResponse? _defaultInstance;

  /// false = já estava revogado (não é erro).
  @$pb.TagNumber(1)
  $core.bool get revogado => $_getBF(0);
  @$pb.TagNumber(1)
  set revogado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRevogado() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevogado() => $_clearField(1);
}

class ListVoucherRedemptionsRequest extends $pb.GeneratedMessage {
  factory ListVoucherRedemptionsRequest({
    $core.String? voucherId,
  }) {
    final result = create();
    if (voucherId != null) result.voucherId = voucherId;
    return result;
  }

  ListVoucherRedemptionsRequest._();

  factory ListVoucherRedemptionsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListVoucherRedemptionsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListVoucherRedemptionsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'voucherId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVoucherRedemptionsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVoucherRedemptionsRequest copyWith(
          void Function(ListVoucherRedemptionsRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListVoucherRedemptionsRequest))
          as ListVoucherRedemptionsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListVoucherRedemptionsRequest create() =>
      ListVoucherRedemptionsRequest._();
  @$core.override
  ListVoucherRedemptionsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListVoucherRedemptionsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListVoucherRedemptionsRequest>(create);
  static ListVoucherRedemptionsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get voucherId => $_getSZ(0);
  @$pb.TagNumber(1)
  set voucherId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVoucherId() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoucherId() => $_clearField(1);
}

class ListVoucherRedemptionsResponse extends $pb.GeneratedMessage {
  factory ListVoucherRedemptionsResponse({
    $core.Iterable<VoucherRedemption>? resgates,
  }) {
    final result = create();
    if (resgates != null) result.resgates.addAll(resgates);
    return result;
  }

  ListVoucherRedemptionsResponse._();

  factory ListVoucherRedemptionsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListVoucherRedemptionsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListVoucherRedemptionsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<VoucherRedemption>(1, _omitFieldNames ? '' : 'resgates',
        subBuilder: VoucherRedemption.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVoucherRedemptionsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListVoucherRedemptionsResponse copyWith(
          void Function(ListVoucherRedemptionsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListVoucherRedemptionsResponse))
          as ListVoucherRedemptionsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListVoucherRedemptionsResponse create() =>
      ListVoucherRedemptionsResponse._();
  @$core.override
  ListVoucherRedemptionsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListVoucherRedemptionsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListVoucherRedemptionsResponse>(create);
  static ListVoucherRedemptionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<VoucherRedemption> get resgates => $_getList(0);
}

class ListSubscriptionsRequest extends $pb.GeneratedMessage {
  factory ListSubscriptionsRequest() => create();

  ListSubscriptionsRequest._();

  factory ListSubscriptionsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListSubscriptionsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSubscriptionsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSubscriptionsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSubscriptionsRequest copyWith(
          void Function(ListSubscriptionsRequest) updates) =>
      super.copyWith((message) => updates(message as ListSubscriptionsRequest))
          as ListSubscriptionsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListSubscriptionsRequest create() => ListSubscriptionsRequest._();
  @$core.override
  ListSubscriptionsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListSubscriptionsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSubscriptionsRequest>(create);
  static ListSubscriptionsRequest? _defaultInstance;
}

class ListSubscriptionsResponse extends $pb.GeneratedMessage {
  factory ListSubscriptionsResponse({
    $core.Iterable<Subscription>? subscriptions,
  }) {
    final result = create();
    if (subscriptions != null) result.subscriptions.addAll(subscriptions);
    return result;
  }

  ListSubscriptionsResponse._();

  factory ListSubscriptionsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListSubscriptionsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListSubscriptionsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<Subscription>(1, _omitFieldNames ? '' : 'subscriptions',
        subBuilder: Subscription.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSubscriptionsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListSubscriptionsResponse copyWith(
          void Function(ListSubscriptionsResponse) updates) =>
      super.copyWith((message) => updates(message as ListSubscriptionsResponse))
          as ListSubscriptionsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListSubscriptionsResponse create() => ListSubscriptionsResponse._();
  @$core.override
  ListSubscriptionsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListSubscriptionsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListSubscriptionsResponse>(create);
  static ListSubscriptionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Subscription> get subscriptions => $_getList(0);
}

class RegisterPaymentRequest extends $pb.GeneratedMessage {
  factory RegisterPaymentRequest({
    $core.String? tenantId,
    $core.String? amount,
    $core.String? paymentMethod,
    $core.String? paymentDate,
    $core.String? periodStart,
    $core.String? periodEnd,
    $core.String? notes,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (amount != null) result.amount = amount;
    if (paymentMethod != null) result.paymentMethod = paymentMethod;
    if (paymentDate != null) result.paymentDate = paymentDate;
    if (periodStart != null) result.periodStart = periodStart;
    if (periodEnd != null) result.periodEnd = periodEnd;
    if (notes != null) result.notes = notes;
    return result;
  }

  RegisterPaymentRequest._();

  factory RegisterPaymentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterPaymentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterPaymentRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'amount')
    ..aOS(3, _omitFieldNames ? '' : 'paymentMethod')
    ..aOS(4, _omitFieldNames ? '' : 'paymentDate')
    ..aOS(5, _omitFieldNames ? '' : 'periodStart')
    ..aOS(6, _omitFieldNames ? '' : 'periodEnd')
    ..aOS(7, _omitFieldNames ? '' : 'notes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPaymentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPaymentRequest copyWith(
          void Function(RegisterPaymentRequest) updates) =>
      super.copyWith((message) => updates(message as RegisterPaymentRequest))
          as RegisterPaymentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterPaymentRequest create() => RegisterPaymentRequest._();
  @$core.override
  RegisterPaymentRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterPaymentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterPaymentRequest>(create);
  static RegisterPaymentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get amount => $_getSZ(1);
  @$pb.TagNumber(2)
  set amount($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmount() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmount() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get paymentMethod => $_getSZ(2);
  @$pb.TagNumber(3)
  set paymentMethod($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPaymentMethod() => $_has(2);
  @$pb.TagNumber(3)
  void clearPaymentMethod() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get paymentDate => $_getSZ(3);
  @$pb.TagNumber(4)
  set paymentDate($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPaymentDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearPaymentDate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get periodStart => $_getSZ(4);
  @$pb.TagNumber(5)
  set periodStart($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPeriodStart() => $_has(4);
  @$pb.TagNumber(5)
  void clearPeriodStart() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get periodEnd => $_getSZ(5);
  @$pb.TagNumber(6)
  set periodEnd($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPeriodEnd() => $_has(5);
  @$pb.TagNumber(6)
  void clearPeriodEnd() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get notes => $_getSZ(6);
  @$pb.TagNumber(7)
  set notes($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNotes() => $_has(6);
  @$pb.TagNumber(7)
  void clearNotes() => $_clearField(7);
}

class RegisterPaymentResponse extends $pb.GeneratedMessage {
  factory RegisterPaymentResponse({
    PaymentRecord? payment,
  }) {
    final result = create();
    if (payment != null) result.payment = payment;
    return result;
  }

  RegisterPaymentResponse._();

  factory RegisterPaymentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterPaymentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterPaymentResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<PaymentRecord>(1, _omitFieldNames ? '' : 'payment',
        subBuilder: PaymentRecord.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPaymentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPaymentResponse copyWith(
          void Function(RegisterPaymentResponse) updates) =>
      super.copyWith((message) => updates(message as RegisterPaymentResponse))
          as RegisterPaymentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterPaymentResponse create() => RegisterPaymentResponse._();
  @$core.override
  RegisterPaymentResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterPaymentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterPaymentResponse>(create);
  static RegisterPaymentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  PaymentRecord get payment => $_getN(0);
  @$pb.TagNumber(1)
  set payment(PaymentRecord value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPayment() => $_has(0);
  @$pb.TagNumber(1)
  void clearPayment() => $_clearField(1);
  @$pb.TagNumber(1)
  PaymentRecord ensurePayment() => $_ensure(0);
}

class ListPaymentsRequest extends $pb.GeneratedMessage {
  factory ListPaymentsRequest({
    $core.String? tenantId,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  ListPaymentsRequest._();

  factory ListPaymentsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPaymentsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPaymentsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentsRequest copyWith(void Function(ListPaymentsRequest) updates) =>
      super.copyWith((message) => updates(message as ListPaymentsRequest))
          as ListPaymentsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPaymentsRequest create() => ListPaymentsRequest._();
  @$core.override
  ListPaymentsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPaymentsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPaymentsRequest>(create);
  static ListPaymentsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);
}

class ListPaymentsResponse extends $pb.GeneratedMessage {
  factory ListPaymentsResponse({
    $core.Iterable<PaymentRecord>? payments,
  }) {
    final result = create();
    if (payments != null) result.payments.addAll(payments);
    return result;
  }

  ListPaymentsResponse._();

  factory ListPaymentsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPaymentsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPaymentsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<PaymentRecord>(1, _omitFieldNames ? '' : 'payments',
        subBuilder: PaymentRecord.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPaymentsResponse copyWith(void Function(ListPaymentsResponse) updates) =>
      super.copyWith((message) => updates(message as ListPaymentsResponse))
          as ListPaymentsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPaymentsResponse create() => ListPaymentsResponse._();
  @$core.override
  ListPaymentsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPaymentsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPaymentsResponse>(create);
  static ListPaymentsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PaymentRecord> get payments => $_getList(0);
}

/// --- Fase 3: Evolution Connection ---
class TestEvolutionConnectionRequest extends $pb.GeneratedMessage {
  factory TestEvolutionConnectionRequest({
    $core.String? tenantId,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  TestEvolutionConnectionRequest._();

  factory TestEvolutionConnectionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestEvolutionConnectionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestEvolutionConnectionRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestEvolutionConnectionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestEvolutionConnectionRequest copyWith(
          void Function(TestEvolutionConnectionRequest) updates) =>
      super.copyWith(
              (message) => updates(message as TestEvolutionConnectionRequest))
          as TestEvolutionConnectionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestEvolutionConnectionRequest create() =>
      TestEvolutionConnectionRequest._();
  @$core.override
  TestEvolutionConnectionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestEvolutionConnectionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestEvolutionConnectionRequest>(create);
  static TestEvolutionConnectionRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);
}

class TestEvolutionConnectionResponse extends $pb.GeneratedMessage {
  factory TestEvolutionConnectionResponse({
    $core.String? status,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  TestEvolutionConnectionResponse._();

  factory TestEvolutionConnectionResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestEvolutionConnectionResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestEvolutionConnectionResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestEvolutionConnectionResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestEvolutionConnectionResponse copyWith(
          void Function(TestEvolutionConnectionResponse) updates) =>
      super.copyWith(
              (message) => updates(message as TestEvolutionConnectionResponse))
          as TestEvolutionConnectionResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestEvolutionConnectionResponse create() =>
      TestEvolutionConnectionResponse._();
  @$core.override
  TestEvolutionConnectionResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestEvolutionConnectionResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestEvolutionConnectionResponse>(
          create);
  static TestEvolutionConnectionResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get status => $_getSZ(0);
  @$pb.TagNumber(1)
  set status($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => $_clearField(2);
}

/// --- Fase 4: Feature Flags ---
class FeatureFlagOverride extends $pb.GeneratedMessage {
  factory FeatureFlagOverride({
    $core.String? tenantId,
    $core.bool? enabled,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (enabled != null) result.enabled = enabled;
    return result;
  }

  FeatureFlagOverride._();

  factory FeatureFlagOverride.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FeatureFlagOverride.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FeatureFlagOverride',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOB(2, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlagOverride clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlagOverride copyWith(void Function(FeatureFlagOverride) updates) =>
      super.copyWith((message) => updates(message as FeatureFlagOverride))
          as FeatureFlagOverride;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FeatureFlagOverride create() => FeatureFlagOverride._();
  @$core.override
  FeatureFlagOverride createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FeatureFlagOverride getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FeatureFlagOverride>(create);
  static FeatureFlagOverride? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enabled => $_getBF(1);
  @$pb.TagNumber(2)
  set enabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabled() => $_clearField(2);
}

class FeatureFlag extends $pb.GeneratedMessage {
  factory FeatureFlag({
    $core.String? key,
    $core.String? description,
    $core.bool? enabledGlobally,
    $core.Iterable<FeatureFlagOverride>? overrides,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (description != null) result.description = description;
    if (enabledGlobally != null) result.enabledGlobally = enabledGlobally;
    if (overrides != null) result.overrides.addAll(overrides);
    return result;
  }

  FeatureFlag._();

  factory FeatureFlag.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FeatureFlag.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FeatureFlag',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..aOB(3, _omitFieldNames ? '' : 'enabledGlobally')
    ..pPM<FeatureFlagOverride>(4, _omitFieldNames ? '' : 'overrides',
        subBuilder: FeatureFlagOverride.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlag clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlag copyWith(void Function(FeatureFlag) updates) =>
      super.copyWith((message) => updates(message as FeatureFlag))
          as FeatureFlag;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FeatureFlag create() => FeatureFlag._();
  @$core.override
  FeatureFlag createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FeatureFlag getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FeatureFlag>(create);
  static FeatureFlag? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get enabledGlobally => $_getBF(2);
  @$pb.TagNumber(3)
  set enabledGlobally($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnabledGlobally() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnabledGlobally() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<FeatureFlagOverride> get overrides => $_getList(3);
}

class ListFeatureFlagsRequest extends $pb.GeneratedMessage {
  factory ListFeatureFlagsRequest() => create();

  ListFeatureFlagsRequest._();

  factory ListFeatureFlagsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListFeatureFlagsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListFeatureFlagsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFeatureFlagsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFeatureFlagsRequest copyWith(
          void Function(ListFeatureFlagsRequest) updates) =>
      super.copyWith((message) => updates(message as ListFeatureFlagsRequest))
          as ListFeatureFlagsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListFeatureFlagsRequest create() => ListFeatureFlagsRequest._();
  @$core.override
  ListFeatureFlagsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListFeatureFlagsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListFeatureFlagsRequest>(create);
  static ListFeatureFlagsRequest? _defaultInstance;
}

class ListFeatureFlagsResponse extends $pb.GeneratedMessage {
  factory ListFeatureFlagsResponse({
    $core.Iterable<FeatureFlag>? flags,
  }) {
    final result = create();
    if (flags != null) result.flags.addAll(flags);
    return result;
  }

  ListFeatureFlagsResponse._();

  factory ListFeatureFlagsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListFeatureFlagsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListFeatureFlagsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<FeatureFlag>(1, _omitFieldNames ? '' : 'flags',
        subBuilder: FeatureFlag.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFeatureFlagsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListFeatureFlagsResponse copyWith(
          void Function(ListFeatureFlagsResponse) updates) =>
      super.copyWith((message) => updates(message as ListFeatureFlagsResponse))
          as ListFeatureFlagsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListFeatureFlagsResponse create() => ListFeatureFlagsResponse._();
  @$core.override
  ListFeatureFlagsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListFeatureFlagsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListFeatureFlagsResponse>(create);
  static ListFeatureFlagsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<FeatureFlag> get flags => $_getList(0);
}

class SetFeatureFlagRequest extends $pb.GeneratedMessage {
  factory SetFeatureFlagRequest({
    $core.String? key,
    $core.bool? enabledGlobally,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (enabledGlobally != null) result.enabledGlobally = enabledGlobally;
    return result;
  }

  SetFeatureFlagRequest._();

  factory SetFeatureFlagRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetFeatureFlagRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFeatureFlagRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOB(2, _omitFieldNames ? '' : 'enabledGlobally')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagRequest copyWith(
          void Function(SetFeatureFlagRequest) updates) =>
      super.copyWith((message) => updates(message as SetFeatureFlagRequest))
          as SetFeatureFlagRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagRequest create() => SetFeatureFlagRequest._();
  @$core.override
  SetFeatureFlagRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFeatureFlagRequest>(create);
  static SetFeatureFlagRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enabledGlobally => $_getBF(1);
  @$pb.TagNumber(2)
  set enabledGlobally($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabledGlobally() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabledGlobally() => $_clearField(2);
}

class SetFeatureFlagResponse extends $pb.GeneratedMessage {
  factory SetFeatureFlagResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  SetFeatureFlagResponse._();

  factory SetFeatureFlagResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetFeatureFlagResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFeatureFlagResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagResponse copyWith(
          void Function(SetFeatureFlagResponse) updates) =>
      super.copyWith((message) => updates(message as SetFeatureFlagResponse))
          as SetFeatureFlagResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagResponse create() => SetFeatureFlagResponse._();
  @$core.override
  SetFeatureFlagResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFeatureFlagResponse>(create);
  static SetFeatureFlagResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class SetFeatureFlagOverrideRequest extends $pb.GeneratedMessage {
  factory SetFeatureFlagOverrideRequest({
    $core.String? key,
    $core.String? tenantId,
    $core.bool? enabled,
    $core.bool? removeOverride,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (tenantId != null) result.tenantId = tenantId;
    if (enabled != null) result.enabled = enabled;
    if (removeOverride != null) result.removeOverride = removeOverride;
    return result;
  }

  SetFeatureFlagOverrideRequest._();

  factory SetFeatureFlagOverrideRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetFeatureFlagOverrideRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFeatureFlagOverrideRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'tenantId')
    ..aOB(3, _omitFieldNames ? '' : 'enabled')
    ..aOB(4, _omitFieldNames ? '' : 'removeOverride')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagOverrideRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagOverrideRequest copyWith(
          void Function(SetFeatureFlagOverrideRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SetFeatureFlagOverrideRequest))
          as SetFeatureFlagOverrideRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagOverrideRequest create() =>
      SetFeatureFlagOverrideRequest._();
  @$core.override
  SetFeatureFlagOverrideRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagOverrideRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFeatureFlagOverrideRequest>(create);
  static SetFeatureFlagOverrideRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tenantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tenantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTenantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTenantId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get enabled => $_getBF(2);
  @$pb.TagNumber(3)
  set enabled($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEnabled() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnabled() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get removeOverride => $_getBF(3);
  @$pb.TagNumber(4)
  set removeOverride($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRemoveOverride() => $_has(3);
  @$pb.TagNumber(4)
  void clearRemoveOverride() => $_clearField(4);
}

class SetFeatureFlagOverrideResponse extends $pb.GeneratedMessage {
  factory SetFeatureFlagOverrideResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  SetFeatureFlagOverrideResponse._();

  factory SetFeatureFlagOverrideResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetFeatureFlagOverrideResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFeatureFlagOverrideResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagOverrideResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFeatureFlagOverrideResponse copyWith(
          void Function(SetFeatureFlagOverrideResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SetFeatureFlagOverrideResponse))
          as SetFeatureFlagOverrideResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagOverrideResponse create() =>
      SetFeatureFlagOverrideResponse._();
  @$core.override
  SetFeatureFlagOverrideResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetFeatureFlagOverrideResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetFeatureFlagOverrideResponse>(create);
  static SetFeatureFlagOverrideResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

/// --- Fase 5: Auditoria & Saúde ---
class AuditLogEntry extends $pb.GeneratedMessage {
  factory AuditLogEntry({
    $core.int? id,
    $core.String? eventType,
    $core.String? actor,
    $core.String? tenantId,
    $core.String? description,
    $core.String? ipAddress,
    $core.String? userAgent,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (eventType != null) result.eventType = eventType;
    if (actor != null) result.actor = actor;
    if (tenantId != null) result.tenantId = tenantId;
    if (description != null) result.description = description;
    if (ipAddress != null) result.ipAddress = ipAddress;
    if (userAgent != null) result.userAgent = userAgent;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  AuditLogEntry._();

  factory AuditLogEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AuditLogEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuditLogEntry',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'eventType')
    ..aOS(3, _omitFieldNames ? '' : 'actor')
    ..aOS(4, _omitFieldNames ? '' : 'tenantId')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..aOS(6, _omitFieldNames ? '' : 'ipAddress')
    ..aOS(7, _omitFieldNames ? '' : 'userAgent')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditLogEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuditLogEntry copyWith(void Function(AuditLogEntry) updates) =>
      super.copyWith((message) => updates(message as AuditLogEntry))
          as AuditLogEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuditLogEntry create() => AuditLogEntry._();
  @$core.override
  AuditLogEntry createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AuditLogEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AuditLogEntry>(create);
  static AuditLogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventType => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventType() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get actor => $_getSZ(2);
  @$pb.TagNumber(3)
  set actor($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasActor() => $_has(2);
  @$pb.TagNumber(3)
  void clearActor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get tenantId => $_getSZ(3);
  @$pb.TagNumber(4)
  set tenantId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTenantId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTenantId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get ipAddress => $_getSZ(5);
  @$pb.TagNumber(6)
  set ipAddress($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIpAddress() => $_has(5);
  @$pb.TagNumber(6)
  void clearIpAddress() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get userAgent => $_getSZ(6);
  @$pb.TagNumber(7)
  set userAgent($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasUserAgent() => $_has(6);
  @$pb.TagNumber(7)
  void clearUserAgent() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAt => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAt($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAt() => $_clearField(8);
}

class QueryAuditLogRequest extends $pb.GeneratedMessage {
  factory QueryAuditLogRequest({
    $core.String? tenantId,
    $core.String? eventType,
    $core.int? limit,
    $core.int? offset,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    if (eventType != null) result.eventType = eventType;
    if (limit != null) result.limit = limit;
    if (offset != null) result.offset = offset;
    return result;
  }

  QueryAuditLogRequest._();

  factory QueryAuditLogRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory QueryAuditLogRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QueryAuditLogRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..aOS(2, _omitFieldNames ? '' : 'eventType')
    ..aI(3, _omitFieldNames ? '' : 'limit')
    ..aI(4, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryAuditLogRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryAuditLogRequest copyWith(void Function(QueryAuditLogRequest) updates) =>
      super.copyWith((message) => updates(message as QueryAuditLogRequest))
          as QueryAuditLogRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static QueryAuditLogRequest create() => QueryAuditLogRequest._();
  @$core.override
  QueryAuditLogRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static QueryAuditLogRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QueryAuditLogRequest>(create);
  static QueryAuditLogRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventType => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventType() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get offset => $_getIZ(3);
  @$pb.TagNumber(4)
  set offset($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearOffset() => $_clearField(4);
}

class QueryAuditLogResponse extends $pb.GeneratedMessage {
  factory QueryAuditLogResponse({
    $core.Iterable<AuditLogEntry>? entries,
    $core.int? totalCount,
  }) {
    final result = create();
    if (entries != null) result.entries.addAll(entries);
    if (totalCount != null) result.totalCount = totalCount;
    return result;
  }

  QueryAuditLogResponse._();

  factory QueryAuditLogResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory QueryAuditLogResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QueryAuditLogResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<AuditLogEntry>(1, _omitFieldNames ? '' : 'entries',
        subBuilder: AuditLogEntry.create)
    ..aI(2, _omitFieldNames ? '' : 'totalCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryAuditLogResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QueryAuditLogResponse copyWith(
          void Function(QueryAuditLogResponse) updates) =>
      super.copyWith((message) => updates(message as QueryAuditLogResponse))
          as QueryAuditLogResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static QueryAuditLogResponse create() => QueryAuditLogResponse._();
  @$core.override
  QueryAuditLogResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static QueryAuditLogResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QueryAuditLogResponse>(create);
  static QueryAuditLogResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AuditLogEntry> get entries => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get totalCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalCount() => $_clearField(2);
}

class ServiceHealth extends $pb.GeneratedMessage {
  factory ServiceHealth({
    $core.String? serviceName,
    $core.String? status,
    $core.String? message,
    $fixnum.Int64? responseTimeMs,
  }) {
    final result = create();
    if (serviceName != null) result.serviceName = serviceName;
    if (status != null) result.status = status;
    if (message != null) result.message = message;
    if (responseTimeMs != null) result.responseTimeMs = responseTimeMs;
    return result;
  }

  ServiceHealth._();

  factory ServiceHealth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ServiceHealth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServiceHealth',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'serviceName')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..aInt64(4, _omitFieldNames ? '' : 'responseTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServiceHealth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServiceHealth copyWith(void Function(ServiceHealth) updates) =>
      super.copyWith((message) => updates(message as ServiceHealth))
          as ServiceHealth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServiceHealth create() => ServiceHealth._();
  @$core.override
  ServiceHealth createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ServiceHealth getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServiceHealth>(create);
  static ServiceHealth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get serviceName => $_getSZ(0);
  @$pb.TagNumber(1)
  set serviceName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasServiceName() => $_has(0);
  @$pb.TagNumber(1)
  void clearServiceName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get responseTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set responseTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResponseTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearResponseTimeMs() => $_clearField(4);
}

class GetServiceHealthRequest extends $pb.GeneratedMessage {
  factory GetServiceHealthRequest() => create();

  GetServiceHealthRequest._();

  factory GetServiceHealthRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetServiceHealthRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetServiceHealthRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServiceHealthRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServiceHealthRequest copyWith(
          void Function(GetServiceHealthRequest) updates) =>
      super.copyWith((message) => updates(message as GetServiceHealthRequest))
          as GetServiceHealthRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetServiceHealthRequest create() => GetServiceHealthRequest._();
  @$core.override
  GetServiceHealthRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetServiceHealthRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetServiceHealthRequest>(create);
  static GetServiceHealthRequest? _defaultInstance;
}

class GetServiceHealthResponse extends $pb.GeneratedMessage {
  factory GetServiceHealthResponse({
    $core.Iterable<ServiceHealth>? services,
  }) {
    final result = create();
    if (services != null) result.services.addAll(services);
    return result;
  }

  GetServiceHealthResponse._();

  factory GetServiceHealthResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetServiceHealthResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetServiceHealthResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<ServiceHealth>(1, _omitFieldNames ? '' : 'services',
        subBuilder: ServiceHealth.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServiceHealthResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetServiceHealthResponse copyWith(
          void Function(GetServiceHealthResponse) updates) =>
      super.copyWith((message) => updates(message as GetServiceHealthResponse))
          as GetServiceHealthResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetServiceHealthResponse create() => GetServiceHealthResponse._();
  @$core.override
  GetServiceHealthResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetServiceHealthResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetServiceHealthResponse>(create);
  static GetServiceHealthResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ServiceHealth> get services => $_getList(0);
}

class GetDashboardSummaryRequest extends $pb.GeneratedMessage {
  factory GetDashboardSummaryRequest() => create();

  GetDashboardSummaryRequest._();

  factory GetDashboardSummaryRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetDashboardSummaryRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetDashboardSummaryRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDashboardSummaryRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDashboardSummaryRequest copyWith(
          void Function(GetDashboardSummaryRequest) updates) =>
      super.copyWith(
              (message) => updates(message as GetDashboardSummaryRequest))
          as GetDashboardSummaryRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDashboardSummaryRequest create() => GetDashboardSummaryRequest._();
  @$core.override
  GetDashboardSummaryRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetDashboardSummaryRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetDashboardSummaryRequest>(create);
  static GetDashboardSummaryRequest? _defaultInstance;
}

class GetDashboardSummaryResponse extends $pb.GeneratedMessage {
  factory GetDashboardSummaryResponse({
    $core.int? totalTenants,
    $core.int? activeTenants,
    $core.int? totalSubscriptions,
    $core.String? monthlyRecurringRevenue,
    $core.Iterable<ServiceHealth>? health,
  }) {
    final result = create();
    if (totalTenants != null) result.totalTenants = totalTenants;
    if (activeTenants != null) result.activeTenants = activeTenants;
    if (totalSubscriptions != null)
      result.totalSubscriptions = totalSubscriptions;
    if (monthlyRecurringRevenue != null)
      result.monthlyRecurringRevenue = monthlyRecurringRevenue;
    if (health != null) result.health.addAll(health);
    return result;
  }

  GetDashboardSummaryResponse._();

  factory GetDashboardSummaryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetDashboardSummaryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetDashboardSummaryResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'totalTenants')
    ..aI(2, _omitFieldNames ? '' : 'activeTenants')
    ..aI(3, _omitFieldNames ? '' : 'totalSubscriptions')
    ..aOS(4, _omitFieldNames ? '' : 'monthlyRecurringRevenue')
    ..pPM<ServiceHealth>(5, _omitFieldNames ? '' : 'health',
        subBuilder: ServiceHealth.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDashboardSummaryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetDashboardSummaryResponse copyWith(
          void Function(GetDashboardSummaryResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GetDashboardSummaryResponse))
          as GetDashboardSummaryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetDashboardSummaryResponse create() =>
      GetDashboardSummaryResponse._();
  @$core.override
  GetDashboardSummaryResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetDashboardSummaryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetDashboardSummaryResponse>(create);
  static GetDashboardSummaryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get totalTenants => $_getIZ(0);
  @$pb.TagNumber(1)
  set totalTenants($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTotalTenants() => $_has(0);
  @$pb.TagNumber(1)
  void clearTotalTenants() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get activeTenants => $_getIZ(1);
  @$pb.TagNumber(2)
  set activeTenants($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasActiveTenants() => $_has(1);
  @$pb.TagNumber(2)
  void clearActiveTenants() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalSubscriptions => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalSubscriptions($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSubscriptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSubscriptions() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get monthlyRecurringRevenue => $_getSZ(3);
  @$pb.TagNumber(4)
  set monthlyRecurringRevenue($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMonthlyRecurringRevenue() => $_has(3);
  @$pb.TagNumber(4)
  void clearMonthlyRecurringRevenue() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<ServiceHealth> get health => $_getList(4);
}

class ExportTenantsCsvRequest extends $pb.GeneratedMessage {
  factory ExportTenantsCsvRequest() => create();

  ExportTenantsCsvRequest._();

  factory ExportTenantsCsvRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExportTenantsCsvRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportTenantsCsvRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportTenantsCsvRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportTenantsCsvRequest copyWith(
          void Function(ExportTenantsCsvRequest) updates) =>
      super.copyWith((message) => updates(message as ExportTenantsCsvRequest))
          as ExportTenantsCsvRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExportTenantsCsvRequest create() => ExportTenantsCsvRequest._();
  @$core.override
  ExportTenantsCsvRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExportTenantsCsvRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportTenantsCsvRequest>(create);
  static ExportTenantsCsvRequest? _defaultInstance;
}

class ExportTenantsCsvResponse extends $pb.GeneratedMessage {
  factory ExportTenantsCsvResponse({
    $core.List<$core.int>? chunk,
  }) {
    final result = create();
    if (chunk != null) result.chunk = chunk;
    return result;
  }

  ExportTenantsCsvResponse._();

  factory ExportTenantsCsvResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExportTenantsCsvResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportTenantsCsvResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'chunk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportTenantsCsvResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportTenantsCsvResponse copyWith(
          void Function(ExportTenantsCsvResponse) updates) =>
      super.copyWith((message) => updates(message as ExportTenantsCsvResponse))
          as ExportTenantsCsvResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExportTenantsCsvResponse create() => ExportTenantsCsvResponse._();
  @$core.override
  ExportTenantsCsvResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExportTenantsCsvResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportTenantsCsvResponse>(create);
  static ExportTenantsCsvResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get chunk => $_getN(0);
  @$pb.TagNumber(1)
  set chunk($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChunk() => $_has(0);
  @$pb.TagNumber(1)
  void clearChunk() => $_clearField(1);
}

/// --- Fase 6: Operacional (fila/Kanban/chat — WS-6) ---
class AtendimentoResumo extends $pb.GeneratedMessage {
  factory AtendimentoResumo({
    $core.int? id,
    $core.int? contatoId,
    $core.String? status,
    $core.int? departamentoId,
    $core.int? fluxoAtendimentoId,
    $core.int? etapaAtualId,
    $core.String? assunto,
    $core.String? prioridade,
    $core.int? atendenteHumanoId,
    $fixnum.Int64? dataInicio,
    $fixnum.Int64? dataUltimaMensagem,
    $core.int? sentimentoNota,
    $core.String? sentimentoLabel,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (contatoId != null) result.contatoId = contatoId;
    if (status != null) result.status = status;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (fluxoAtendimentoId != null)
      result.fluxoAtendimentoId = fluxoAtendimentoId;
    if (etapaAtualId != null) result.etapaAtualId = etapaAtualId;
    if (assunto != null) result.assunto = assunto;
    if (prioridade != null) result.prioridade = prioridade;
    if (atendenteHumanoId != null) result.atendenteHumanoId = atendenteHumanoId;
    if (dataInicio != null) result.dataInicio = dataInicio;
    if (dataUltimaMensagem != null)
      result.dataUltimaMensagem = dataUltimaMensagem;
    if (sentimentoNota != null) result.sentimentoNota = sentimentoNota;
    if (sentimentoLabel != null) result.sentimentoLabel = sentimentoLabel;
    return result;
  }

  AtendimentoResumo._();

  factory AtendimentoResumo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtendimentoResumo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtendimentoResumo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'contatoId')
    ..aOS(3, _omitFieldNames ? '' : 'status')
    ..aI(4, _omitFieldNames ? '' : 'departamentoId')
    ..aI(5, _omitFieldNames ? '' : 'fluxoAtendimentoId')
    ..aI(6, _omitFieldNames ? '' : 'etapaAtualId')
    ..aOS(7, _omitFieldNames ? '' : 'assunto')
    ..aOS(8, _omitFieldNames ? '' : 'prioridade')
    ..aI(9, _omitFieldNames ? '' : 'atendenteHumanoId')
    ..aInt64(10, _omitFieldNames ? '' : 'dataInicio')
    ..aInt64(11, _omitFieldNames ? '' : 'dataUltimaMensagem')
    ..aI(12, _omitFieldNames ? '' : 'sentimentoNota')
    ..aOS(13, _omitFieldNames ? '' : 'sentimentoLabel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoResumo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoResumo copyWith(void Function(AtendimentoResumo) updates) =>
      super.copyWith((message) => updates(message as AtendimentoResumo))
          as AtendimentoResumo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtendimentoResumo create() => AtendimentoResumo._();
  @$core.override
  AtendimentoResumo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtendimentoResumo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtendimentoResumo>(create);
  static AtendimentoResumo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get contatoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set contatoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContatoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearContatoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get status => $_getSZ(2);
  @$pb.TagNumber(3)
  set status($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get departamentoId => $_getIZ(3);
  @$pb.TagNumber(4)
  set departamentoId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDepartamentoId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDepartamentoId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get fluxoAtendimentoId => $_getIZ(4);
  @$pb.TagNumber(5)
  set fluxoAtendimentoId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFluxoAtendimentoId() => $_has(4);
  @$pb.TagNumber(5)
  void clearFluxoAtendimentoId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get etapaAtualId => $_getIZ(5);
  @$pb.TagNumber(6)
  set etapaAtualId($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEtapaAtualId() => $_has(5);
  @$pb.TagNumber(6)
  void clearEtapaAtualId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get assunto => $_getSZ(6);
  @$pb.TagNumber(7)
  set assunto($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAssunto() => $_has(6);
  @$pb.TagNumber(7)
  void clearAssunto() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get prioridade => $_getSZ(7);
  @$pb.TagNumber(8)
  set prioridade($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPrioridade() => $_has(7);
  @$pb.TagNumber(8)
  void clearPrioridade() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get atendenteHumanoId => $_getIZ(8);
  @$pb.TagNumber(9)
  set atendenteHumanoId($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAtendenteHumanoId() => $_has(8);
  @$pb.TagNumber(9)
  void clearAtendenteHumanoId() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get dataInicio => $_getI64(9);
  @$pb.TagNumber(10)
  set dataInicio($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDataInicio() => $_has(9);
  @$pb.TagNumber(10)
  void clearDataInicio() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get dataUltimaMensagem => $_getI64(10);
  @$pb.TagNumber(11)
  set dataUltimaMensagem($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDataUltimaMensagem() => $_has(10);
  @$pb.TagNumber(11)
  void clearDataUltimaMensagem() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get sentimentoNota => $_getIZ(11);
  @$pb.TagNumber(12)
  set sentimentoNota($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasSentimentoNota() => $_has(11);
  @$pb.TagNumber(12)
  void clearSentimentoNota() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get sentimentoLabel => $_getSZ(12);
  @$pb.TagNumber(13)
  set sentimentoLabel($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasSentimentoLabel() => $_has(12);
  @$pb.TagNumber(13)
  void clearSentimentoLabel() => $_clearField(13);
}

class ListAtendimentosRequest extends $pb.GeneratedMessage {
  factory ListAtendimentosRequest({
    $core.String? status,
    $core.int? departamentoId,
    $core.int? limit,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (limit != null) result.limit = limit;
    return result;
  }

  ListAtendimentosRequest._();

  factory ListAtendimentosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListAtendimentosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAtendimentosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..aI(2, _omitFieldNames ? '' : 'departamentoId')
    ..aI(3, _omitFieldNames ? '' : 'limit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAtendimentosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAtendimentosRequest copyWith(
          void Function(ListAtendimentosRequest) updates) =>
      super.copyWith((message) => updates(message as ListAtendimentosRequest))
          as ListAtendimentosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListAtendimentosRequest create() => ListAtendimentosRequest._();
  @$core.override
  ListAtendimentosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListAtendimentosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListAtendimentosRequest>(create);
  static ListAtendimentosRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get status => $_getSZ(0);
  @$pb.TagNumber(1)
  set status($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get departamentoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set departamentoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDepartamentoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDepartamentoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => $_clearField(3);
}

class ListAtendimentosResponse extends $pb.GeneratedMessage {
  factory ListAtendimentosResponse({
    $core.Iterable<AtendimentoResumo>? atendimentos,
  }) {
    final result = create();
    if (atendimentos != null) result.atendimentos.addAll(atendimentos);
    return result;
  }

  ListAtendimentosResponse._();

  factory ListAtendimentosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListAtendimentosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAtendimentosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<AtendimentoResumo>(1, _omitFieldNames ? '' : 'atendimentos',
        subBuilder: AtendimentoResumo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAtendimentosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAtendimentosResponse copyWith(
          void Function(ListAtendimentosResponse) updates) =>
      super.copyWith((message) => updates(message as ListAtendimentosResponse))
          as ListAtendimentosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListAtendimentosResponse create() => ListAtendimentosResponse._();
  @$core.override
  ListAtendimentosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListAtendimentosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListAtendimentosResponse>(create);
  static ListAtendimentosResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AtendimentoResumo> get atendimentos => $_getList(0);
}

class MensagemThread extends $pb.GeneratedMessage {
  factory MensagemThread({
    $core.int? id,
    $core.int? atendimentoId,
    $core.String? tipo,
    $core.String? conteudo,
    $core.String? remetente,
    $fixnum.Int64? timestamp,
    $core.String? statusEnvio,
    $core.bool? geradoPorIa,
    $core.String? resumoMidia,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (tipo != null) result.tipo = tipo;
    if (conteudo != null) result.conteudo = conteudo;
    if (remetente != null) result.remetente = remetente;
    if (timestamp != null) result.timestamp = timestamp;
    if (statusEnvio != null) result.statusEnvio = statusEnvio;
    if (geradoPorIa != null) result.geradoPorIa = geradoPorIa;
    if (resumoMidia != null) result.resumoMidia = resumoMidia;
    return result;
  }

  MensagemThread._();

  factory MensagemThread.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MensagemThread.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MensagemThread',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(3, _omitFieldNames ? '' : 'tipo')
    ..aOS(4, _omitFieldNames ? '' : 'conteudo')
    ..aOS(5, _omitFieldNames ? '' : 'remetente')
    ..aInt64(6, _omitFieldNames ? '' : 'timestamp')
    ..aOS(7, _omitFieldNames ? '' : 'statusEnvio')
    ..aOB(8, _omitFieldNames ? '' : 'geradoPorIa')
    ..aOS(9, _omitFieldNames ? '' : 'resumoMidia')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MensagemThread clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MensagemThread copyWith(void Function(MensagemThread) updates) =>
      super.copyWith((message) => updates(message as MensagemThread))
          as MensagemThread;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MensagemThread create() => MensagemThread._();
  @$core.override
  MensagemThread createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MensagemThread getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MensagemThread>(create);
  static MensagemThread? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get atendimentoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set atendimentoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtendimentoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtendimentoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tipo => $_getSZ(2);
  @$pb.TagNumber(3)
  set tipo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTipo() => $_has(2);
  @$pb.TagNumber(3)
  void clearTipo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get conteudo => $_getSZ(3);
  @$pb.TagNumber(4)
  set conteudo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConteudo() => $_has(3);
  @$pb.TagNumber(4)
  void clearConteudo() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get remetente => $_getSZ(4);
  @$pb.TagNumber(5)
  set remetente($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRemetente() => $_has(4);
  @$pb.TagNumber(5)
  void clearRemetente() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestamp => $_getI64(5);
  @$pb.TagNumber(6)
  set timestamp($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimestamp() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestamp() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get statusEnvio => $_getSZ(6);
  @$pb.TagNumber(7)
  set statusEnvio($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStatusEnvio() => $_has(6);
  @$pb.TagNumber(7)
  void clearStatusEnvio() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get geradoPorIa => $_getBF(7);
  @$pb.TagNumber(8)
  set geradoPorIa($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasGeradoPorIa() => $_has(7);
  @$pb.TagNumber(8)
  void clearGeradoPorIa() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get resumoMidia => $_getSZ(8);
  @$pb.TagNumber(9)
  set resumoMidia($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasResumoMidia() => $_has(8);
  @$pb.TagNumber(9)
  void clearResumoMidia() => $_clearField(9);
}

class GetThreadRequest extends $pb.GeneratedMessage {
  factory GetThreadRequest({
    $core.int? atendimentoId,
    $core.int? limit,
    $core.int? offset,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (limit != null) result.limit = limit;
    if (offset != null) result.offset = offset;
    return result;
  }

  GetThreadRequest._();

  factory GetThreadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetThreadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetThreadRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aI(2, _omitFieldNames ? '' : 'limit')
    ..aI(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadRequest copyWith(void Function(GetThreadRequest) updates) =>
      super.copyWith((message) => updates(message as GetThreadRequest))
          as GetThreadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetThreadRequest create() => GetThreadRequest._();
  @$core.override
  GetThreadRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetThreadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetThreadRequest>(create);
  static GetThreadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get offset => $_getIZ(2);
  @$pb.TagNumber(3)
  set offset($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);
}

class GetThreadResponse extends $pb.GeneratedMessage {
  factory GetThreadResponse({
    $core.Iterable<MensagemThread>? mensagens,
  }) {
    final result = create();
    if (mensagens != null) result.mensagens.addAll(mensagens);
    return result;
  }

  GetThreadResponse._();

  factory GetThreadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetThreadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetThreadResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MensagemThread>(1, _omitFieldNames ? '' : 'mensagens',
        subBuilder: MensagemThread.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadResponse copyWith(void Function(GetThreadResponse) updates) =>
      super.copyWith((message) => updates(message as GetThreadResponse))
          as GetThreadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetThreadResponse create() => GetThreadResponse._();
  @$core.override
  GetThreadResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetThreadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetThreadResponse>(create);
  static GetThreadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MensagemThread> get mensagens => $_getList(0);
}

class MoveAtendimentoEtapaRequest extends $pb.GeneratedMessage {
  factory MoveAtendimentoEtapaRequest({
    $core.int? atendimentoId,
    $core.int? etapaDestinoId,
    $core.String? motivo,
    $core.String? actionId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (etapaDestinoId != null) result.etapaDestinoId = etapaDestinoId;
    if (motivo != null) result.motivo = motivo;
    if (actionId != null) result.actionId = actionId;
    return result;
  }

  MoveAtendimentoEtapaRequest._();

  factory MoveAtendimentoEtapaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoveAtendimentoEtapaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveAtendimentoEtapaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aI(2, _omitFieldNames ? '' : 'etapaDestinoId')
    ..aOS(3, _omitFieldNames ? '' : 'motivo')
    ..aOS(4, _omitFieldNames ? '' : 'actionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveAtendimentoEtapaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveAtendimentoEtapaRequest copyWith(
          void Function(MoveAtendimentoEtapaRequest) updates) =>
      super.copyWith(
              (message) => updates(message as MoveAtendimentoEtapaRequest))
          as MoveAtendimentoEtapaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoveAtendimentoEtapaRequest create() =>
      MoveAtendimentoEtapaRequest._();
  @$core.override
  MoveAtendimentoEtapaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoveAtendimentoEtapaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoveAtendimentoEtapaRequest>(create);
  static MoveAtendimentoEtapaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get etapaDestinoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set etapaDestinoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEtapaDestinoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEtapaDestinoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get motivo => $_getSZ(2);
  @$pb.TagNumber(3)
  set motivo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMotivo() => $_has(2);
  @$pb.TagNumber(3)
  void clearMotivo() => $_clearField(3);

  /// N7.2: idempotência do sync offline. Campo aditivo/opcional — clientes
  /// antigos (sem action_id) seguem funcionando sem dedupe server-side.
  @$pb.TagNumber(4)
  $core.String get actionId => $_getSZ(3);
  @$pb.TagNumber(4)
  set actionId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasActionId() => $_has(3);
  @$pb.TagNumber(4)
  void clearActionId() => $_clearField(4);
}

class MoveAtendimentoEtapaResponse extends $pb.GeneratedMessage {
  factory MoveAtendimentoEtapaResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  MoveAtendimentoEtapaResponse._();

  factory MoveAtendimentoEtapaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoveAtendimentoEtapaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveAtendimentoEtapaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveAtendimentoEtapaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveAtendimentoEtapaResponse copyWith(
          void Function(MoveAtendimentoEtapaResponse) updates) =>
      super.copyWith(
              (message) => updates(message as MoveAtendimentoEtapaResponse))
          as MoveAtendimentoEtapaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoveAtendimentoEtapaResponse create() =>
      MoveAtendimentoEtapaResponse._();
  @$core.override
  MoveAtendimentoEtapaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoveAtendimentoEtapaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoveAtendimentoEtapaResponse>(create);
  static MoveAtendimentoEtapaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class SendOutboundMessageRequest extends $pb.GeneratedMessage {
  factory SendOutboundMessageRequest({
    $core.int? atendimentoId,
    $core.String? conteudo,
    $core.String? tipo,
    $core.String? actionId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (conteudo != null) result.conteudo = conteudo;
    if (tipo != null) result.tipo = tipo;
    if (actionId != null) result.actionId = actionId;
    return result;
  }

  SendOutboundMessageRequest._();

  factory SendOutboundMessageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendOutboundMessageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendOutboundMessageRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'conteudo')
    ..aOS(3, _omitFieldNames ? '' : 'tipo')
    ..aOS(4, _omitFieldNames ? '' : 'actionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendOutboundMessageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendOutboundMessageRequest copyWith(
          void Function(SendOutboundMessageRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SendOutboundMessageRequest))
          as SendOutboundMessageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendOutboundMessageRequest create() => SendOutboundMessageRequest._();
  @$core.override
  SendOutboundMessageRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendOutboundMessageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendOutboundMessageRequest>(create);
  static SendOutboundMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get conteudo => $_getSZ(1);
  @$pb.TagNumber(2)
  set conteudo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConteudo() => $_has(1);
  @$pb.TagNumber(2)
  void clearConteudo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tipo => $_getSZ(2);
  @$pb.TagNumber(3)
  set tipo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTipo() => $_has(2);
  @$pb.TagNumber(3)
  void clearTipo() => $_clearField(3);

  /// N7.2: idempotência do sync offline. Campo aditivo/opcional — clientes
  /// antigos (sem action_id) seguem funcionando sem dedupe server-side.
  @$pb.TagNumber(4)
  $core.String get actionId => $_getSZ(3);
  @$pb.TagNumber(4)
  set actionId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasActionId() => $_has(3);
  @$pb.TagNumber(4)
  void clearActionId() => $_clearField(4);
}

class SendOutboundMessageResponse extends $pb.GeneratedMessage {
  factory SendOutboundMessageResponse({
    $core.int? messageId,
  }) {
    final result = create();
    if (messageId != null) result.messageId = messageId;
    return result;
  }

  SendOutboundMessageResponse._();

  factory SendOutboundMessageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendOutboundMessageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendOutboundMessageResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'messageId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendOutboundMessageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendOutboundMessageResponse copyWith(
          void Function(SendOutboundMessageResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SendOutboundMessageResponse))
          as SendOutboundMessageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendOutboundMessageResponse create() =>
      SendOutboundMessageResponse._();
  @$core.override
  SendOutboundMessageResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendOutboundMessageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendOutboundMessageResponse>(create);
  static SendOutboundMessageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get messageId => $_getIZ(0);
  @$pb.TagNumber(1)
  set messageId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => $_clearField(1);
}

class CreateInviteRequest extends $pb.GeneratedMessage {
  factory CreateInviteRequest({
    $core.String? email,
    $core.String? name,
    $core.String? role,
    $core.Iterable<$core.String>? modulePermissions,
    $core.Iterable<$core.int>? flowPermissions,
  }) {
    final result = create();
    if (email != null) result.email = email;
    if (name != null) result.name = name;
    if (role != null) result.role = role;
    if (modulePermissions != null)
      result.modulePermissions.addAll(modulePermissions);
    if (flowPermissions != null) result.flowPermissions.addAll(flowPermissions);
    return result;
  }

  CreateInviteRequest._();

  factory CreateInviteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateInviteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateInviteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..pPS(4, _omitFieldNames ? '' : 'modulePermissions')
    ..p<$core.int>(
        5, _omitFieldNames ? '' : 'flowPermissions', $pb.PbFieldType.K3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInviteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInviteRequest copyWith(void Function(CreateInviteRequest) updates) =>
      super.copyWith((message) => updates(message as CreateInviteRequest))
          as CreateInviteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateInviteRequest create() => CreateInviteRequest._();
  @$core.override
  CreateInviteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateInviteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateInviteRequest>(create);
  static CreateInviteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get modulePermissions => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.int> get flowPermissions => $_getList(4);
}

/// Convite recém-criado. É o ÚNICO ponto onde o `token` é exposto (momento da
/// criação); as listagens jamais o retornam.
class TenantInviteCreated extends $pb.GeneratedMessage {
  factory TenantInviteCreated({
    $core.String? id,
    $core.String? tenantId,
    $core.String? email,
    $core.String? name,
    $core.String? role,
    $core.String? token,
    $fixnum.Int64? expiresAt,
    $core.bool? used,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (tenantId != null) result.tenantId = tenantId;
    if (email != null) result.email = email;
    if (name != null) result.name = name;
    if (role != null) result.role = role;
    if (token != null) result.token = token;
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (used != null) result.used = used;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  TenantInviteCreated._();

  factory TenantInviteCreated.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TenantInviteCreated.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TenantInviteCreated',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'tenantId')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'name')
    ..aOS(5, _omitFieldNames ? '' : 'role')
    ..aOS(6, _omitFieldNames ? '' : 'token')
    ..aInt64(7, _omitFieldNames ? '' : 'expiresAt')
    ..aOB(8, _omitFieldNames ? '' : 'used')
    ..aInt64(9, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantInviteCreated clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantInviteCreated copyWith(void Function(TenantInviteCreated) updates) =>
      super.copyWith((message) => updates(message as TenantInviteCreated))
          as TenantInviteCreated;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TenantInviteCreated create() => TenantInviteCreated._();
  @$core.override
  TenantInviteCreated createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TenantInviteCreated getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TenantInviteCreated>(create);
  static TenantInviteCreated? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tenantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tenantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTenantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTenantId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get name => $_getSZ(3);
  @$pb.TagNumber(4)
  set name($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasName() => $_has(3);
  @$pb.TagNumber(4)
  void clearName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get role => $_getSZ(4);
  @$pb.TagNumber(5)
  set role($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRole() => $_has(4);
  @$pb.TagNumber(5)
  void clearRole() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get token => $_getSZ(5);
  @$pb.TagNumber(6)
  set token($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearToken() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get expiresAt => $_getI64(6);
  @$pb.TagNumber(7)
  set expiresAt($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExpiresAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearExpiresAt() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get used => $_getBF(7);
  @$pb.TagNumber(8)
  set used($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasUsed() => $_has(7);
  @$pb.TagNumber(8)
  void clearUsed() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get createdAt => $_getI64(8);
  @$pb.TagNumber(9)
  set createdAt($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCreatedAt() => $_has(8);
  @$pb.TagNumber(9)
  void clearCreatedAt() => $_clearField(9);
}

class CreateInviteResponse extends $pb.GeneratedMessage {
  factory CreateInviteResponse({
    TenantInviteCreated? invite,
  }) {
    final result = create();
    if (invite != null) result.invite = invite;
    return result;
  }

  CreateInviteResponse._();

  factory CreateInviteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateInviteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateInviteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<TenantInviteCreated>(1, _omitFieldNames ? '' : 'invite',
        subBuilder: TenantInviteCreated.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInviteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateInviteResponse copyWith(void Function(CreateInviteResponse) updates) =>
      super.copyWith((message) => updates(message as CreateInviteResponse))
          as CreateInviteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateInviteResponse create() => CreateInviteResponse._();
  @$core.override
  CreateInviteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateInviteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateInviteResponse>(create);
  static CreateInviteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  TenantInviteCreated get invite => $_getN(0);
  @$pb.TagNumber(1)
  set invite(TenantInviteCreated value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasInvite() => $_has(0);
  @$pb.TagNumber(1)
  void clearInvite() => $_clearField(1);
  @$pb.TagNumber(1)
  TenantInviteCreated ensureInvite() => $_ensure(0);
}

/// Rota PÚBLICA (sem sessão): o convidado cria a própria conta a partir do token.
class AcceptInviteRequest extends $pb.GeneratedMessage {
  factory AcceptInviteRequest({
    $core.String? token,
    $core.String? username,
    $core.String? email,
    $core.String? password,
  }) {
    final result = create();
    if (token != null) result.token = token;
    if (username != null) result.username = username;
    if (email != null) result.email = email;
    if (password != null) result.password = password;
    return result;
  }

  AcceptInviteRequest._();

  factory AcceptInviteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AcceptInviteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcceptInviteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptInviteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptInviteRequest copyWith(void Function(AcceptInviteRequest) updates) =>
      super.copyWith((message) => updates(message as AcceptInviteRequest))
          as AcceptInviteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AcceptInviteRequest create() => AcceptInviteRequest._();
  @$core.override
  AcceptInviteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AcceptInviteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AcceptInviteRequest>(create);
  static AcceptInviteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get password => $_getSZ(3);
  @$pb.TagNumber(4)
  set password($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPassword() => $_has(3);
  @$pb.TagNumber(4)
  void clearPassword() => $_clearField(4);
}

class AcceptedTenantUser extends $pb.GeneratedMessage {
  factory AcceptedTenantUser({
    $core.int? id,
    $core.int? userId,
    $core.String? tenantId,
    $core.String? role,
    $core.Iterable<$core.String>? modulePermissions,
    $core.Iterable<$core.int>? flowPermissions,
    $core.bool? isActive,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (userId != null) result.userId = userId;
    if (tenantId != null) result.tenantId = tenantId;
    if (role != null) result.role = role;
    if (modulePermissions != null)
      result.modulePermissions.addAll(modulePermissions);
    if (flowPermissions != null) result.flowPermissions.addAll(flowPermissions);
    if (isActive != null) result.isActive = isActive;
    return result;
  }

  AcceptedTenantUser._();

  factory AcceptedTenantUser.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AcceptedTenantUser.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcceptedTenantUser',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'tenantId')
    ..aOS(4, _omitFieldNames ? '' : 'role')
    ..pPS(5, _omitFieldNames ? '' : 'modulePermissions')
    ..p<$core.int>(
        6, _omitFieldNames ? '' : 'flowPermissions', $pb.PbFieldType.K3)
    ..aOB(7, _omitFieldNames ? '' : 'isActive')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptedTenantUser clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptedTenantUser copyWith(void Function(AcceptedTenantUser) updates) =>
      super.copyWith((message) => updates(message as AcceptedTenantUser))
          as AcceptedTenantUser;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AcceptedTenantUser create() => AcceptedTenantUser._();
  @$core.override
  AcceptedTenantUser createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AcceptedTenantUser getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AcceptedTenantUser>(create);
  static AcceptedTenantUser? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tenantId => $_getSZ(2);
  @$pb.TagNumber(3)
  set tenantId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTenantId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTenantId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get role => $_getSZ(3);
  @$pb.TagNumber(4)
  set role($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRole() => $_has(3);
  @$pb.TagNumber(4)
  void clearRole() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get modulePermissions => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.int> get flowPermissions => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get isActive => $_getBF(6);
  @$pb.TagNumber(7)
  set isActive($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsActive() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsActive() => $_clearField(7);
}

class AcceptInviteResponse extends $pb.GeneratedMessage {
  factory AcceptInviteResponse({
    AcceptedTenantUser? tenantUser,
  }) {
    final result = create();
    if (tenantUser != null) result.tenantUser = tenantUser;
    return result;
  }

  AcceptInviteResponse._();

  factory AcceptInviteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AcceptInviteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcceptInviteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<AcceptedTenantUser>(1, _omitFieldNames ? '' : 'tenantUser',
        subBuilder: AcceptedTenantUser.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptInviteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcceptInviteResponse copyWith(void Function(AcceptInviteResponse) updates) =>
      super.copyWith((message) => updates(message as AcceptInviteResponse))
          as AcceptInviteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AcceptInviteResponse create() => AcceptInviteResponse._();
  @$core.override
  AcceptInviteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AcceptInviteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AcceptInviteResponse>(create);
  static AcceptInviteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  AcceptedTenantUser get tenantUser => $_getN(0);
  @$pb.TagNumber(1)
  set tenantUser(AcceptedTenantUser value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantUser() => $_clearField(1);
  @$pb.TagNumber(1)
  AcceptedTenantUser ensureTenantUser() => $_ensure(0);
}

class ListInvitesRequest extends $pb.GeneratedMessage {
  factory ListInvitesRequest() => create();

  ListInvitesRequest._();

  factory ListInvitesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListInvitesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListInvitesRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInvitesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInvitesRequest copyWith(void Function(ListInvitesRequest) updates) =>
      super.copyWith((message) => updates(message as ListInvitesRequest))
          as ListInvitesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListInvitesRequest create() => ListInvitesRequest._();
  @$core.override
  ListInvitesRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListInvitesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListInvitesRequest>(create);
  static ListInvitesRequest? _defaultInstance;
}

class TenantInviteItem extends $pb.GeneratedMessage {
  factory TenantInviteItem({
    $core.String? id,
    $core.String? email,
    $core.String? name,
    $core.String? role,
    $core.Iterable<$core.String>? modulePermissions,
    $core.Iterable<$core.int>? flowPermissions,
    $fixnum.Int64? expiresAt,
    $core.bool? used,
    $core.bool? revoked,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (email != null) result.email = email;
    if (name != null) result.name = name;
    if (role != null) result.role = role;
    if (modulePermissions != null)
      result.modulePermissions.addAll(modulePermissions);
    if (flowPermissions != null) result.flowPermissions.addAll(flowPermissions);
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (used != null) result.used = used;
    if (revoked != null) result.revoked = revoked;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  TenantInviteItem._();

  factory TenantInviteItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TenantInviteItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TenantInviteItem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'email')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOS(4, _omitFieldNames ? '' : 'role')
    ..pPS(5, _omitFieldNames ? '' : 'modulePermissions')
    ..p<$core.int>(
        6, _omitFieldNames ? '' : 'flowPermissions', $pb.PbFieldType.K3)
    ..aInt64(7, _omitFieldNames ? '' : 'expiresAt')
    ..aOB(8, _omitFieldNames ? '' : 'used')
    ..aOB(9, _omitFieldNames ? '' : 'revoked')
    ..aInt64(10, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantInviteItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantInviteItem copyWith(void Function(TenantInviteItem) updates) =>
      super.copyWith((message) => updates(message as TenantInviteItem))
          as TenantInviteItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TenantInviteItem create() => TenantInviteItem._();
  @$core.override
  TenantInviteItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TenantInviteItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TenantInviteItem>(create);
  static TenantInviteItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get email => $_getSZ(1);
  @$pb.TagNumber(2)
  set email($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmail() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmail() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get role => $_getSZ(3);
  @$pb.TagNumber(4)
  set role($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRole() => $_has(3);
  @$pb.TagNumber(4)
  void clearRole() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get modulePermissions => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.int> get flowPermissions => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get expiresAt => $_getI64(6);
  @$pb.TagNumber(7)
  set expiresAt($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExpiresAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearExpiresAt() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get used => $_getBF(7);
  @$pb.TagNumber(8)
  set used($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasUsed() => $_has(7);
  @$pb.TagNumber(8)
  void clearUsed() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get revoked => $_getBF(8);
  @$pb.TagNumber(9)
  set revoked($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRevoked() => $_has(8);
  @$pb.TagNumber(9)
  void clearRevoked() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get createdAt => $_getI64(9);
  @$pb.TagNumber(10)
  set createdAt($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedAt() => $_clearField(10);
}

class ListInvitesResponse extends $pb.GeneratedMessage {
  factory ListInvitesResponse({
    $core.Iterable<TenantInviteItem>? invites,
  }) {
    final result = create();
    if (invites != null) result.invites.addAll(invites);
    return result;
  }

  ListInvitesResponse._();

  factory ListInvitesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListInvitesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListInvitesResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<TenantInviteItem>(1, _omitFieldNames ? '' : 'invites',
        subBuilder: TenantInviteItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInvitesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListInvitesResponse copyWith(void Function(ListInvitesResponse) updates) =>
      super.copyWith((message) => updates(message as ListInvitesResponse))
          as ListInvitesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListInvitesResponse create() => ListInvitesResponse._();
  @$core.override
  ListInvitesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListInvitesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListInvitesResponse>(create);
  static ListInvitesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TenantInviteItem> get invites => $_getList(0);
}

class RevokeInviteRequest extends $pb.GeneratedMessage {
  factory RevokeInviteRequest({
    $core.String? inviteId,
  }) {
    final result = create();
    if (inviteId != null) result.inviteId = inviteId;
    return result;
  }

  RevokeInviteRequest._();

  factory RevokeInviteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeInviteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeInviteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'inviteId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeInviteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeInviteRequest copyWith(void Function(RevokeInviteRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeInviteRequest))
          as RevokeInviteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeInviteRequest create() => RevokeInviteRequest._();
  @$core.override
  RevokeInviteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeInviteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeInviteRequest>(create);
  static RevokeInviteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get inviteId => $_getSZ(0);
  @$pb.TagNumber(1)
  set inviteId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInviteId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInviteId() => $_clearField(1);
}

class RevokeInviteResponse extends $pb.GeneratedMessage {
  factory RevokeInviteResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  RevokeInviteResponse._();

  factory RevokeInviteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeInviteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeInviteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeInviteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeInviteResponse copyWith(void Function(RevokeInviteResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeInviteResponse))
          as RevokeInviteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeInviteResponse create() => RevokeInviteResponse._();
  @$core.override
  RevokeInviteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeInviteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeInviteResponse>(create);
  static RevokeInviteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class ListTenantUsersRequest extends $pb.GeneratedMessage {
  factory ListTenantUsersRequest() => create();

  ListTenantUsersRequest._();

  factory ListTenantUsersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTenantUsersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTenantUsersRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantUsersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantUsersRequest copyWith(
          void Function(ListTenantUsersRequest) updates) =>
      super.copyWith((message) => updates(message as ListTenantUsersRequest))
          as ListTenantUsersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTenantUsersRequest create() => ListTenantUsersRequest._();
  @$core.override
  ListTenantUsersRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTenantUsersRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTenantUsersRequest>(create);
  static ListTenantUsersRequest? _defaultInstance;
}

class TenantUserItem extends $pb.GeneratedMessage {
  factory TenantUserItem({
    $core.int? id,
    $core.int? userId,
    $core.String? role,
    $core.Iterable<$core.String>? modulePermissions,
    $core.Iterable<$core.int>? flowPermissions,
    $core.bool? isActive,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (userId != null) result.userId = userId;
    if (role != null) result.role = role;
    if (modulePermissions != null)
      result.modulePermissions.addAll(modulePermissions);
    if (flowPermissions != null) result.flowPermissions.addAll(flowPermissions);
    if (isActive != null) result.isActive = isActive;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  TenantUserItem._();

  factory TenantUserItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TenantUserItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TenantUserItem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..pPS(4, _omitFieldNames ? '' : 'modulePermissions')
    ..p<$core.int>(
        5, _omitFieldNames ? '' : 'flowPermissions', $pb.PbFieldType.K3)
    ..aOB(6, _omitFieldNames ? '' : 'isActive')
    ..aInt64(7, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantUserItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TenantUserItem copyWith(void Function(TenantUserItem) updates) =>
      super.copyWith((message) => updates(message as TenantUserItem))
          as TenantUserItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TenantUserItem create() => TenantUserItem._();
  @$core.override
  TenantUserItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TenantUserItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TenantUserItem>(create);
  static TenantUserItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get userId => $_getIZ(1);
  @$pb.TagNumber(2)
  set userId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get modulePermissions => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.int> get flowPermissions => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get isActive => $_getBF(5);
  @$pb.TagNumber(6)
  set isActive($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsActive() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsActive() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAt => $_getI64(6);
  @$pb.TagNumber(7)
  set createdAt($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAt() => $_clearField(7);
}

class ListTenantUsersResponse extends $pb.GeneratedMessage {
  factory ListTenantUsersResponse({
    $core.Iterable<TenantUserItem>? users,
  }) {
    final result = create();
    if (users != null) result.users.addAll(users);
    return result;
  }

  ListTenantUsersResponse._();

  factory ListTenantUsersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTenantUsersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTenantUsersResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<TenantUserItem>(1, _omitFieldNames ? '' : 'users',
        subBuilder: TenantUserItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantUsersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTenantUsersResponse copyWith(
          void Function(ListTenantUsersResponse) updates) =>
      super.copyWith((message) => updates(message as ListTenantUsersResponse))
          as ListTenantUsersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTenantUsersResponse create() => ListTenantUsersResponse._();
  @$core.override
  ListTenantUsersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTenantUsersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTenantUsersResponse>(create);
  static ListTenantUsersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TenantUserItem> get users => $_getList(0);
}

/// Campos opcionais em proto3: como não há `optional`/wrappers no projeto e listas
/// repetidas não distinguem "vazio" de "ausente", usamos flags companion `set_*`.
/// Só os campos com a flag correspondente `true` são alterados no data_postgres.
class UpdateTenantUserRequest extends $pb.GeneratedMessage {
  factory UpdateTenantUserRequest({
    $core.int? userId,
    $core.bool? setRole,
    $core.String? role,
    $core.bool? setModulePermissions,
    $core.Iterable<$core.String>? modulePermissions,
    $core.bool? setFlowPermissions,
    $core.Iterable<$core.int>? flowPermissions,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (setRole != null) result.setRole = setRole;
    if (role != null) result.role = role;
    if (setModulePermissions != null)
      result.setModulePermissions = setModulePermissions;
    if (modulePermissions != null)
      result.modulePermissions.addAll(modulePermissions);
    if (setFlowPermissions != null)
      result.setFlowPermissions = setFlowPermissions;
    if (flowPermissions != null) result.flowPermissions.addAll(flowPermissions);
    return result;
  }

  UpdateTenantUserRequest._();

  factory UpdateTenantUserRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantUserRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantUserRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOB(2, _omitFieldNames ? '' : 'setRole')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..aOB(4, _omitFieldNames ? '' : 'setModulePermissions')
    ..pPS(5, _omitFieldNames ? '' : 'modulePermissions')
    ..aOB(6, _omitFieldNames ? '' : 'setFlowPermissions')
    ..p<$core.int>(
        7, _omitFieldNames ? '' : 'flowPermissions', $pb.PbFieldType.K3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantUserRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantUserRequest copyWith(
          void Function(UpdateTenantUserRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateTenantUserRequest))
          as UpdateTenantUserRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantUserRequest create() => UpdateTenantUserRequest._();
  @$core.override
  UpdateTenantUserRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantUserRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantUserRequest>(create);
  static UpdateTenantUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get setRole => $_getBF(1);
  @$pb.TagNumber(2)
  set setRole($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSetRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearSetRole() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get setModulePermissions => $_getBF(3);
  @$pb.TagNumber(4)
  set setModulePermissions($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSetModulePermissions() => $_has(3);
  @$pb.TagNumber(4)
  void clearSetModulePermissions() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get modulePermissions => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get setFlowPermissions => $_getBF(5);
  @$pb.TagNumber(6)
  set setFlowPermissions($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSetFlowPermissions() => $_has(5);
  @$pb.TagNumber(6)
  void clearSetFlowPermissions() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<$core.int> get flowPermissions => $_getList(6);
}

class UpdateTenantUserResponse extends $pb.GeneratedMessage {
  factory UpdateTenantUserResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  UpdateTenantUserResponse._();

  factory UpdateTenantUserResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTenantUserResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTenantUserResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantUserResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTenantUserResponse copyWith(
          void Function(UpdateTenantUserResponse) updates) =>
      super.copyWith((message) => updates(message as UpdateTenantUserResponse))
          as UpdateTenantUserResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTenantUserResponse create() => UpdateTenantUserResponse._();
  @$core.override
  UpdateTenantUserResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTenantUserResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTenantUserResponse>(create);
  static UpdateTenantUserResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class CreateMyWhatsappInstanceRequest extends $pb.GeneratedMessage {
  factory CreateMyWhatsappInstanceRequest({
    $core.String? instanceName,
  }) {
    final result = create();
    if (instanceName != null) result.instanceName = instanceName;
    return result;
  }

  CreateMyWhatsappInstanceRequest._();

  factory CreateMyWhatsappInstanceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyWhatsappInstanceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyWhatsappInstanceRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'instanceName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyWhatsappInstanceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyWhatsappInstanceRequest copyWith(
          void Function(CreateMyWhatsappInstanceRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateMyWhatsappInstanceRequest))
          as CreateMyWhatsappInstanceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyWhatsappInstanceRequest create() =>
      CreateMyWhatsappInstanceRequest._();
  @$core.override
  CreateMyWhatsappInstanceRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyWhatsappInstanceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyWhatsappInstanceRequest>(
          create);
  static CreateMyWhatsappInstanceRequest? _defaultInstance;

  /// Nome da instância no provedor. Precisa ser único entre todos os tenants.
  @$pb.TagNumber(1)
  $core.String get instanceName => $_getSZ(0);
  @$pb.TagNumber(1)
  set instanceName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstanceName() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstanceName() => $_clearField(1);
}

class CreateMyWhatsappInstanceResponse extends $pb.GeneratedMessage {
  factory CreateMyWhatsappInstanceResponse({
    $core.int? id,
    $core.String? instanceName,
    $core.String? provider,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (instanceName != null) result.instanceName = instanceName;
    if (provider != null) result.provider = provider;
    return result;
  }

  CreateMyWhatsappInstanceResponse._();

  factory CreateMyWhatsappInstanceResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyWhatsappInstanceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyWhatsappInstanceResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'instanceName')
    ..aOS(3, _omitFieldNames ? '' : 'provider')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyWhatsappInstanceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyWhatsappInstanceResponse copyWith(
          void Function(CreateMyWhatsappInstanceResponse) updates) =>
      super.copyWith(
              (message) => updates(message as CreateMyWhatsappInstanceResponse))
          as CreateMyWhatsappInstanceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyWhatsappInstanceResponse create() =>
      CreateMyWhatsappInstanceResponse._();
  @$core.override
  CreateMyWhatsappInstanceResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyWhatsappInstanceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyWhatsappInstanceResponse>(
          create);
  static CreateMyWhatsappInstanceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get instanceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set instanceName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstanceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstanceName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get provider => $_getSZ(2);
  @$pb.TagNumber(3)
  set provider($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProvider() => $_has(2);
  @$pb.TagNumber(3)
  void clearProvider() => $_clearField(3);
}

class GetMyWhatsappInstanceStatusRequest extends $pb.GeneratedMessage {
  factory GetMyWhatsappInstanceStatusRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  GetMyWhatsappInstanceStatusRequest._();

  factory GetMyWhatsappInstanceStatusRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyWhatsappInstanceStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyWhatsappInstanceStatusRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyWhatsappInstanceStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyWhatsappInstanceStatusRequest copyWith(
          void Function(GetMyWhatsappInstanceStatusRequest) updates) =>
      super.copyWith((message) =>
              updates(message as GetMyWhatsappInstanceStatusRequest))
          as GetMyWhatsappInstanceStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyWhatsappInstanceStatusRequest create() =>
      GetMyWhatsappInstanceStatusRequest._();
  @$core.override
  GetMyWhatsappInstanceStatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyWhatsappInstanceStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyWhatsappInstanceStatusRequest>(
          create);
  static GetMyWhatsappInstanceStatusRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class GetMyWhatsappInstanceStatusResponse extends $pb.GeneratedMessage {
  factory GetMyWhatsappInstanceStatusResponse({
    $core.String? connectionState,
    $core.String? qrCode,
  }) {
    final result = create();
    if (connectionState != null) result.connectionState = connectionState;
    if (qrCode != null) result.qrCode = qrCode;
    return result;
  }

  GetMyWhatsappInstanceStatusResponse._();

  factory GetMyWhatsappInstanceStatusResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyWhatsappInstanceStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyWhatsappInstanceStatusResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'connectionState')
    ..aOS(2, _omitFieldNames ? '' : 'qrCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyWhatsappInstanceStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyWhatsappInstanceStatusResponse copyWith(
          void Function(GetMyWhatsappInstanceStatusResponse) updates) =>
      super.copyWith((message) =>
              updates(message as GetMyWhatsappInstanceStatusResponse))
          as GetMyWhatsappInstanceStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyWhatsappInstanceStatusResponse create() =>
      GetMyWhatsappInstanceStatusResponse._();
  @$core.override
  GetMyWhatsappInstanceStatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyWhatsappInstanceStatusResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          GetMyWhatsappInstanceStatusResponse>(create);
  static GetMyWhatsappInstanceStatusResponse? _defaultInstance;

  /// `connected`, `disconnected`, `connecting` ou `unknown`.
  @$pb.TagNumber(1)
  $core.String get connectionState => $_getSZ(0);
  @$pb.TagNumber(1)
  set connectionState($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionState() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionState() => $_clearField(1);

  /// QR em base64 para o pareamento; vazio quando já conectado (ou quando o
  /// provedor ainda não o gerou).
  @$pb.TagNumber(2)
  $core.String get qrCode => $_getSZ(1);
  @$pb.TagNumber(2)
  set qrCode($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQrCode() => $_has(1);
  @$pb.TagNumber(2)
  void clearQrCode() => $_clearField(2);
}

class CreateMyDepartamentoRequest extends $pb.GeneratedMessage {
  factory CreateMyDepartamentoRequest({
    $core.String? nome,
    $core.String? descricao,
  }) {
    final result = create();
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    return result;
  }

  CreateMyDepartamentoRequest._();

  factory CreateMyDepartamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyDepartamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyDepartamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nome')
    ..aOS(2, _omitFieldNames ? '' : 'descricao')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyDepartamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyDepartamentoRequest copyWith(
          void Function(CreateMyDepartamentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateMyDepartamentoRequest))
          as CreateMyDepartamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyDepartamentoRequest create() =>
      CreateMyDepartamentoRequest._();
  @$core.override
  CreateMyDepartamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyDepartamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyDepartamentoRequest>(create);
  static CreateMyDepartamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nome => $_getSZ(0);
  @$pb.TagNumber(1)
  set nome($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNome() => $_has(0);
  @$pb.TagNumber(1)
  void clearNome() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get descricao => $_getSZ(1);
  @$pb.TagNumber(2)
  set descricao($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescricao() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescricao() => $_clearField(2);
}

class CreateMyDepartamentoResponse extends $pb.GeneratedMessage {
  factory CreateMyDepartamentoResponse({
    $core.int? id,
    $core.String? nome,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    return result;
  }

  CreateMyDepartamentoResponse._();

  factory CreateMyDepartamentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyDepartamentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyDepartamentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyDepartamentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyDepartamentoResponse copyWith(
          void Function(CreateMyDepartamentoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as CreateMyDepartamentoResponse))
          as CreateMyDepartamentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyDepartamentoResponse create() =>
      CreateMyDepartamentoResponse._();
  @$core.override
  CreateMyDepartamentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyDepartamentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyDepartamentoResponse>(create);
  static CreateMyDepartamentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nome => $_getSZ(1);
  @$pb.TagNumber(2)
  set nome($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNome() => $_has(1);
  @$pb.TagNumber(2)
  void clearNome() => $_clearField(2);
}

/// Define a persona do bot no passo 7.
///
/// RPC dedicado, e não `UpdateMyTenantConfig`: aquele carrega o objeto de
/// configuração inteiro, e em proto3 um campo não preenchido chega como string
/// vazia — o UPSERT do `data_postgres` faz `COALESCE(EXCLUDED.campo, atual)`, de
/// modo que "" SOBRESCREVE o valor existente. Mandar só a persona por ali
/// apagaria modelo de LLM, thresholds e o resto da configuração de IA.
class SetMyBotPersonaRequest extends $pb.GeneratedMessage {
  factory SetMyBotPersonaRequest({
    $core.String? personaBot,
    $core.String? botAgentName,
  }) {
    final result = create();
    if (personaBot != null) result.personaBot = personaBot;
    if (botAgentName != null) result.botAgentName = botAgentName;
    return result;
  }

  SetMyBotPersonaRequest._();

  factory SetMyBotPersonaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetMyBotPersonaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMyBotPersonaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'personaBot')
    ..aOS(2, _omitFieldNames ? '' : 'botAgentName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyBotPersonaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyBotPersonaRequest copyWith(
          void Function(SetMyBotPersonaRequest) updates) =>
      super.copyWith((message) => updates(message as SetMyBotPersonaRequest))
          as SetMyBotPersonaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetMyBotPersonaRequest create() => SetMyBotPersonaRequest._();
  @$core.override
  SetMyBotPersonaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetMyBotPersonaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMyBotPersonaRequest>(create);
  static SetMyBotPersonaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get personaBot => $_getSZ(0);
  @$pb.TagNumber(1)
  set personaBot($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPersonaBot() => $_has(0);
  @$pb.TagNumber(1)
  void clearPersonaBot() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get botAgentName => $_getSZ(1);
  @$pb.TagNumber(2)
  set botAgentName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBotAgentName() => $_has(1);
  @$pb.TagNumber(2)
  void clearBotAgentName() => $_clearField(2);
}

class SetMyBotPersonaResponse extends $pb.GeneratedMessage {
  factory SetMyBotPersonaResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  SetMyBotPersonaResponse._();

  factory SetMyBotPersonaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetMyBotPersonaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMyBotPersonaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyBotPersonaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyBotPersonaResponse copyWith(
          void Function(SetMyBotPersonaResponse) updates) =>
      super.copyWith((message) => updates(message as SetMyBotPersonaResponse))
          as SetMyBotPersonaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetMyBotPersonaResponse create() => SetMyBotPersonaResponse._();
  @$core.override
  SetMyBotPersonaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetMyBotPersonaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMyBotPersonaResponse>(create);
  static SetMyBotPersonaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

/// Registra até onde o tenant chegou na configuração guiada.
///
/// O progresso vive no servidor, e não no app, para que fechar o programa e
/// reabrir continue de onde parou — num app instalado isso é o esperado.
class SetOnboardingProgressRequest extends $pb.GeneratedMessage {
  factory SetOnboardingProgressRequest({
    $core.int? passo,
    $core.bool? concluido,
  }) {
    final result = create();
    if (passo != null) result.passo = passo;
    if (concluido != null) result.concluido = concluido;
    return result;
  }

  SetOnboardingProgressRequest._();

  factory SetOnboardingProgressRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetOnboardingProgressRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetOnboardingProgressRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'passo')
    ..aOB(2, _omitFieldNames ? '' : 'concluido')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOnboardingProgressRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOnboardingProgressRequest copyWith(
          void Function(SetOnboardingProgressRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SetOnboardingProgressRequest))
          as SetOnboardingProgressRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetOnboardingProgressRequest create() =>
      SetOnboardingProgressRequest._();
  @$core.override
  SetOnboardingProgressRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetOnboardingProgressRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetOnboardingProgressRequest>(create);
  static SetOnboardingProgressRequest? _defaultInstance;

  /// 5..8. O passo 8 conclui o roteiro e marca `setup_completed`.
  @$pb.TagNumber(1)
  $core.int get passo => $_getIZ(0);
  @$pb.TagNumber(1)
  set passo($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasso() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasso() => $_clearField(1);

  /// true = o tenant terminou (ou pulou o que faltava) e vai para o workspace.
  @$pb.TagNumber(2)
  $core.bool get concluido => $_getBF(1);
  @$pb.TagNumber(2)
  set concluido($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConcluido() => $_has(1);
  @$pb.TagNumber(2)
  void clearConcluido() => $_clearField(2);
}

class SetOnboardingProgressResponse extends $pb.GeneratedMessage {
  factory SetOnboardingProgressResponse({
    $core.int? passo,
    $core.bool? concluido,
  }) {
    final result = create();
    if (passo != null) result.passo = passo;
    if (concluido != null) result.concluido = concluido;
    return result;
  }

  SetOnboardingProgressResponse._();

  factory SetOnboardingProgressResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetOnboardingProgressResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetOnboardingProgressResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'passo')
    ..aOB(2, _omitFieldNames ? '' : 'concluido')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOnboardingProgressResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetOnboardingProgressResponse copyWith(
          void Function(SetOnboardingProgressResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SetOnboardingProgressResponse))
          as SetOnboardingProgressResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetOnboardingProgressResponse create() =>
      SetOnboardingProgressResponse._();
  @$core.override
  SetOnboardingProgressResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetOnboardingProgressResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetOnboardingProgressResponse>(create);
  static SetOnboardingProgressResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get passo => $_getIZ(0);
  @$pb.TagNumber(1)
  set passo($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasso() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasso() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get concluido => $_getBF(1);
  @$pb.TagNumber(2)
  set concluido($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConcluido() => $_has(1);
  @$pb.TagNumber(2)
  void clearConcluido() => $_clearField(2);
}

/// N3.3: config do PRÓPRIO tenant (tenant_id vem das claims, não do request).
/// Reaproveita GetTenantConfigResponse/UpdateTenantConfigResponse. As api_keys já
/// vêm mascaradas do data_postgres (`••••••••`), igual ao caminho do superusuário.
class GetMyTenantConfigRequest extends $pb.GeneratedMessage {
  factory GetMyTenantConfigRequest() => create();

  GetMyTenantConfigRequest._();

  factory GetMyTenantConfigRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyTenantConfigRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyTenantConfigRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyTenantConfigRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyTenantConfigRequest copyWith(
          void Function(GetMyTenantConfigRequest) updates) =>
      super.copyWith((message) => updates(message as GetMyTenantConfigRequest))
          as GetMyTenantConfigRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyTenantConfigRequest create() => GetMyTenantConfigRequest._();
  @$core.override
  GetMyTenantConfigRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyTenantConfigRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyTenantConfigRequest>(create);
  static GetMyTenantConfigRequest? _defaultInstance;
}

class UpdateMyTenantConfigRequest extends $pb.GeneratedMessage {
  factory UpdateMyTenantConfigRequest({
    $core.String? dadosEmpresa,
    $core.String? personaBot,
    $core.String? botAgentName,
    $core.String? msgFallback,
    $core.String? msgSemInfo,
    $core.String? msgTransferencia,
    $core.String? llmClass,
    $core.String? model,
    $core.String? llmTemperature,
    $core.String? transcriptionProvider,
    $core.String? transcriptionModel,
    $core.String? visionProvider,
    $core.String? visionModel,
    $core.String? embeddingsClass,
    $core.String? embeddingsModel,
    $core.int? chunkSize,
    $core.int? chunkOverlap,
    $core.String? similarityThreshold,
    $core.String? vectorDistanceThreshold,
    $core.Iterable<ApiKeyEntry>? apiKeys,
  }) {
    final result = create();
    if (dadosEmpresa != null) result.dadosEmpresa = dadosEmpresa;
    if (personaBot != null) result.personaBot = personaBot;
    if (botAgentName != null) result.botAgentName = botAgentName;
    if (msgFallback != null) result.msgFallback = msgFallback;
    if (msgSemInfo != null) result.msgSemInfo = msgSemInfo;
    if (msgTransferencia != null) result.msgTransferencia = msgTransferencia;
    if (llmClass != null) result.llmClass = llmClass;
    if (model != null) result.model = model;
    if (llmTemperature != null) result.llmTemperature = llmTemperature;
    if (transcriptionProvider != null)
      result.transcriptionProvider = transcriptionProvider;
    if (transcriptionModel != null)
      result.transcriptionModel = transcriptionModel;
    if (visionProvider != null) result.visionProvider = visionProvider;
    if (visionModel != null) result.visionModel = visionModel;
    if (embeddingsClass != null) result.embeddingsClass = embeddingsClass;
    if (embeddingsModel != null) result.embeddingsModel = embeddingsModel;
    if (chunkSize != null) result.chunkSize = chunkSize;
    if (chunkOverlap != null) result.chunkOverlap = chunkOverlap;
    if (similarityThreshold != null)
      result.similarityThreshold = similarityThreshold;
    if (vectorDistanceThreshold != null)
      result.vectorDistanceThreshold = vectorDistanceThreshold;
    if (apiKeys != null) result.apiKeys.addAll(apiKeys);
    return result;
  }

  UpdateMyTenantConfigRequest._();

  factory UpdateMyTenantConfigRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyTenantConfigRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyTenantConfigRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'dadosEmpresa')
    ..aOS(2, _omitFieldNames ? '' : 'personaBot')
    ..aOS(3, _omitFieldNames ? '' : 'botAgentName')
    ..aOS(4, _omitFieldNames ? '' : 'msgFallback')
    ..aOS(5, _omitFieldNames ? '' : 'msgSemInfo')
    ..aOS(6, _omitFieldNames ? '' : 'msgTransferencia')
    ..aOS(7, _omitFieldNames ? '' : 'llmClass')
    ..aOS(8, _omitFieldNames ? '' : 'model')
    ..aOS(9, _omitFieldNames ? '' : 'llmTemperature')
    ..aOS(10, _omitFieldNames ? '' : 'transcriptionProvider')
    ..aOS(11, _omitFieldNames ? '' : 'transcriptionModel')
    ..aOS(12, _omitFieldNames ? '' : 'visionProvider')
    ..aOS(13, _omitFieldNames ? '' : 'visionModel')
    ..aOS(14, _omitFieldNames ? '' : 'embeddingsClass')
    ..aOS(15, _omitFieldNames ? '' : 'embeddingsModel')
    ..aI(16, _omitFieldNames ? '' : 'chunkSize')
    ..aI(17, _omitFieldNames ? '' : 'chunkOverlap')
    ..aOS(18, _omitFieldNames ? '' : 'similarityThreshold')
    ..aOS(19, _omitFieldNames ? '' : 'vectorDistanceThreshold')
    ..pPM<ApiKeyEntry>(20, _omitFieldNames ? '' : 'apiKeys',
        subBuilder: ApiKeyEntry.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyTenantConfigRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyTenantConfigRequest copyWith(
          void Function(UpdateMyTenantConfigRequest) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateMyTenantConfigRequest))
          as UpdateMyTenantConfigRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyTenantConfigRequest create() =>
      UpdateMyTenantConfigRequest._();
  @$core.override
  UpdateMyTenantConfigRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyTenantConfigRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyTenantConfigRequest>(create);
  static UpdateMyTenantConfigRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get dadosEmpresa => $_getSZ(0);
  @$pb.TagNumber(1)
  set dadosEmpresa($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDadosEmpresa() => $_has(0);
  @$pb.TagNumber(1)
  void clearDadosEmpresa() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get personaBot => $_getSZ(1);
  @$pb.TagNumber(2)
  set personaBot($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPersonaBot() => $_has(1);
  @$pb.TagNumber(2)
  void clearPersonaBot() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get botAgentName => $_getSZ(2);
  @$pb.TagNumber(3)
  set botAgentName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBotAgentName() => $_has(2);
  @$pb.TagNumber(3)
  void clearBotAgentName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get msgFallback => $_getSZ(3);
  @$pb.TagNumber(4)
  set msgFallback($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMsgFallback() => $_has(3);
  @$pb.TagNumber(4)
  void clearMsgFallback() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get msgSemInfo => $_getSZ(4);
  @$pb.TagNumber(5)
  set msgSemInfo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMsgSemInfo() => $_has(4);
  @$pb.TagNumber(5)
  void clearMsgSemInfo() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get msgTransferencia => $_getSZ(5);
  @$pb.TagNumber(6)
  set msgTransferencia($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMsgTransferencia() => $_has(5);
  @$pb.TagNumber(6)
  void clearMsgTransferencia() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get llmClass => $_getSZ(6);
  @$pb.TagNumber(7)
  set llmClass($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLlmClass() => $_has(6);
  @$pb.TagNumber(7)
  void clearLlmClass() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get model => $_getSZ(7);
  @$pb.TagNumber(8)
  set model($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasModel() => $_has(7);
  @$pb.TagNumber(8)
  void clearModel() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get llmTemperature => $_getSZ(8);
  @$pb.TagNumber(9)
  set llmTemperature($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLlmTemperature() => $_has(8);
  @$pb.TagNumber(9)
  void clearLlmTemperature() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get transcriptionProvider => $_getSZ(9);
  @$pb.TagNumber(10)
  set transcriptionProvider($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasTranscriptionProvider() => $_has(9);
  @$pb.TagNumber(10)
  void clearTranscriptionProvider() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get transcriptionModel => $_getSZ(10);
  @$pb.TagNumber(11)
  set transcriptionModel($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTranscriptionModel() => $_has(10);
  @$pb.TagNumber(11)
  void clearTranscriptionModel() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get visionProvider => $_getSZ(11);
  @$pb.TagNumber(12)
  set visionProvider($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasVisionProvider() => $_has(11);
  @$pb.TagNumber(12)
  void clearVisionProvider() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get visionModel => $_getSZ(12);
  @$pb.TagNumber(13)
  set visionModel($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasVisionModel() => $_has(12);
  @$pb.TagNumber(13)
  void clearVisionModel() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get embeddingsClass => $_getSZ(13);
  @$pb.TagNumber(14)
  set embeddingsClass($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasEmbeddingsClass() => $_has(13);
  @$pb.TagNumber(14)
  void clearEmbeddingsClass() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get embeddingsModel => $_getSZ(14);
  @$pb.TagNumber(15)
  set embeddingsModel($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasEmbeddingsModel() => $_has(14);
  @$pb.TagNumber(15)
  void clearEmbeddingsModel() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get chunkSize => $_getIZ(15);
  @$pb.TagNumber(16)
  set chunkSize($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasChunkSize() => $_has(15);
  @$pb.TagNumber(16)
  void clearChunkSize() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get chunkOverlap => $_getIZ(16);
  @$pb.TagNumber(17)
  set chunkOverlap($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasChunkOverlap() => $_has(16);
  @$pb.TagNumber(17)
  void clearChunkOverlap() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get similarityThreshold => $_getSZ(17);
  @$pb.TagNumber(18)
  set similarityThreshold($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasSimilarityThreshold() => $_has(17);
  @$pb.TagNumber(18)
  void clearSimilarityThreshold() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get vectorDistanceThreshold => $_getSZ(18);
  @$pb.TagNumber(19)
  set vectorDistanceThreshold($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasVectorDistanceThreshold() => $_has(18);
  @$pb.TagNumber(19)
  void clearVectorDistanceThreshold() => $_clearField(19);

  @$pb.TagNumber(20)
  $pb.PbList<ApiKeyEntry> get apiKeys => $_getList(19);
}

class StreamAtendimentosRequest extends $pb.GeneratedMessage {
  factory StreamAtendimentosRequest() => create();

  StreamAtendimentosRequest._();

  factory StreamAtendimentosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamAtendimentosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamAtendimentosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamAtendimentosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamAtendimentosRequest copyWith(
          void Function(StreamAtendimentosRequest) updates) =>
      super.copyWith((message) => updates(message as StreamAtendimentosRequest))
          as StreamAtendimentosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamAtendimentosRequest create() => StreamAtendimentosRequest._();
  @$core.override
  StreamAtendimentosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamAtendimentosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamAtendimentosRequest>(create);
  static StreamAtendimentosRequest? _defaultInstance;
}

class AtendimentoEvent extends $pb.GeneratedMessage {
  factory AtendimentoEvent({
    $core.String? eventType,
    $core.String? tenantId,
    $core.String? payload,
  }) {
    final result = create();
    if (eventType != null) result.eventType = eventType;
    if (tenantId != null) result.tenantId = tenantId;
    if (payload != null) result.payload = payload;
    return result;
  }

  AtendimentoEvent._();

  factory AtendimentoEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtendimentoEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtendimentoEvent',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'eventType')
    ..aOS(2, _omitFieldNames ? '' : 'tenantId')
    ..aOS(3, _omitFieldNames ? '' : 'payload')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoEvent copyWith(void Function(AtendimentoEvent) updates) =>
      super.copyWith((message) => updates(message as AtendimentoEvent))
          as AtendimentoEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtendimentoEvent create() => AtendimentoEvent._();
  @$core.override
  AtendimentoEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtendimentoEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtendimentoEvent>(create);
  static AtendimentoEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get eventType => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventType($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEventType() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tenantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tenantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTenantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTenantId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get payload => $_getSZ(2);
  @$pb.TagNumber(3)
  set payload($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearPayload() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
