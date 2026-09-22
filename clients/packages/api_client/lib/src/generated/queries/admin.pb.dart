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
    $core.String? confiancaMinimaTransferencia,
    $core.String? confiancaMinimaAutomatica,
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
    if (confiancaMinimaTransferencia != null)
      result.confiancaMinimaTransferencia = confiancaMinimaTransferencia;
    if (confiancaMinimaAutomatica != null)
      result.confiancaMinimaAutomatica = confiancaMinimaAutomatica;
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
    ..aOS(21, _omitFieldNames ? '' : 'confiancaMinimaTransferencia')
    ..aOS(22, _omitFieldNames ? '' : 'confiancaMinimaAutomatica')
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

  /// B4 — limiares de confiança da IA, como string decimal ("0.80").
  /// Vazio = não mexer. "0" em confianca_minima_transferencia desliga o veto.
  @$pb.TagNumber(21)
  $core.String get confiancaMinimaTransferencia => $_getSZ(20);
  @$pb.TagNumber(21)
  set confiancaMinimaTransferencia($core.String value) =>
      $_setString(20, value);
  @$pb.TagNumber(21)
  $core.bool hasConfiancaMinimaTransferencia() => $_has(20);
  @$pb.TagNumber(21)
  void clearConfiancaMinimaTransferencia() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.String get confiancaMinimaAutomatica => $_getSZ(21);
  @$pb.TagNumber(22)
  set confiancaMinimaAutomatica($core.String value) => $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasConfiancaMinimaAutomatica() => $_has(21);
  @$pb.TagNumber(22)
  void clearConfiancaMinimaAutomatica() => $_clearField(22);
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
    $core.String? confiancaMinimaTransferencia,
    $core.String? confiancaMinimaAutomatica,
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
    if (confiancaMinimaTransferencia != null)
      result.confiancaMinimaTransferencia = confiancaMinimaTransferencia;
    if (confiancaMinimaAutomatica != null)
      result.confiancaMinimaAutomatica = confiancaMinimaAutomatica;
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
    ..aOS(22, _omitFieldNames ? '' : 'confiancaMinimaTransferencia')
    ..aOS(23, _omitFieldNames ? '' : 'confiancaMinimaAutomatica')
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

  /// B4 — limiares de confiança da IA, como string decimal ("0.80").
  /// Vazio = não mexer. "0" em confianca_minima_transferencia desliga o veto.
  @$pb.TagNumber(22)
  $core.String get confiancaMinimaTransferencia => $_getSZ(21);
  @$pb.TagNumber(22)
  set confiancaMinimaTransferencia($core.String value) =>
      $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasConfiancaMinimaTransferencia() => $_has(21);
  @$pb.TagNumber(22)
  void clearConfiancaMinimaTransferencia() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.String get confiancaMinimaAutomatica => $_getSZ(22);
  @$pb.TagNumber(23)
  set confiancaMinimaAutomatica($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasConfiancaMinimaAutomatica() => $_has(22);
  @$pb.TagNumber(23)
  void clearConfiancaMinimaAutomatica() => $_clearField(23);
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
    $core.int? naoLidas,
    $core.String? contatoNome,
    $core.String? contatoTelefone,
    $core.String? contatoFotoUrl,
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
    if (naoLidas != null) result.naoLidas = naoLidas;
    if (contatoNome != null) result.contatoNome = contatoNome;
    if (contatoTelefone != null) result.contatoTelefone = contatoTelefone;
    if (contatoFotoUrl != null) result.contatoFotoUrl = contatoFotoUrl;
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
    ..aI(14, _omitFieldNames ? '' : 'naoLidas')
    ..aOS(15, _omitFieldNames ? '' : 'contatoNome')
    ..aOS(16, _omitFieldNames ? '' : 'contatoTelefone')
    ..aOS(17, _omitFieldNames ? '' : 'contatoFotoUrl')
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

  @$pb.TagNumber(14)
  $core.int get naoLidas => $_getIZ(13);
  @$pb.TagNumber(14)
  set naoLidas($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasNaoLidas() => $_has(13);
  @$pb.TagNumber(14)
  void clearNaoLidas() => $_clearField(14);

  /// P13 — o contato do cartão. O quadro mostrava `Contato #id`: o resumo nunca
  /// levou nome nem telefone. `contato_nome` cai para o nome de perfil do
  /// WhatsApp e fica vazio quando nem isso existe (a tela mostra o telefone).
  @$pb.TagNumber(15)
  $core.String get contatoNome => $_getSZ(14);
  @$pb.TagNumber(15)
  set contatoNome($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasContatoNome() => $_has(14);
  @$pb.TagNumber(15)
  void clearContatoNome() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get contatoTelefone => $_getSZ(15);
  @$pb.TagNumber(16)
  set contatoTelefone($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasContatoTelefone() => $_has(15);
  @$pb.TagNumber(16)
  void clearContatoTelefone() => $_clearField(16);

  /// URL do CDN do WhatsApp, assinada e com validade: a tela trata imagem
  /// quebrada como "sem foto" e pede uma nova com `ObterContatoDoAtendimento`.
  @$pb.TagNumber(17)
  $core.String get contatoFotoUrl => $_getSZ(16);
  @$pb.TagNumber(17)
  set contatoFotoUrl($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasContatoFotoUrl() => $_has(16);
  @$pb.TagNumber(17)
  void clearContatoFotoUrl() => $_clearField(17);
}

/// P13 — nome, telefone e foto do contato de uma conversa, para o cabeçalho.
class ObterContatoDoAtendimentoRequest extends $pb.GeneratedMessage {
  factory ObterContatoDoAtendimentoRequest({
    $core.int? atendimentoId,
    $core.bool? forcar,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (forcar != null) result.forcar = forcar;
    return result;
  }

  ObterContatoDoAtendimentoRequest._();

  factory ObterContatoDoAtendimentoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ObterContatoDoAtendimentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObterContatoDoAtendimentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOB(2, _omitFieldNames ? '' : 'forcar')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObterContatoDoAtendimentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObterContatoDoAtendimentoRequest copyWith(
          void Function(ObterContatoDoAtendimentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ObterContatoDoAtendimentoRequest))
          as ObterContatoDoAtendimentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ObterContatoDoAtendimentoRequest create() =>
      ObterContatoDoAtendimentoRequest._();
  @$core.override
  ObterContatoDoAtendimentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ObterContatoDoAtendimentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObterContatoDoAtendimentoRequest>(
          create);
  static ObterContatoDoAtendimentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  /// Ignora o prazo de 7 dias entre consultas ao provedor. A tela usa quando a
  /// foto guardada não abre (a URL do CDN expirou).
  @$pb.TagNumber(2)
  $core.bool get forcar => $_getBF(1);
  @$pb.TagNumber(2)
  set forcar($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasForcar() => $_has(1);
  @$pb.TagNumber(2)
  void clearForcar() => $_clearField(2);
}

class ObterContatoDoAtendimentoResponse extends $pb.GeneratedMessage {
  factory ObterContatoDoAtendimentoResponse({
    $core.int? contatoId,
    $core.String? nome,
    $core.String? telefone,
    $core.String? fotoUrl,
  }) {
    final result = create();
    if (contatoId != null) result.contatoId = contatoId;
    if (nome != null) result.nome = nome;
    if (telefone != null) result.telefone = telefone;
    if (fotoUrl != null) result.fotoUrl = fotoUrl;
    return result;
  }

  ObterContatoDoAtendimentoResponse._();

  factory ObterContatoDoAtendimentoResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ObterContatoDoAtendimentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObterContatoDoAtendimentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'contatoId')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'telefone')
    ..aOS(4, _omitFieldNames ? '' : 'fotoUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObterContatoDoAtendimentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObterContatoDoAtendimentoResponse copyWith(
          void Function(ObterContatoDoAtendimentoResponse) updates) =>
      super.copyWith((message) =>
              updates(message as ObterContatoDoAtendimentoResponse))
          as ObterContatoDoAtendimentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ObterContatoDoAtendimentoResponse create() =>
      ObterContatoDoAtendimentoResponse._();
  @$core.override
  ObterContatoDoAtendimentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ObterContatoDoAtendimentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObterContatoDoAtendimentoResponse>(
          create);
  static ObterContatoDoAtendimentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get contatoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set contatoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContatoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearContatoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nome => $_getSZ(1);
  @$pb.TagNumber(2)
  set nome($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNome() => $_has(1);
  @$pb.TagNumber(2)
  void clearNome() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get telefone => $_getSZ(2);
  @$pb.TagNumber(3)
  set telefone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTelefone() => $_has(2);
  @$pb.TagNumber(3)
  void clearTelefone() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get fotoUrl => $_getSZ(3);
  @$pb.TagNumber(4)
  set fotoUrl($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFotoUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearFotoUrl() => $_clearField(4);
}

class ListAtendimentosRequest extends $pb.GeneratedMessage {
  factory ListAtendimentosRequest({
    $core.String? status,
    $core.int? departamentoId,
    $core.int? limit,
    $core.String? busca,
    $core.int? atendenteId,
    $core.bool? somenteNaoLidos,
    $core.String? prioridade,
    $fixnum.Int64? etiquetaId,
    $core.bool? somenteMeus,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (limit != null) result.limit = limit;
    if (busca != null) result.busca = busca;
    if (atendenteId != null) result.atendenteId = atendenteId;
    if (somenteNaoLidos != null) result.somenteNaoLidos = somenteNaoLidos;
    if (prioridade != null) result.prioridade = prioridade;
    if (etiquetaId != null) result.etiquetaId = etiquetaId;
    if (somenteMeus != null) result.somenteMeus = somenteMeus;
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
    ..aOS(4, _omitFieldNames ? '' : 'busca')
    ..aI(5, _omitFieldNames ? '' : 'atendenteId')
    ..aOB(6, _omitFieldNames ? '' : 'somenteNaoLidos')
    ..aOS(7, _omitFieldNames ? '' : 'prioridade')
    ..aInt64(8, _omitFieldNames ? '' : 'etiquetaId')
    ..aOB(9, _omitFieldNames ? '' : 'somenteMeus')
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

  /// Vazio = o quadro inteiro (tudo que nao foi arquivado).
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

  /// P1 (paridade v1 `list_conversations`): o mesmo recorte que a v1 fazia.
  /// Casa nome do contato, nome do perfil do WhatsApp, telefone e assunto.
  @$pb.TagNumber(4)
  $core.String get busca => $_getSZ(3);
  @$pb.TagNumber(4)
  set busca($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBusca() => $_has(3);
  @$pb.TagNumber(4)
  void clearBusca() => $_clearField(4);

  /// 0 = todos. Use -1 para "sem dono" (a fila que ninguem assumiu).
  @$pb.TagNumber(5)
  $core.int get atendenteId => $_getIZ(4);
  @$pb.TagNumber(5)
  set atendenteId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAtendenteId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAtendenteId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get somenteNaoLidos => $_getBF(5);
  @$pb.TagNumber(6)
  set somenteNaoLidos($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSomenteNaoLidos() => $_has(5);
  @$pb.TagNumber(6)
  void clearSomenteNaoLidos() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get prioridade => $_getSZ(6);
  @$pb.TagNumber(7)
  set prioridade($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPrioridade() => $_has(6);
  @$pb.TagNumber(7)
  void clearPrioridade() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get etiquetaId => $_getI64(7);
  @$pb.TagNumber(8)
  set etiquetaId($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasEtiquetaId() => $_has(7);
  @$pb.TagNumber(8)
  void clearEtiquetaId() => $_clearField(8);

  /// "minhas conversas": o servidor resolve o atendente pelo usuario logado,
  /// como a v1 fazia — o cliente nao conhece o id do atendente.
  @$pb.TagNumber(9)
  $core.bool get somenteMeus => $_getBF(8);
  @$pb.TagNumber(9)
  set somenteMeus($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSomenteMeus() => $_has(8);
  @$pb.TagNumber(9)
  void clearSomenteMeus() => $_clearField(9);
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

/// Mídia anexada a uma mensagem da thread (N9/E2).
///
/// A `url_assinada` é gerada NO MOMENTO da leitura da thread, com TTL curto. Não
/// é URL permanente nem proxy pelo backend: presign curto é o que o R2 faz bem, e
/// virar CDN não é papel do servidor.
class MidiaMensagem extends $pb.GeneratedMessage {
  factory MidiaMensagem({
    $core.String? kind,
    $core.String? urlAssinada,
    $core.String? mimetype,
    $core.String? filename,
    $fixnum.Int64? sizeBytes,
    $core.int? seconds,
    $core.bool? isPtt,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (urlAssinada != null) result.urlAssinada = urlAssinada;
    if (mimetype != null) result.mimetype = mimetype;
    if (filename != null) result.filename = filename;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (seconds != null) result.seconds = seconds;
    if (isPtt != null) result.isPtt = isPtt;
    return result;
  }

  MidiaMensagem._();

  factory MidiaMensagem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MidiaMensagem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MidiaMensagem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'kind')
    ..aOS(2, _omitFieldNames ? '' : 'urlAssinada')
    ..aOS(3, _omitFieldNames ? '' : 'mimetype')
    ..aOS(4, _omitFieldNames ? '' : 'filename')
    ..aInt64(5, _omitFieldNames ? '' : 'sizeBytes')
    ..aI(6, _omitFieldNames ? '' : 'seconds')
    ..aOB(7, _omitFieldNames ? '' : 'isPtt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MidiaMensagem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MidiaMensagem copyWith(void Function(MidiaMensagem) updates) =>
      super.copyWith((message) => updates(message as MidiaMensagem))
          as MidiaMensagem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MidiaMensagem create() => MidiaMensagem._();
  @$core.override
  MidiaMensagem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MidiaMensagem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MidiaMensagem>(create);
  static MidiaMensagem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get kind => $_getSZ(0);
  @$pb.TagNumber(1)
  set kind($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get urlAssinada => $_getSZ(1);
  @$pb.TagNumber(2)
  set urlAssinada($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrlAssinada() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrlAssinada() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mimetype => $_getSZ(2);
  @$pb.TagNumber(3)
  set mimetype($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMimetype() => $_has(2);
  @$pb.TagNumber(3)
  void clearMimetype() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get filename => $_getSZ(3);
  @$pb.TagNumber(4)
  set filename($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFilename() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilename() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sizeBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSizeBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearSizeBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get seconds => $_getIZ(5);
  @$pb.TagNumber(6)
  set seconds($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSeconds() => $_has(5);
  @$pb.TagNumber(6)
  void clearSeconds() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isPtt => $_getBF(6);
  @$pb.TagNumber(7)
  set isPtt($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsPtt() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsPtt() => $_clearField(7);
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
    MidiaMensagem? midia,
    $fixnum.Int64? dataEntregue,
    $fixnum.Int64? dataLida,
    $core.int? mensagemCitadaId,
    $core.String? citadaRemetente,
    $core.String? citadaPreview,
    $core.Iterable<ReacaoDaMensagem>? reacoes,
    $core.String? metadadosJson,
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
    if (midia != null) result.midia = midia;
    if (dataEntregue != null) result.dataEntregue = dataEntregue;
    if (dataLida != null) result.dataLida = dataLida;
    if (mensagemCitadaId != null) result.mensagemCitadaId = mensagemCitadaId;
    if (citadaRemetente != null) result.citadaRemetente = citadaRemetente;
    if (citadaPreview != null) result.citadaPreview = citadaPreview;
    if (reacoes != null) result.reacoes.addAll(reacoes);
    if (metadadosJson != null) result.metadadosJson = metadadosJson;
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
    ..aOM<MidiaMensagem>(10, _omitFieldNames ? '' : 'midia',
        subBuilder: MidiaMensagem.create)
    ..aInt64(11, _omitFieldNames ? '' : 'dataEntregue')
    ..aInt64(12, _omitFieldNames ? '' : 'dataLida')
    ..aI(13, _omitFieldNames ? '' : 'mensagemCitadaId')
    ..aOS(14, _omitFieldNames ? '' : 'citadaRemetente')
    ..aOS(15, _omitFieldNames ? '' : 'citadaPreview')
    ..pPM<ReacaoDaMensagem>(16, _omitFieldNames ? '' : 'reacoes',
        subBuilder: ReacaoDaMensagem.create)
    ..aOS(17, _omitFieldNames ? '' : 'metadadosJson')
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

  /// N9/E2: presente só quando a mensagem tem mídia.
  @$pb.TagNumber(10)
  MidiaMensagem get midia => $_getN(9);
  @$pb.TagNumber(10)
  set midia(MidiaMensagem value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasMidia() => $_has(9);
  @$pb.TagNumber(10)
  void clearMidia() => $_clearField(10);
  @$pb.TagNumber(10)
  MidiaMensagem ensureMidia() => $_ensure(9);

  /// N9/E7: ticks de entrega e leitura. As colunas existem desde a 0006 e nunca
  /// foram expostas — sem elas a bolha não distingue "enviado" de "lido".
  @$pb.TagNumber(11)
  $fixnum.Int64 get dataEntregue => $_getI64(10);
  @$pb.TagNumber(11)
  set dataEntregue($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDataEntregue() => $_has(10);
  @$pb.TagNumber(11)
  void clearDataEntregue() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get dataLida => $_getI64(11);
  @$pb.TagNumber(12)
  set dataLida($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDataLida() => $_has(11);
  @$pb.TagNumber(12)
  void clearDataLida() => $_clearField(12);

  /// N9/E6: citação (responder mensagem). Colunas existentes desde a 0006.
  @$pb.TagNumber(13)
  $core.int get mensagemCitadaId => $_getIZ(12);
  @$pb.TagNumber(13)
  set mensagemCitadaId($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasMensagemCitadaId() => $_has(12);
  @$pb.TagNumber(13)
  void clearMensagemCitadaId() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get citadaRemetente => $_getSZ(13);
  @$pb.TagNumber(14)
  set citadaRemetente($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasCitadaRemetente() => $_has(13);
  @$pb.TagNumber(14)
  void clearCitadaRemetente() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get citadaPreview => $_getSZ(14);
  @$pb.TagNumber(15)
  set citadaPreview($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasCitadaPreview() => $_has(14);
  @$pb.TagNumber(15)
  void clearCitadaPreview() => $_clearField(15);

  /// P8 — reação (emoji) a esta mensagem. Não é bolha nova: é atributo da
  /// mensagem reagida, como no WhatsApp Web. Vazio na imensa maioria delas.
  @$pb.TagNumber(16)
  $pb.PbList<ReacaoDaMensagem> get reacoes => $_getList(15);

  /// P8 — o que não cabe em `conteudo`: alternativas da enquete, itens da lista,
  /// rótulos dos botões, vCard do contato. JSON cru porque o formato varia com o
  /// tipo, e um campo por tipo engessaria o contrato no que o WhatsApp oferece
  /// hoje.
  @$pb.TagNumber(17)
  $core.String get metadadosJson => $_getSZ(16);
  @$pb.TagNumber(17)
  set metadadosJson($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasMetadadosJson() => $_has(16);
  @$pb.TagNumber(17)
  void clearMetadadosJson() => $_clearField(17);
}

/// P8 — quem reagiu e com quê.
class ReacaoDaMensagem extends $pb.GeneratedMessage {
  factory ReacaoDaMensagem({
    $core.String? emoji,
    $core.String? de,
  }) {
    final result = create();
    if (emoji != null) result.emoji = emoji;
    if (de != null) result.de = de;
    return result;
  }

  ReacaoDaMensagem._();

  factory ReacaoDaMensagem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReacaoDaMensagem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReacaoDaMensagem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'emoji')
    ..aOS(2, _omitFieldNames ? '' : 'de')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReacaoDaMensagem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReacaoDaMensagem copyWith(void Function(ReacaoDaMensagem) updates) =>
      super.copyWith((message) => updates(message as ReacaoDaMensagem))
          as ReacaoDaMensagem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReacaoDaMensagem create() => ReacaoDaMensagem._();
  @$core.override
  ReacaoDaMensagem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReacaoDaMensagem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReacaoDaMensagem>(create);
  static ReacaoDaMensagem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get emoji => $_getSZ(0);
  @$pb.TagNumber(1)
  set emoji($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmoji() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmoji() => $_clearField(1);

  /// Vocabulário do `remetente` da mensagem: "contato" ou "atendente". É o que
  /// diz de que lado da bolha desenhar.
  @$pb.TagNumber(2)
  $core.String get de => $_getSZ(1);
  @$pb.TagNumber(2)
  set de($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDe() => $_has(1);
  @$pb.TagNumber(2)
  void clearDe() => $_clearField(2);
}

class GetThreadRequest extends $pb.GeneratedMessage {
  factory GetThreadRequest({
    $core.int? atendimentoId,
    $core.int? limit,
    $core.int? offset,
    $core.int? beforeId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (limit != null) result.limit = limit;
    if (offset != null) result.offset = offset;
    if (beforeId != null) result.beforeId = beforeId;
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
    ..aI(4, _omitFieldNames ? '' : 'beforeId')
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

  /// P2 — rolar para cima carrega o que veio ANTES desta mensagem, como o
  /// `get_messages(before_id=...)` da v1. Paginar por offset numa conversa que
  /// recebe mensagem enquanto se rola repete ou pula bolha; o cursor nao.
  /// Quando presente, `offset` e ignorado.
  @$pb.TagNumber(4)
  $core.int get beforeId => $_getIZ(3);
  @$pb.TagNumber(4)
  set beforeId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBeforeId() => $_has(3);
  @$pb.TagNumber(4)
  void clearBeforeId() => $_clearField(4);
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

/// C3 — iniciar um atendimento a partir de um cliente ja cadastrado.
///
/// Ate aqui um atendimento so nascia de uma mensagem que chegou: para procurar
/// o cliente era preciso abrir o WhatsApp por fora, e o historico da conversa
/// comecava pela metade.
class IniciarAtendimentoManualRequest extends $pb.GeneratedMessage {
  factory IniciarAtendimentoManualRequest({
    $core.int? contatoId,
    $core.int? fluxoId,
    $core.int? etapaInicialId,
    $core.int? departamentoId,
    $core.String? assunto,
  }) {
    final result = create();
    if (contatoId != null) result.contatoId = contatoId;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (etapaInicialId != null) result.etapaInicialId = etapaInicialId;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (assunto != null) result.assunto = assunto;
    return result;
  }

  IniciarAtendimentoManualRequest._();

  factory IniciarAtendimentoManualRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory IniciarAtendimentoManualRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'IniciarAtendimentoManualRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'contatoId')
    ..aI(2, _omitFieldNames ? '' : 'fluxoId')
    ..aI(3, _omitFieldNames ? '' : 'etapaInicialId')
    ..aI(4, _omitFieldNames ? '' : 'departamentoId')
    ..aOS(5, _omitFieldNames ? '' : 'assunto')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IniciarAtendimentoManualRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IniciarAtendimentoManualRequest copyWith(
          void Function(IniciarAtendimentoManualRequest) updates) =>
      super.copyWith(
              (message) => updates(message as IniciarAtendimentoManualRequest))
          as IniciarAtendimentoManualRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IniciarAtendimentoManualRequest create() =>
      IniciarAtendimentoManualRequest._();
  @$core.override
  IniciarAtendimentoManualRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static IniciarAtendimentoManualRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<IniciarAtendimentoManualRequest>(
          create);
  static IniciarAtendimentoManualRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get contatoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set contatoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContatoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearContatoId() => $_clearField(1);

  /// Fluxo e etapa sao OBRIGATORIOS, ao contrario da ingestao (que cria sem
  /// etapa e preenche depois). Um atendimento sem etapa nao aparece em coluna
  /// nenhuma do quadro — nasceria invisivel.
  @$pb.TagNumber(2)
  $core.int get fluxoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set fluxoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFluxoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFluxoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get etapaInicialId => $_getIZ(2);
  @$pb.TagNumber(3)
  set etapaInicialId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEtapaInicialId() => $_has(2);
  @$pb.TagNumber(3)
  void clearEtapaInicialId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get departamentoId => $_getIZ(3);
  @$pb.TagNumber(4)
  set departamentoId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDepartamentoId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDepartamentoId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get assunto => $_getSZ(4);
  @$pb.TagNumber(5)
  set assunto($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAssunto() => $_has(4);
  @$pb.TagNumber(5)
  void clearAssunto() => $_clearField(5);
}

class IniciarAtendimentoManualResponse extends $pb.GeneratedMessage {
  factory IniciarAtendimentoManualResponse({
    $core.int? atendimentoId,
    $core.bool? jaExistia,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (jaExistia != null) result.jaExistia = jaExistia;
    return result;
  }

  IniciarAtendimentoManualResponse._();

  factory IniciarAtendimentoManualResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory IniciarAtendimentoManualResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'IniciarAtendimentoManualResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOB(2, _omitFieldNames ? '' : 'jaExistia')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IniciarAtendimentoManualResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IniciarAtendimentoManualResponse copyWith(
          void Function(IniciarAtendimentoManualResponse) updates) =>
      super.copyWith(
              (message) => updates(message as IniciarAtendimentoManualResponse))
          as IniciarAtendimentoManualResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IniciarAtendimentoManualResponse create() =>
      IniciarAtendimentoManualResponse._();
  @$core.override
  IniciarAtendimentoManualResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static IniciarAtendimentoManualResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<IniciarAtendimentoManualResponse>(
          create);
  static IniciarAtendimentoManualResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  /// TRUE quando ja havia conversa aberta com esse contato: vale a invariante
  /// de um atendimento ativo por contato, e a tela ABRE a existente em vez de
  /// criar um segundo cartao para o mesmo cliente.
  @$pb.TagNumber(2)
  $core.bool get jaExistia => $_getBF(1);
  @$pb.TagNumber(2)
  set jaExistia($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasJaExistia() => $_has(1);
  @$pb.TagNumber(2)
  void clearJaExistia() => $_clearField(2);
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

/// O par simetrico de MoveAtendimentoEtapa: la a coluna manda no status, aqui o
/// status manda na coluna. Encerrar pelo chat sem isto deixaria o cartao parado
/// na coluna de trabalho, e o quadro passaria a mentir sobre o que esta aberto.
class SetAtendimentoStatusRequest extends $pb.GeneratedMessage {
  factory SetAtendimentoStatusRequest({
    $core.int? atendimentoId,
    $core.String? status,
    $core.String? motivo,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (status != null) result.status = status;
    if (motivo != null) result.motivo = motivo;
    return result;
  }

  SetAtendimentoStatusRequest._();

  factory SetAtendimentoStatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetAtendimentoStatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetAtendimentoStatusRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..aOS(3, _omitFieldNames ? '' : 'motivo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetAtendimentoStatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetAtendimentoStatusRequest copyWith(
          void Function(SetAtendimentoStatusRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SetAtendimentoStatusRequest))
          as SetAtendimentoStatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetAtendimentoStatusRequest create() =>
      SetAtendimentoStatusRequest._();
  @$core.override
  SetAtendimentoStatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetAtendimentoStatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetAtendimentoStatusRequest>(create);
  static SetAtendimentoStatusRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  /// Vocabulario fechado: fila, em_atendimento, pendencia, resolvido,
  /// cancelado, arquivado.
  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get motivo => $_getSZ(2);
  @$pb.TagNumber(3)
  set motivo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMotivo() => $_has(2);
  @$pb.TagNumber(3)
  void clearMotivo() => $_clearField(3);
}

class SetAtendimentoStatusResponse extends $pb.GeneratedMessage {
  factory SetAtendimentoStatusResponse({
    $core.bool? success,
    $core.String? status,
    $core.int? etapaAtualId,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (status != null) result.status = status;
    if (etapaAtualId != null) result.etapaAtualId = etapaAtualId;
    return result;
  }

  SetAtendimentoStatusResponse._();

  factory SetAtendimentoStatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetAtendimentoStatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetAtendimentoStatusResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..aI(3, _omitFieldNames ? '' : 'etapaAtualId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetAtendimentoStatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetAtendimentoStatusResponse copyWith(
          void Function(SetAtendimentoStatusResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SetAtendimentoStatusResponse))
          as SetAtendimentoStatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetAtendimentoStatusResponse create() =>
      SetAtendimentoStatusResponse._();
  @$core.override
  SetAtendimentoStatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetAtendimentoStatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetAtendimentoStatusResponse>(create);
  static SetAtendimentoStatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  /// Onde o cartao ficou. 0 quando o fluxo nao tem coluna daquele tipo -- o
  /// cartao fica onde estava, que e melhor que sumir do quadro.
  @$pb.TagNumber(3)
  $core.int get etapaAtualId => $_getIZ(2);
  @$pb.TagNumber(3)
  set etapaAtualId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEtapaAtualId() => $_has(2);
  @$pb.TagNumber(3)
  void clearEtapaAtualId() => $_clearField(3);
}

class SendOutboundMessageRequest extends $pb.GeneratedMessage {
  factory SendOutboundMessageRequest({
    $core.int? atendimentoId,
    $core.String? conteudo,
    $core.String? tipo,
    $core.String? actionId,
    $core.int? mensagemCitadaId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (conteudo != null) result.conteudo = conteudo;
    if (tipo != null) result.tipo = tipo;
    if (actionId != null) result.actionId = actionId;
    if (mensagemCitadaId != null) result.mensagemCitadaId = mensagemCitadaId;
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
    ..aI(5, _omitFieldNames ? '' : 'mensagemCitadaId')
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

  /// N9/E6: responder citando outra mensagem da mesma thread.
  @$pb.TagNumber(5)
  $core.int get mensagemCitadaId => $_getIZ(4);
  @$pb.TagNumber(5)
  set mensagemCitadaId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMensagemCitadaId() => $_has(4);
  @$pb.TagNumber(5)
  void clearMensagemCitadaId() => $_clearField(5);
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

/// Passo 1 do envio: pedir onde subir. O binário NÃO trafega pelo gRPC-Web.
class SolicitarUploadMidiaRequest extends $pb.GeneratedMessage {
  factory SolicitarUploadMidiaRequest({
    $core.int? atendimentoId,
    $core.String? nomeArquivo,
    $core.String? mimetype,
    $fixnum.Int64? bytes,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (nomeArquivo != null) result.nomeArquivo = nomeArquivo;
    if (mimetype != null) result.mimetype = mimetype;
    if (bytes != null) result.bytes = bytes;
    return result;
  }

  SolicitarUploadMidiaRequest._();

  factory SolicitarUploadMidiaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolicitarUploadMidiaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolicitarUploadMidiaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'nomeArquivo')
    ..aOS(3, _omitFieldNames ? '' : 'mimetype')
    ..aInt64(4, _omitFieldNames ? '' : 'bytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadMidiaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadMidiaRequest copyWith(
          void Function(SolicitarUploadMidiaRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SolicitarUploadMidiaRequest))
          as SolicitarUploadMidiaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolicitarUploadMidiaRequest create() =>
      SolicitarUploadMidiaRequest._();
  @$core.override
  SolicitarUploadMidiaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolicitarUploadMidiaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolicitarUploadMidiaRequest>(create);
  static SolicitarUploadMidiaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nomeArquivo => $_getSZ(1);
  @$pb.TagNumber(2)
  set nomeArquivo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNomeArquivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearNomeArquivo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mimetype => $_getSZ(2);
  @$pb.TagNumber(3)
  set mimetype($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMimetype() => $_has(2);
  @$pb.TagNumber(3)
  void clearMimetype() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get bytes => $_getI64(3);
  @$pb.TagNumber(4)
  set bytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytes() => $_clearField(4);
}

class SolicitarUploadMidiaResponse extends $pb.GeneratedMessage {
  factory SolicitarUploadMidiaResponse({
    $core.String? urlUpload,
    $core.String? chave,
    $core.String? contentType,
    $fixnum.Int64? expiraEmSegundos,
  }) {
    final result = create();
    if (urlUpload != null) result.urlUpload = urlUpload;
    if (chave != null) result.chave = chave;
    if (contentType != null) result.contentType = contentType;
    if (expiraEmSegundos != null) result.expiraEmSegundos = expiraEmSegundos;
    return result;
  }

  SolicitarUploadMidiaResponse._();

  factory SolicitarUploadMidiaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolicitarUploadMidiaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolicitarUploadMidiaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'urlUpload')
    ..aOS(2, _omitFieldNames ? '' : 'chave')
    ..aOS(3, _omitFieldNames ? '' : 'contentType')
    ..aInt64(4, _omitFieldNames ? '' : 'expiraEmSegundos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadMidiaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadMidiaResponse copyWith(
          void Function(SolicitarUploadMidiaResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SolicitarUploadMidiaResponse))
          as SolicitarUploadMidiaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolicitarUploadMidiaResponse create() =>
      SolicitarUploadMidiaResponse._();
  @$core.override
  SolicitarUploadMidiaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolicitarUploadMidiaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolicitarUploadMidiaResponse>(create);
  static SolicitarUploadMidiaResponse? _defaultInstance;

  /// URL pré-assinada de PUT. É credencial de escrita: usar e descartar.
  @$pb.TagNumber(1)
  $core.String get urlUpload => $_getSZ(0);
  @$pb.TagNumber(1)
  set urlUpload($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrlUpload() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrlUpload() => $_clearField(1);

  /// Chave do objeto no bucket — é o que volta em EnviarMidiaAtendimento.
  @$pb.TagNumber(2)
  $core.String get chave => $_getSZ(1);
  @$pb.TagNumber(2)
  set chave($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChave() => $_has(1);
  @$pb.TagNumber(2)
  void clearChave() => $_clearField(2);

  /// Content-Type que o PUT DEVE mandar: o R2 recusa se divergir do assinado.
  @$pb.TagNumber(3)
  $core.String get contentType => $_getSZ(2);
  @$pb.TagNumber(3)
  set contentType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContentType() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentType() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expiraEmSegundos => $_getI64(3);
  @$pb.TagNumber(4)
  set expiraEmSegundos($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpiraEmSegundos() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpiraEmSegundos() => $_clearField(4);
}

/// Passo 3: o upload terminou. O servidor confere o conteúdo (magic bytes),
/// contabiliza a quota e só então põe a mensagem na thread.
class EnviarMidiaAtendimentoRequest extends $pb.GeneratedMessage {
  factory EnviarMidiaAtendimentoRequest({
    $core.int? atendimentoId,
    $core.String? chave,
    $core.String? mimetype,
    $core.String? nomeArquivo,
    $core.String? legenda,
    $core.bool? isPtt,
    $core.String? actionId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (chave != null) result.chave = chave;
    if (mimetype != null) result.mimetype = mimetype;
    if (nomeArquivo != null) result.nomeArquivo = nomeArquivo;
    if (legenda != null) result.legenda = legenda;
    if (isPtt != null) result.isPtt = isPtt;
    if (actionId != null) result.actionId = actionId;
    return result;
  }

  EnviarMidiaAtendimentoRequest._();

  factory EnviarMidiaAtendimentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnviarMidiaAtendimentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnviarMidiaAtendimentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'chave')
    ..aOS(3, _omitFieldNames ? '' : 'mimetype')
    ..aOS(4, _omitFieldNames ? '' : 'nomeArquivo')
    ..aOS(5, _omitFieldNames ? '' : 'legenda')
    ..aOB(6, _omitFieldNames ? '' : 'isPtt')
    ..aOS(7, _omitFieldNames ? '' : 'actionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarMidiaAtendimentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarMidiaAtendimentoRequest copyWith(
          void Function(EnviarMidiaAtendimentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as EnviarMidiaAtendimentoRequest))
          as EnviarMidiaAtendimentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnviarMidiaAtendimentoRequest create() =>
      EnviarMidiaAtendimentoRequest._();
  @$core.override
  EnviarMidiaAtendimentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnviarMidiaAtendimentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnviarMidiaAtendimentoRequest>(create);
  static EnviarMidiaAtendimentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get chave => $_getSZ(1);
  @$pb.TagNumber(2)
  set chave($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChave() => $_has(1);
  @$pb.TagNumber(2)
  void clearChave() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mimetype => $_getSZ(2);
  @$pb.TagNumber(3)
  set mimetype($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMimetype() => $_has(2);
  @$pb.TagNumber(3)
  void clearMimetype() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get nomeArquivo => $_getSZ(3);
  @$pb.TagNumber(4)
  set nomeArquivo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNomeArquivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearNomeArquivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get legenda => $_getSZ(4);
  @$pb.TagNumber(5)
  set legenda($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLegenda() => $_has(4);
  @$pb.TagNumber(5)
  void clearLegenda() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isPtt => $_getBF(5);
  @$pb.TagNumber(6)
  set isPtt($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsPtt() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsPtt() => $_clearField(6);

  /// Mesma idempotência do envio de texto (N7.2).
  @$pb.TagNumber(7)
  $core.String get actionId => $_getSZ(6);
  @$pb.TagNumber(7)
  set actionId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasActionId() => $_has(6);
  @$pb.TagNumber(7)
  void clearActionId() => $_clearField(7);
}

class EnviarMidiaAtendimentoResponse extends $pb.GeneratedMessage {
  factory EnviarMidiaAtendimentoResponse({
    $core.int? messageId,
  }) {
    final result = create();
    if (messageId != null) result.messageId = messageId;
    return result;
  }

  EnviarMidiaAtendimentoResponse._();

  factory EnviarMidiaAtendimentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnviarMidiaAtendimentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnviarMidiaAtendimentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'messageId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarMidiaAtendimentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarMidiaAtendimentoResponse copyWith(
          void Function(EnviarMidiaAtendimentoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as EnviarMidiaAtendimentoResponse))
          as EnviarMidiaAtendimentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnviarMidiaAtendimentoResponse create() =>
      EnviarMidiaAtendimentoResponse._();
  @$core.override
  EnviarMidiaAtendimentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnviarMidiaAtendimentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnviarMidiaAtendimentoResponse>(create);
  static EnviarMidiaAtendimentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get messageId => $_getIZ(0);
  @$pb.TagNumber(1)
  set messageId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => $_clearField(1);
}

/// P5 — um acontecimento da vida do atendimento.
///
/// Tudo o que ja era gravado em tabelas separadas (movimento de etapa, nota,
/// etiqueta, avaliacao) reunido numa linha do tempo: e assim que se explica,
/// depois, por que uma conversa demorou.
class EventoDaTimeline extends $pb.GeneratedMessage {
  factory EventoDaTimeline({
    $core.String? tipo,
    $fixnum.Int64? quando,
    $core.String? descricao,
    $core.String? autor,
    $core.bool? automatico,
  }) {
    final result = create();
    if (tipo != null) result.tipo = tipo;
    if (quando != null) result.quando = quando;
    if (descricao != null) result.descricao = descricao;
    if (autor != null) result.autor = autor;
    if (automatico != null) result.automatico = automatico;
    return result;
  }

  EventoDaTimeline._();

  factory EventoDaTimeline.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EventoDaTimeline.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EventoDaTimeline',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tipo')
    ..aInt64(2, _omitFieldNames ? '' : 'quando')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOS(4, _omitFieldNames ? '' : 'autor')
    ..aOB(5, _omitFieldNames ? '' : 'automatico')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventoDaTimeline clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EventoDaTimeline copyWith(void Function(EventoDaTimeline) updates) =>
      super.copyWith((message) => updates(message as EventoDaTimeline))
          as EventoDaTimeline;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EventoDaTimeline create() => EventoDaTimeline._();
  @$core.override
  EventoDaTimeline createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EventoDaTimeline getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EventoDaTimeline>(create);
  static EventoDaTimeline? _defaultInstance;

  /// "aberto" | "movido" | "nota" | "etiqueta" | "avaliado" | "encerrado"
  @$pb.TagNumber(1)
  $core.String get tipo => $_getSZ(0);
  @$pb.TagNumber(1)
  set tipo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTipo() => $_has(0);
  @$pb.TagNumber(1)
  void clearTipo() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get quando => $_getI64(1);
  @$pb.TagNumber(2)
  set quando($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQuando() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuando() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get autor => $_getSZ(3);
  @$pb.TagNumber(4)
  set autor($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAutor() => $_has(3);
  @$pb.TagNumber(4)
  void clearAutor() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get automatico => $_getBF(4);
  @$pb.TagNumber(5)
  set automatico($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAutomatico() => $_has(4);
  @$pb.TagNumber(5)
  void clearAutomatico() => $_clearField(5);
}

class ListarTimelineRequest extends $pb.GeneratedMessage {
  factory ListarTimelineRequest({
    $core.int? atendimentoId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    return result;
  }

  ListarTimelineRequest._();

  factory ListarTimelineRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarTimelineRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarTimelineRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarTimelineRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarTimelineRequest copyWith(
          void Function(ListarTimelineRequest) updates) =>
      super.copyWith((message) => updates(message as ListarTimelineRequest))
          as ListarTimelineRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarTimelineRequest create() => ListarTimelineRequest._();
  @$core.override
  ListarTimelineRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarTimelineRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListarTimelineRequest>(create);
  static ListarTimelineRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);
}

class ListarTimelineResponse extends $pb.GeneratedMessage {
  factory ListarTimelineResponse({
    $core.Iterable<EventoDaTimeline>? eventos,
  }) {
    final result = create();
    if (eventos != null) result.eventos.addAll(eventos);
    return result;
  }

  ListarTimelineResponse._();

  factory ListarTimelineResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarTimelineResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarTimelineResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<EventoDaTimeline>(1, _omitFieldNames ? '' : 'eventos',
        subBuilder: EventoDaTimeline.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarTimelineResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarTimelineResponse copyWith(
          void Function(ListarTimelineResponse) updates) =>
      super.copyWith((message) => updates(message as ListarTimelineResponse))
          as ListarTimelineResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarTimelineResponse create() => ListarTimelineResponse._();
  @$core.override
  ListarTimelineResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarTimelineResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListarTimelineResponse>(create);
  static ListarTimelineResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<EventoDaTimeline> get eventos => $_getList(0);
}

/// P5 — as outras conversas do mesmo contato.
class ListarAtendimentosDoContatoRequest extends $pb.GeneratedMessage {
  factory ListarAtendimentosDoContatoRequest({
    $core.int? contatoId,
    $core.int? limit,
  }) {
    final result = create();
    if (contatoId != null) result.contatoId = contatoId;
    if (limit != null) result.limit = limit;
    return result;
  }

  ListarAtendimentosDoContatoRequest._();

  factory ListarAtendimentosDoContatoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarAtendimentosDoContatoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarAtendimentosDoContatoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'contatoId')
    ..aI(2, _omitFieldNames ? '' : 'limit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarAtendimentosDoContatoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarAtendimentosDoContatoRequest copyWith(
          void Function(ListarAtendimentosDoContatoRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ListarAtendimentosDoContatoRequest))
          as ListarAtendimentosDoContatoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarAtendimentosDoContatoRequest create() =>
      ListarAtendimentosDoContatoRequest._();
  @$core.override
  ListarAtendimentosDoContatoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarAtendimentosDoContatoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListarAtendimentosDoContatoRequest>(
          create);
  static ListarAtendimentosDoContatoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get contatoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set contatoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContatoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearContatoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class ListarAtendimentosDoContatoResponse extends $pb.GeneratedMessage {
  factory ListarAtendimentosDoContatoResponse({
    $core.Iterable<AtendimentoResumo>? atendimentos,
  }) {
    final result = create();
    if (atendimentos != null) result.atendimentos.addAll(atendimentos);
    return result;
  }

  ListarAtendimentosDoContatoResponse._();

  factory ListarAtendimentosDoContatoResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarAtendimentosDoContatoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarAtendimentosDoContatoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<AtendimentoResumo>(1, _omitFieldNames ? '' : 'atendimentos',
        subBuilder: AtendimentoResumo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarAtendimentosDoContatoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarAtendimentosDoContatoResponse copyWith(
          void Function(ListarAtendimentosDoContatoResponse) updates) =>
      super.copyWith((message) =>
              updates(message as ListarAtendimentosDoContatoResponse))
          as ListarAtendimentosDoContatoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarAtendimentosDoContatoResponse create() =>
      ListarAtendimentosDoContatoResponse._();
  @$core.override
  ListarAtendimentosDoContatoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarAtendimentosDoContatoResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ListarAtendimentosDoContatoResponse>(create);
  static ListarAtendimentosDoContatoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AtendimentoResumo> get atendimentos => $_getList(0);
}

/// P5 — apagar uma nota interna.
class RemoverNotaRequest extends $pb.GeneratedMessage {
  factory RemoverNotaRequest({
    $fixnum.Int64? notaId,
    $core.int? atendimentoId,
  }) {
    final result = create();
    if (notaId != null) result.notaId = notaId;
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    return result;
  }

  RemoverNotaRequest._();

  factory RemoverNotaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RemoverNotaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoverNotaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'notaId')
    ..aI(2, _omitFieldNames ? '' : 'atendimentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoverNotaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoverNotaRequest copyWith(void Function(RemoverNotaRequest) updates) =>
      super.copyWith((message) => updates(message as RemoverNotaRequest))
          as RemoverNotaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoverNotaRequest create() => RemoverNotaRequest._();
  @$core.override
  RemoverNotaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RemoverNotaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoverNotaRequest>(create);
  static RemoverNotaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get notaId => $_getI64(0);
  @$pb.TagNumber(1)
  set notaId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNotaId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNotaId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get atendimentoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set atendimentoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtendimentoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtendimentoId() => $_clearField(2);
}

/// P5 — manutencao do catalogo de etiquetas.
class UpdateEtiquetaRequest extends $pb.GeneratedMessage {
  factory UpdateEtiquetaRequest({
    $fixnum.Int64? id,
    $core.String? nome,
    $core.String? cor,
    $core.String? descricao,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (cor != null) result.cor = cor;
    if (descricao != null) result.descricao = descricao;
    return result;
  }

  UpdateEtiquetaRequest._();

  factory UpdateEtiquetaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateEtiquetaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateEtiquetaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'cor')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEtiquetaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEtiquetaRequest copyWith(
          void Function(UpdateEtiquetaRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateEtiquetaRequest))
          as UpdateEtiquetaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateEtiquetaRequest create() => UpdateEtiquetaRequest._();
  @$core.override
  UpdateEtiquetaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateEtiquetaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateEtiquetaRequest>(create);
  static UpdateEtiquetaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
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

  @$pb.TagNumber(3)
  $core.String get cor => $_getSZ(2);
  @$pb.TagNumber(3)
  set cor($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCor() => $_has(2);
  @$pb.TagNumber(3)
  void clearCor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);
}

class DesativarEtiquetaRequest extends $pb.GeneratedMessage {
  factory DesativarEtiquetaRequest({
    $fixnum.Int64? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  DesativarEtiquetaRequest._();

  factory DesativarEtiquetaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DesativarEtiquetaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DesativarEtiquetaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DesativarEtiquetaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DesativarEtiquetaRequest copyWith(
          void Function(DesativarEtiquetaRequest) updates) =>
      super.copyWith((message) => updates(message as DesativarEtiquetaRequest))
          as DesativarEtiquetaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DesativarEtiquetaRequest create() => DesativarEtiquetaRequest._();
  @$core.override
  DesativarEtiquetaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DesativarEtiquetaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DesativarEtiquetaRequest>(create);
  static DesativarEtiquetaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

/// P4 — quem cuida da conversa.
///
/// `atendente_id = 0` significa "eu": o servidor resolve o atendente pelo
/// usuario do token, como a v1 fazia no "assumir".
class AtribuirAtendimentoRequest extends $pb.GeneratedMessage {
  factory AtribuirAtendimentoRequest({
    $core.int? atendimentoId,
    $core.int? atendenteId,
    $core.bool? devolverParaFila,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (atendenteId != null) result.atendenteId = atendenteId;
    if (devolverParaFila != null) result.devolverParaFila = devolverParaFila;
    return result;
  }

  AtribuirAtendimentoRequest._();

  factory AtribuirAtendimentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtribuirAtendimentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtribuirAtendimentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aI(2, _omitFieldNames ? '' : 'atendenteId')
    ..aOB(3, _omitFieldNames ? '' : 'devolverParaFila')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtribuirAtendimentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtribuirAtendimentoRequest copyWith(
          void Function(AtribuirAtendimentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as AtribuirAtendimentoRequest))
          as AtribuirAtendimentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtribuirAtendimentoRequest create() => AtribuirAtendimentoRequest._();
  @$core.override
  AtribuirAtendimentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtribuirAtendimentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtribuirAtendimentoRequest>(create);
  static AtribuirAtendimentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get atendenteId => $_getIZ(1);
  @$pb.TagNumber(2)
  set atendenteId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtendenteId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtendenteId() => $_clearField(2);

  /// true devolve a conversa para a fila (tira o dono).
  @$pb.TagNumber(3)
  $core.bool get devolverParaFila => $_getBF(2);
  @$pb.TagNumber(3)
  set devolverParaFila($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDevolverParaFila() => $_has(2);
  @$pb.TagNumber(3)
  void clearDevolverParaFila() => $_clearField(3);
}

class AtribuirAtendimentoResponse extends $pb.GeneratedMessage {
  factory AtribuirAtendimentoResponse({
    $core.bool? atribuido,
    $core.String? motivo,
  }) {
    final result = create();
    if (atribuido != null) result.atribuido = atribuido;
    if (motivo != null) result.motivo = motivo;
    return result;
  }

  AtribuirAtendimentoResponse._();

  factory AtribuirAtendimentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtribuirAtendimentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtribuirAtendimentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'atribuido')
    ..aOS(2, _omitFieldNames ? '' : 'motivo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtribuirAtendimentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtribuirAtendimentoResponse copyWith(
          void Function(AtribuirAtendimentoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as AtribuirAtendimentoResponse))
          as AtribuirAtendimentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtribuirAtendimentoResponse create() =>
      AtribuirAtendimentoResponse._();
  @$core.override
  AtribuirAtendimentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtribuirAtendimentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtribuirAtendimentoResponse>(create);
  static AtribuirAtendimentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get atribuido => $_getBF(0);
  @$pb.TagNumber(1)
  set atribuido($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtribuido() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtribuido() => $_clearField(1);

  /// Preenchido quando a conversa ja tinha dono: atribuir nao rouba conversa.
  @$pb.TagNumber(2)
  $core.String get motivo => $_getSZ(1);
  @$pb.TagNumber(2)
  set motivo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMotivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearMotivo() => $_clearField(2);
}

/// P4 — urgencia do cartao: "baixa", "normal", "alta" ou "urgente".
class DefinirPrioridadeRequest extends $pb.GeneratedMessage {
  factory DefinirPrioridadeRequest({
    $core.int? atendimentoId,
    $core.String? prioridade,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (prioridade != null) result.prioridade = prioridade;
    return result;
  }

  DefinirPrioridadeRequest._();

  factory DefinirPrioridadeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirPrioridadeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirPrioridadeRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'prioridade')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirPrioridadeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirPrioridadeRequest copyWith(
          void Function(DefinirPrioridadeRequest) updates) =>
      super.copyWith((message) => updates(message as DefinirPrioridadeRequest))
          as DefinirPrioridadeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirPrioridadeRequest create() => DefinirPrioridadeRequest._();
  @$core.override
  DefinirPrioridadeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirPrioridadeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirPrioridadeRequest>(create);
  static DefinirPrioridadeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get prioridade => $_getSZ(1);
  @$pb.TagNumber(2)
  set prioridade($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPrioridade() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrioridade() => $_clearField(2);
}

class DefinirPrioridadeResponse extends $pb.GeneratedMessage {
  factory DefinirPrioridadeResponse({
    $core.bool? definida,
  }) {
    final result = create();
    if (definida != null) result.definida = definida;
    return result;
  }

  DefinirPrioridadeResponse._();

  factory DefinirPrioridadeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirPrioridadeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirPrioridadeResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'definida')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirPrioridadeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirPrioridadeResponse copyWith(
          void Function(DefinirPrioridadeResponse) updates) =>
      super.copyWith((message) => updates(message as DefinirPrioridadeResponse))
          as DefinirPrioridadeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirPrioridadeResponse create() => DefinirPrioridadeResponse._();
  @$core.override
  DefinirPrioridadeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirPrioridadeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirPrioridadeResponse>(create);
  static DefinirPrioridadeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get definida => $_getBF(0);
  @$pb.TagNumber(1)
  set definida($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDefinida() => $_has(0);
  @$pb.TagNumber(1)
  void clearDefinida() => $_clearField(1);
}

/// P4 — transferir a conversa para outro fluxo, pela tela.
///
/// A IA ja fazia isso desde a N6.3; o RPC existia no `data_postgres` e nunca
/// teve caminho da borda, entao o supervisor nao conseguia corrigir a mao.
class TransferirParaFluxoRequest extends $pb.GeneratedMessage {
  factory TransferirParaFluxoRequest({
    $core.int? atendimentoId,
    $core.int? fluxoId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (fluxoId != null) result.fluxoId = fluxoId;
    return result;
  }

  TransferirParaFluxoRequest._();

  factory TransferirParaFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TransferirParaFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TransferirParaFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aI(2, _omitFieldNames ? '' : 'fluxoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferirParaFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferirParaFluxoRequest copyWith(
          void Function(TransferirParaFluxoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as TransferirParaFluxoRequest))
          as TransferirParaFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransferirParaFluxoRequest create() => TransferirParaFluxoRequest._();
  @$core.override
  TransferirParaFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TransferirParaFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TransferirParaFluxoRequest>(create);
  static TransferirParaFluxoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get fluxoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set fluxoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFluxoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFluxoId() => $_clearField(2);
}

class TransferirParaFluxoResponse extends $pb.GeneratedMessage {
  factory TransferirParaFluxoResponse({
    $core.bool? transferido,
    $core.int? fluxoId,
    $core.String? fluxoNome,
    $core.int? etapaId,
    $core.String? etapaNome,
    $core.String? motivo,
  }) {
    final result = create();
    if (transferido != null) result.transferido = transferido;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (fluxoNome != null) result.fluxoNome = fluxoNome;
    if (etapaId != null) result.etapaId = etapaId;
    if (etapaNome != null) result.etapaNome = etapaNome;
    if (motivo != null) result.motivo = motivo;
    return result;
  }

  TransferirParaFluxoResponse._();

  factory TransferirParaFluxoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TransferirParaFluxoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TransferirParaFluxoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'transferido')
    ..aI(2, _omitFieldNames ? '' : 'fluxoId')
    ..aOS(3, _omitFieldNames ? '' : 'fluxoNome')
    ..aI(4, _omitFieldNames ? '' : 'etapaId')
    ..aOS(5, _omitFieldNames ? '' : 'etapaNome')
    ..aOS(6, _omitFieldNames ? '' : 'motivo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferirParaFluxoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferirParaFluxoResponse copyWith(
          void Function(TransferirParaFluxoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as TransferirParaFluxoResponse))
          as TransferirParaFluxoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TransferirParaFluxoResponse create() =>
      TransferirParaFluxoResponse._();
  @$core.override
  TransferirParaFluxoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TransferirParaFluxoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TransferirParaFluxoResponse>(create);
  static TransferirParaFluxoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get transferido => $_getBF(0);
  @$pb.TagNumber(1)
  set transferido($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTransferido() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferido() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get fluxoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set fluxoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFluxoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFluxoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fluxoNome => $_getSZ(2);
  @$pb.TagNumber(3)
  set fluxoNome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFluxoNome() => $_has(2);
  @$pb.TagNumber(3)
  void clearFluxoNome() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get etapaId => $_getIZ(3);
  @$pb.TagNumber(4)
  set etapaId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEtapaId() => $_has(3);
  @$pb.TagNumber(4)
  void clearEtapaId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get etapaNome => $_getSZ(4);
  @$pb.TagNumber(5)
  set etapaNome($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEtapaNome() => $_has(4);
  @$pb.TagNumber(5)
  void clearEtapaNome() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get motivo => $_getSZ(5);
  @$pb.TagNumber(6)
  set motivo($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMotivo() => $_has(5);
  @$pb.TagNumber(6)
  void clearMotivo() => $_clearField(6);
}

/// P4 — o quadro em CSV.
///
/// Exportacao de PII em massa: e auditada no servidor, como a de tenants.
class ExportarQuadroRequest extends $pb.GeneratedMessage {
  factory ExportarQuadroRequest({
    $core.String? status,
    $core.int? departamentoId,
    $core.String? busca,
    $core.bool? somenteMeus,
    $core.bool? somenteNaoLidos,
  }) {
    final result = create();
    if (status != null) result.status = status;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (busca != null) result.busca = busca;
    if (somenteMeus != null) result.somenteMeus = somenteMeus;
    if (somenteNaoLidos != null) result.somenteNaoLidos = somenteNaoLidos;
    return result;
  }

  ExportarQuadroRequest._();

  factory ExportarQuadroRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExportarQuadroRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportarQuadroRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..aI(2, _omitFieldNames ? '' : 'departamentoId')
    ..aOS(3, _omitFieldNames ? '' : 'busca')
    ..aOB(4, _omitFieldNames ? '' : 'somenteMeus')
    ..aOB(5, _omitFieldNames ? '' : 'somenteNaoLidos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportarQuadroRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportarQuadroRequest copyWith(
          void Function(ExportarQuadroRequest) updates) =>
      super.copyWith((message) => updates(message as ExportarQuadroRequest))
          as ExportarQuadroRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExportarQuadroRequest create() => ExportarQuadroRequest._();
  @$core.override
  ExportarQuadroRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExportarQuadroRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportarQuadroRequest>(create);
  static ExportarQuadroRequest? _defaultInstance;

  /// Mesmo recorte do ListAtendimentos: exporta-se o que esta na tela.
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
  $core.String get busca => $_getSZ(2);
  @$pb.TagNumber(3)
  set busca($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBusca() => $_has(2);
  @$pb.TagNumber(3)
  void clearBusca() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get somenteMeus => $_getBF(3);
  @$pb.TagNumber(4)
  set somenteMeus($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSomenteMeus() => $_has(3);
  @$pb.TagNumber(4)
  void clearSomenteMeus() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get somenteNaoLidos => $_getBF(4);
  @$pb.TagNumber(5)
  set somenteNaoLidos($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSomenteNaoLidos() => $_has(4);
  @$pb.TagNumber(5)
  void clearSomenteNaoLidos() => $_clearField(5);
}

class ExportarQuadroResponse extends $pb.GeneratedMessage {
  factory ExportarQuadroResponse({
    $core.List<$core.int>? csv,
    $core.int? linhas,
  }) {
    final result = create();
    if (csv != null) result.csv = csv;
    if (linhas != null) result.linhas = linhas;
    return result;
  }

  ExportarQuadroResponse._();

  factory ExportarQuadroResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExportarQuadroResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportarQuadroResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'csv', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'linhas')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportarQuadroResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportarQuadroResponse copyWith(
          void Function(ExportarQuadroResponse) updates) =>
      super.copyWith((message) => updates(message as ExportarQuadroResponse))
          as ExportarQuadroResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExportarQuadroResponse create() => ExportarQuadroResponse._();
  @$core.override
  ExportarQuadroResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExportarQuadroResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportarQuadroResponse>(create);
  static ExportarQuadroResponse? _defaultInstance;

  /// CSV em UTF-8, com cabecalho.
  @$pb.TagNumber(1)
  $core.List<$core.int> get csv => $_getN(0);
  @$pb.TagNumber(1)
  set csv($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCsv() => $_has(0);
  @$pb.TagNumber(1)
  void clearCsv() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get linhas => $_getIZ(1);
  @$pb.TagNumber(2)
  set linhas($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLinhas() => $_has(1);
  @$pb.TagNumber(2)
  void clearLinhas() => $_clearField(2);
}

/// P3 — "digitando..." / "gravando audio..." do atendente para o contato.
///
/// E efemero: nao grava nada, nao entra na thread. O `data_whatsapp` ja sabia
/// mandar (`SetWhatsappPresence`); faltava caminho da borda ate ele.
class EnviarPresencaRequest extends $pb.GeneratedMessage {
  factory EnviarPresencaRequest({
    $core.int? atendimentoId,
    $core.String? situacao,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (situacao != null) result.situacao = situacao;
    return result;
  }

  EnviarPresencaRequest._();

  factory EnviarPresencaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnviarPresencaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnviarPresencaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'situacao')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarPresencaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarPresencaRequest copyWith(
          void Function(EnviarPresencaRequest) updates) =>
      super.copyWith((message) => updates(message as EnviarPresencaRequest))
          as EnviarPresencaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnviarPresencaRequest create() => EnviarPresencaRequest._();
  @$core.override
  EnviarPresencaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnviarPresencaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnviarPresencaRequest>(create);
  static EnviarPresencaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  /// "composing", "recording" ou "paused".
  @$pb.TagNumber(2)
  $core.String get situacao => $_getSZ(1);
  @$pb.TagNumber(2)
  set situacao($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSituacao() => $_has(1);
  @$pb.TagNumber(2)
  void clearSituacao() => $_clearField(2);
}

class EnviarPresencaResponse extends $pb.GeneratedMessage {
  factory EnviarPresencaResponse({
    $core.bool? enviado,
  }) {
    final result = create();
    if (enviado != null) result.enviado = enviado;
    return result;
  }

  EnviarPresencaResponse._();

  factory EnviarPresencaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnviarPresencaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnviarPresencaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enviado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarPresencaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnviarPresencaResponse copyWith(
          void Function(EnviarPresencaResponse) updates) =>
      super.copyWith((message) => updates(message as EnviarPresencaResponse))
          as EnviarPresencaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnviarPresencaResponse create() => EnviarPresencaResponse._();
  @$core.override
  EnviarPresencaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnviarPresencaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnviarPresencaResponse>(create);
  static EnviarPresencaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enviado => $_getBF(0);
  @$pb.TagNumber(1)
  set enviado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnviado() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnviado() => $_clearField(1);
}

class ListarMidiasAtendimentoRequest extends $pb.GeneratedMessage {
  factory ListarMidiasAtendimentoRequest({
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

  ListarMidiasAtendimentoRequest._();

  factory ListarMidiasAtendimentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarMidiasAtendimentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarMidiasAtendimentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aI(2, _omitFieldNames ? '' : 'limit')
    ..aI(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarMidiasAtendimentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarMidiasAtendimentoRequest copyWith(
          void Function(ListarMidiasAtendimentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListarMidiasAtendimentoRequest))
          as ListarMidiasAtendimentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarMidiasAtendimentoRequest create() =>
      ListarMidiasAtendimentoRequest._();
  @$core.override
  ListarMidiasAtendimentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarMidiasAtendimentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListarMidiasAtendimentoRequest>(create);
  static ListarMidiasAtendimentoRequest? _defaultInstance;

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

class ListarMidiasAtendimentoResponse extends $pb.GeneratedMessage {
  factory ListarMidiasAtendimentoResponse({
    $core.Iterable<MidiaMensagem>? midias,
  }) {
    final result = create();
    if (midias != null) result.midias.addAll(midias);
    return result;
  }

  ListarMidiasAtendimentoResponse._();

  factory ListarMidiasAtendimentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListarMidiasAtendimentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListarMidiasAtendimentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MidiaMensagem>(1, _omitFieldNames ? '' : 'midias',
        subBuilder: MidiaMensagem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarMidiasAtendimentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListarMidiasAtendimentoResponse copyWith(
          void Function(ListarMidiasAtendimentoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListarMidiasAtendimentoResponse))
          as ListarMidiasAtendimentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListarMidiasAtendimentoResponse create() =>
      ListarMidiasAtendimentoResponse._();
  @$core.override
  ListarMidiasAtendimentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListarMidiasAtendimentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListarMidiasAtendimentoResponse>(
          create);
  static ListarMidiasAtendimentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MidiaMensagem> get midias => $_getList(0);
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

/// N11 E8 — reenviar o e-mail de um convite pendente ou vencido. Renova a
/// validade e mantém o mesmo link.
class ReenviarConviteRequest extends $pb.GeneratedMessage {
  factory ReenviarConviteRequest({
    $core.String? inviteId,
  }) {
    final result = create();
    if (inviteId != null) result.inviteId = inviteId;
    return result;
  }

  ReenviarConviteRequest._();

  factory ReenviarConviteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReenviarConviteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReenviarConviteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'inviteId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarConviteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarConviteRequest copyWith(
          void Function(ReenviarConviteRequest) updates) =>
      super.copyWith((message) => updates(message as ReenviarConviteRequest))
          as ReenviarConviteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReenviarConviteRequest create() => ReenviarConviteRequest._();
  @$core.override
  ReenviarConviteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReenviarConviteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReenviarConviteRequest>(create);
  static ReenviarConviteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get inviteId => $_getSZ(0);
  @$pb.TagNumber(1)
  set inviteId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInviteId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInviteId() => $_clearField(1);
}

class ReenviarConviteResponse extends $pb.GeneratedMessage {
  factory ReenviarConviteResponse({
    $fixnum.Int64? expiresAt,
  }) {
    final result = create();
    if (expiresAt != null) result.expiresAt = expiresAt;
    return result;
  }

  ReenviarConviteResponse._();

  factory ReenviarConviteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReenviarConviteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReenviarConviteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'expiresAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarConviteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarConviteResponse copyWith(
          void Function(ReenviarConviteResponse) updates) =>
      super.copyWith((message) => updates(message as ReenviarConviteResponse))
          as ReenviarConviteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReenviarConviteResponse create() => ReenviarConviteResponse._();
  @$core.override
  ReenviarConviteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReenviarConviteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReenviarConviteResponse>(create);
  static ReenviarConviteResponse? _defaultInstance;

  /// Nova validade, em milissegundos desde a época.
  @$pb.TagNumber(1)
  $fixnum.Int64 get expiresAt => $_getI64(0);
  @$pb.TagNumber(1)
  set expiresAt($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasExpiresAt() => $_has(0);
  @$pb.TagNumber(1)
  void clearExpiresAt() => $_clearField(1);
}

/// D7 — usuarios de TODOS os tenants, para o painel do superusuario.
///
/// `ListTenantUsers` resolve o tenant a partir das claims de quem chama e nunca
/// enxerga alem do proprio; a v1 tinha esta visao global no admin do Django.
class AdminListUsersRequest extends $pb.GeneratedMessage {
  factory AdminListUsersRequest({
    $core.String? busca,
    $core.int? limite,
    $core.int? offset,
  }) {
    final result = create();
    if (busca != null) result.busca = busca;
    if (limite != null) result.limite = limite;
    if (offset != null) result.offset = offset;
    return result;
  }

  AdminListUsersRequest._();

  factory AdminListUsersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminListUsersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminListUsersRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'busca')
    ..aI(2, _omitFieldNames ? '' : 'limite')
    ..aI(3, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminListUsersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminListUsersRequest copyWith(
          void Function(AdminListUsersRequest) updates) =>
      super.copyWith((message) => updates(message as AdminListUsersRequest))
          as AdminListUsersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminListUsersRequest create() => AdminListUsersRequest._();
  @$core.override
  AdminListUsersRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminListUsersRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminListUsersRequest>(create);
  static AdminListUsersRequest? _defaultInstance;

  /// Casa em username, e-mail e nome. Vazio lista todo mundo.
  @$pb.TagNumber(1)
  $core.String get busca => $_getSZ(0);
  @$pb.TagNumber(1)
  set busca($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBusca() => $_has(0);
  @$pb.TagNumber(1)
  void clearBusca() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limite => $_getIZ(1);
  @$pb.TagNumber(2)
  set limite($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimite() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimite() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get offset => $_getIZ(2);
  @$pb.TagNumber(3)
  set offset($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffset() => $_clearField(3);
}

class AdminUserItem extends $pb.GeneratedMessage {
  factory AdminUserItem({
    $core.int? id,
    $core.String? username,
    $core.String? email,
    $core.String? nome,
    $core.bool? isActive,
    $core.bool? isSuperuser,
    $fixnum.Int64? lastLogin,
    $fixnum.Int64? dateJoined,
    $core.String? tenantDono,
    $core.String? tenantMembro,
    $core.String? papel,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (username != null) result.username = username;
    if (email != null) result.email = email;
    if (nome != null) result.nome = nome;
    if (isActive != null) result.isActive = isActive;
    if (isSuperuser != null) result.isSuperuser = isSuperuser;
    if (lastLogin != null) result.lastLogin = lastLogin;
    if (dateJoined != null) result.dateJoined = dateJoined;
    if (tenantDono != null) result.tenantDono = tenantDono;
    if (tenantMembro != null) result.tenantMembro = tenantMembro;
    if (papel != null) result.papel = papel;
    return result;
  }

  AdminUserItem._();

  factory AdminUserItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminUserItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminUserItem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'nome')
    ..aOB(5, _omitFieldNames ? '' : 'isActive')
    ..aOB(6, _omitFieldNames ? '' : 'isSuperuser')
    ..aInt64(7, _omitFieldNames ? '' : 'lastLogin')
    ..aInt64(8, _omitFieldNames ? '' : 'dateJoined')
    ..aOS(9, _omitFieldNames ? '' : 'tenantDono')
    ..aOS(10, _omitFieldNames ? '' : 'tenantMembro')
    ..aOS(11, _omitFieldNames ? '' : 'papel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminUserItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminUserItem copyWith(void Function(AdminUserItem) updates) =>
      super.copyWith((message) => updates(message as AdminUserItem))
          as AdminUserItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminUserItem create() => AdminUserItem._();
  @$core.override
  AdminUserItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminUserItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminUserItem>(create);
  static AdminUserItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

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
  $core.String get nome => $_getSZ(3);
  @$pb.TagNumber(4)
  set nome($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNome() => $_has(3);
  @$pb.TagNumber(4)
  void clearNome() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isActive => $_getBF(4);
  @$pb.TagNumber(5)
  set isActive($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsActive() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsActive() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isSuperuser => $_getBF(5);
  @$pb.TagNumber(6)
  set isSuperuser($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsSuperuser() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsSuperuser() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get lastLogin => $_getI64(6);
  @$pb.TagNumber(7)
  set lastLogin($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLastLogin() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastLogin() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get dateJoined => $_getI64(7);
  @$pb.TagNumber(8)
  set dateJoined($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDateJoined() => $_has(7);
  @$pb.TagNumber(8)
  void clearDateJoined() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get tenantDono => $_getSZ(8);
  @$pb.TagNumber(9)
  set tenantDono($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTenantDono() => $_has(8);
  @$pb.TagNumber(9)
  void clearTenantDono() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get tenantMembro => $_getSZ(9);
  @$pb.TagNumber(10)
  set tenantMembro($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasTenantMembro() => $_has(9);
  @$pb.TagNumber(10)
  void clearTenantMembro() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get papel => $_getSZ(10);
  @$pb.TagNumber(11)
  set papel($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasPapel() => $_has(10);
  @$pb.TagNumber(11)
  void clearPapel() => $_clearField(11);
}

class AdminListUsersResponse extends $pb.GeneratedMessage {
  factory AdminListUsersResponse({
    $core.Iterable<AdminUserItem>? usuarios,
  }) {
    final result = create();
    if (usuarios != null) result.usuarios.addAll(usuarios);
    return result;
  }

  AdminListUsersResponse._();

  factory AdminListUsersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminListUsersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminListUsersResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<AdminUserItem>(1, _omitFieldNames ? '' : 'usuarios',
        subBuilder: AdminUserItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminListUsersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminListUsersResponse copyWith(
          void Function(AdminListUsersResponse) updates) =>
      super.copyWith((message) => updates(message as AdminListUsersResponse))
          as AdminListUsersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminListUsersResponse create() => AdminListUsersResponse._();
  @$core.override
  AdminListUsersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminListUsersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminListUsersResponse>(create);
  static AdminListUsersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<AdminUserItem> get usuarios => $_getList(0);
}

/// D7 — bloqueia/desbloqueia o acesso de um usuario.
class AdminSetUserActiveRequest extends $pb.GeneratedMessage {
  factory AdminSetUserActiveRequest({
    $core.int? userId,
    $core.bool? ativo,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  AdminSetUserActiveRequest._();

  factory AdminSetUserActiveRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminSetUserActiveRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminSetUserActiveRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'userId')
    ..aOB(2, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminSetUserActiveRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminSetUserActiveRequest copyWith(
          void Function(AdminSetUserActiveRequest) updates) =>
      super.copyWith((message) => updates(message as AdminSetUserActiveRequest))
          as AdminSetUserActiveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminSetUserActiveRequest create() => AdminSetUserActiveRequest._();
  @$core.override
  AdminSetUserActiveRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminSetUserActiveRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminSetUserActiveRequest>(create);
  static AdminSetUserActiveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get userId => $_getIZ(0);
  @$pb.TagNumber(1)
  set userId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get ativo => $_getBF(1);
  @$pb.TagNumber(2)
  set ativo($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtivo() => $_clearField(2);
}

class AdminSetUserActiveResponse extends $pb.GeneratedMessage {
  factory AdminSetUserActiveResponse({
    $core.bool? ativo,
  }) {
    final result = create();
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  AdminSetUserActiveResponse._();

  factory AdminSetUserActiveResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AdminSetUserActiveResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AdminSetUserActiveResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminSetUserActiveResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AdminSetUserActiveResponse copyWith(
          void Function(AdminSetUserActiveResponse) updates) =>
      super.copyWith(
              (message) => updates(message as AdminSetUserActiveResponse))
          as AdminSetUserActiveResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AdminSetUserActiveResponse create() => AdminSetUserActiveResponse._();
  @$core.override
  AdminSetUserActiveResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AdminSetUserActiveResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AdminSetUserActiveResponse>(create);
  static AdminSetUserActiveResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ativo => $_getBF(0);
  @$pb.TagNumber(1)
  set ativo($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtivo() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtivo() => $_clearField(1);
}

class ListMcpGrantsRequest extends $pb.GeneratedMessage {
  factory ListMcpGrantsRequest() => create();

  ListMcpGrantsRequest._();

  factory ListMcpGrantsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMcpGrantsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMcpGrantsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMcpGrantsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMcpGrantsRequest copyWith(void Function(ListMcpGrantsRequest) updates) =>
      super.copyWith((message) => updates(message as ListMcpGrantsRequest))
          as ListMcpGrantsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMcpGrantsRequest create() => ListMcpGrantsRequest._();
  @$core.override
  ListMcpGrantsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMcpGrantsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMcpGrantsRequest>(create);
  static ListMcpGrantsRequest? _defaultInstance;
}

class McpGrantItem extends $pb.GeneratedMessage {
  factory McpGrantItem({
    $core.String? id,
    $core.String? clientId,
    $core.String? clientName,
    $core.String? redirectUri,
    $core.Iterable<$core.String>? scopes,
    $fixnum.Int64? lastUsedAt,
    $fixnum.Int64? createdAt,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (clientId != null) result.clientId = clientId;
    if (clientName != null) result.clientName = clientName;
    if (redirectUri != null) result.redirectUri = redirectUri;
    if (scopes != null) result.scopes.addAll(scopes);
    if (lastUsedAt != null) result.lastUsedAt = lastUsedAt;
    if (createdAt != null) result.createdAt = createdAt;
    return result;
  }

  McpGrantItem._();

  factory McpGrantItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory McpGrantItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'McpGrantItem',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'clientId')
    ..aOS(3, _omitFieldNames ? '' : 'clientName')
    ..aOS(4, _omitFieldNames ? '' : 'redirectUri')
    ..pPS(5, _omitFieldNames ? '' : 'scopes')
    ..aInt64(6, _omitFieldNames ? '' : 'lastUsedAt')
    ..aInt64(7, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  McpGrantItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  McpGrantItem copyWith(void Function(McpGrantItem) updates) =>
      super.copyWith((message) => updates(message as McpGrantItem))
          as McpGrantItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static McpGrantItem create() => McpGrantItem._();
  @$core.override
  McpGrantItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static McpGrantItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<McpGrantItem>(create);
  static McpGrantItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// URL do Client ID Metadata Document — é o identificador do cliente na spec
  /// MCP (Dynamic Client Registration foi deprecado).
  @$pb.TagNumber(2)
  $core.String get clientId => $_getSZ(1);
  @$pb.TagNumber(2)
  set clientId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClientId() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientId() => $_clearField(2);

  /// Nome exibido, vindo do documento do terceiro. TEXTO NÃO CONFIÁVEL: escapar
  /// na renderização.
  @$pb.TagNumber(3)
  $core.String get clientName => $_getSZ(2);
  @$pb.TagNumber(3)
  set clientName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientName() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientName() => $_clearField(3);

  /// Guardado inteiro para a trilha; a tela mostra só o hostname, que é o que o
  /// usuário consegue reconhecer.
  @$pb.TagNumber(4)
  $core.String get redirectUri => $_getSZ(3);
  @$pb.TagNumber(4)
  set redirectUri($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRedirectUri() => $_has(3);
  @$pb.TagNumber(4)
  void clearRedirectUri() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get scopes => $_getList(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get lastUsedAt => $_getI64(5);
  @$pb.TagNumber(6)
  set lastUsedAt($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLastUsedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastUsedAt() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAt => $_getI64(6);
  @$pb.TagNumber(7)
  set createdAt($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAt() => $_clearField(7);
}

class ListMcpGrantsResponse extends $pb.GeneratedMessage {
  factory ListMcpGrantsResponse({
    $core.Iterable<McpGrantItem>? grants,
  }) {
    final result = create();
    if (grants != null) result.grants.addAll(grants);
    return result;
  }

  ListMcpGrantsResponse._();

  factory ListMcpGrantsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMcpGrantsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMcpGrantsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<McpGrantItem>(1, _omitFieldNames ? '' : 'grants',
        subBuilder: McpGrantItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMcpGrantsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMcpGrantsResponse copyWith(
          void Function(ListMcpGrantsResponse) updates) =>
      super.copyWith((message) => updates(message as ListMcpGrantsResponse))
          as ListMcpGrantsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMcpGrantsResponse create() => ListMcpGrantsResponse._();
  @$core.override
  ListMcpGrantsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMcpGrantsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMcpGrantsResponse>(create);
  static ListMcpGrantsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<McpGrantItem> get grants => $_getList(0);
}

class RevokeMcpGrantRequest extends $pb.GeneratedMessage {
  factory RevokeMcpGrantRequest({
    $core.String? grantId,
  }) {
    final result = create();
    if (grantId != null) result.grantId = grantId;
    return result;
  }

  RevokeMcpGrantRequest._();

  factory RevokeMcpGrantRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeMcpGrantRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeMcpGrantRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'grantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeMcpGrantRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeMcpGrantRequest copyWith(
          void Function(RevokeMcpGrantRequest) updates) =>
      super.copyWith((message) => updates(message as RevokeMcpGrantRequest))
          as RevokeMcpGrantRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeMcpGrantRequest create() => RevokeMcpGrantRequest._();
  @$core.override
  RevokeMcpGrantRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeMcpGrantRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeMcpGrantRequest>(create);
  static RevokeMcpGrantRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get grantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set grantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGrantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGrantId() => $_clearField(1);
}

class RevokeMcpGrantResponse extends $pb.GeneratedMessage {
  factory RevokeMcpGrantResponse({
    $core.bool? success,
    $core.int? janelaRevogacaoMin,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (janelaRevogacaoMin != null)
      result.janelaRevogacaoMin = janelaRevogacaoMin;
    return result;
  }

  RevokeMcpGrantResponse._();

  factory RevokeMcpGrantResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RevokeMcpGrantResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RevokeMcpGrantResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aI(2, _omitFieldNames ? '' : 'janelaRevogacaoMin')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeMcpGrantResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RevokeMcpGrantResponse copyWith(
          void Function(RevokeMcpGrantResponse) updates) =>
      super.copyWith((message) => updates(message as RevokeMcpGrantResponse))
          as RevokeMcpGrantResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RevokeMcpGrantResponse create() => RevokeMcpGrantResponse._();
  @$core.override
  RevokeMcpGrantResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RevokeMcpGrantResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RevokeMcpGrantResponse>(create);
  static RevokeMcpGrantResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  /// Minutos que o acesso em curso ainda pode durar depois da revogação (o
  /// access token morre no `exp`). Vem do servidor para que a tela não precise
  /// repetir um número que a configuração pode mudar.
  @$pb.TagNumber(2)
  $core.int get janelaRevogacaoMin => $_getIZ(1);
  @$pb.TagNumber(2)
  set janelaRevogacaoMin($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasJanelaRevogacaoMin() => $_has(1);
  @$pb.TagNumber(2)
  void clearJanelaRevogacaoMin() => $_clearField(2);
}

/// B7 (doc 35-agentes F4) — reduz as permissões de um aplicativo conectado sem
/// desconectá-lo. Só reduz: ampliar exige reconectar e aprovar no consentimento.
class AjustarEscoposMcpGrantRequest extends $pb.GeneratedMessage {
  factory AjustarEscoposMcpGrantRequest({
    $core.String? grantId,
    $core.Iterable<$core.String>? scopes,
  }) {
    final result = create();
    if (grantId != null) result.grantId = grantId;
    if (scopes != null) result.scopes.addAll(scopes);
    return result;
  }

  AjustarEscoposMcpGrantRequest._();

  factory AjustarEscoposMcpGrantRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AjustarEscoposMcpGrantRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AjustarEscoposMcpGrantRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'grantId')
    ..pPS(2, _omitFieldNames ? '' : 'scopes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AjustarEscoposMcpGrantRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AjustarEscoposMcpGrantRequest copyWith(
          void Function(AjustarEscoposMcpGrantRequest) updates) =>
      super.copyWith(
              (message) => updates(message as AjustarEscoposMcpGrantRequest))
          as AjustarEscoposMcpGrantRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AjustarEscoposMcpGrantRequest create() =>
      AjustarEscoposMcpGrantRequest._();
  @$core.override
  AjustarEscoposMcpGrantRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AjustarEscoposMcpGrantRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AjustarEscoposMcpGrantRequest>(create);
  static AjustarEscoposMcpGrantRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get grantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set grantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGrantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGrantId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get scopes => $_getList(1);
}

class AjustarEscoposMcpGrantResponse extends $pb.GeneratedMessage {
  factory AjustarEscoposMcpGrantResponse({
    $core.Iterable<$core.String>? scopes,
    $core.int? janelaMin,
  }) {
    final result = create();
    if (scopes != null) result.scopes.addAll(scopes);
    if (janelaMin != null) result.janelaMin = janelaMin;
    return result;
  }

  AjustarEscoposMcpGrantResponse._();

  factory AjustarEscoposMcpGrantResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AjustarEscoposMcpGrantResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AjustarEscoposMcpGrantResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'scopes')
    ..aI(2, _omitFieldNames ? '' : 'janelaMin')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AjustarEscoposMcpGrantResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AjustarEscoposMcpGrantResponse copyWith(
          void Function(AjustarEscoposMcpGrantResponse) updates) =>
      super.copyWith(
              (message) => updates(message as AjustarEscoposMcpGrantResponse))
          as AjustarEscoposMcpGrantResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AjustarEscoposMcpGrantResponse create() =>
      AjustarEscoposMcpGrantResponse._();
  @$core.override
  AjustarEscoposMcpGrantResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AjustarEscoposMcpGrantResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AjustarEscoposMcpGrantResponse>(create);
  static AjustarEscoposMcpGrantResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get scopes => $_getList(0);

  /// Minutos até o agente sentir a mudança: vale na renovação seguinte do token.
  @$pb.TagNumber(2)
  $core.int get janelaMin => $_getIZ(1);
  @$pb.TagNumber(2)
  set janelaMin($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasJanelaMin() => $_has(1);
  @$pb.TagNumber(2)
  void clearJanelaMin() => $_clearField(2);
}

/// B3 (doc 35-agentes F1) — "o que o agente fez": a trilha do PRÓPRIO tenant.
/// Distinta de QueryAuditLog (superusuário, cross-tenant): aqui o tenant vem da
/// sessão, e quem não é tenant:admin só vê o que os próprios agentes fizeram.
class ListMyAuditLogRequest extends $pb.GeneratedMessage {
  factory ListMyAuditLogRequest({
    $core.String? origem,
    $core.String? grantId,
    $fixnum.Int64? desde,
    $core.int? limit,
    $core.int? offset,
  }) {
    final result = create();
    if (origem != null) result.origem = origem;
    if (grantId != null) result.grantId = grantId;
    if (desde != null) result.desde = desde;
    if (limit != null) result.limit = limit;
    if (offset != null) result.offset = offset;
    return result;
  }

  ListMyAuditLogRequest._();

  factory ListMyAuditLogRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyAuditLogRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyAuditLogRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'origem')
    ..aOS(2, _omitFieldNames ? '' : 'grantId')
    ..aInt64(3, _omitFieldNames ? '' : 'desde')
    ..aI(4, _omitFieldNames ? '' : 'limit')
    ..aI(5, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAuditLogRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAuditLogRequest copyWith(
          void Function(ListMyAuditLogRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyAuditLogRequest))
          as ListMyAuditLogRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyAuditLogRequest create() => ListMyAuditLogRequest._();
  @$core.override
  ListMyAuditLogRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyAuditLogRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyAuditLogRequest>(create);
  static ListMyAuditLogRequest? _defaultInstance;

  /// "" = tudo | "mcp" = só agentes | "painel" = só pessoas. Para quem não é
  /// admin o servidor usa sempre "mcp".
  @$pb.TagNumber(1)
  $core.String get origem => $_getSZ(0);
  @$pb.TagNumber(1)
  set origem($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOrigem() => $_has(0);
  @$pb.TagNumber(1)
  void clearOrigem() => $_clearField(1);

  /// Restringe a um aplicativo conectado (o `id` de McpGrantItem).
  @$pb.TagNumber(2)
  $core.String get grantId => $_getSZ(1);
  @$pb.TagNumber(2)
  set grantId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGrantId() => $_has(1);
  @$pb.TagNumber(2)
  void clearGrantId() => $_clearField(2);

  /// Só o que aconteceu a partir deste instante (ms desde a época). 0 = tudo.
  @$pb.TagNumber(3)
  $fixnum.Int64 get desde => $_getI64(2);
  @$pb.TagNumber(3)
  set desde($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDesde() => $_has(2);
  @$pb.TagNumber(3)
  void clearDesde() => $_clearField(3);

  /// Teto de 200 no servidor.
  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLimit() => $_has(3);
  @$pb.TagNumber(4)
  void clearLimit() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get offset => $_getIZ(4);
  @$pb.TagNumber(5)
  set offset($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearOffset() => $_clearField(5);
}

/// Sem a mensagem do evento, de propósito: alguns eventos guardam nome ou
/// e-mail na mensagem, e esta tela não mostra dado pessoal.
class MyAuditLogEntry extends $pb.GeneratedMessage {
  factory MyAuditLogEntry({
    $fixnum.Int64? timestamp,
    $core.String? eventType,
    $core.String? origem,
    $core.String? clientName,
    $core.String? tool,
    $core.int? userId,
    $core.String? userNome,
    $core.String? grantId,
  }) {
    final result = create();
    if (timestamp != null) result.timestamp = timestamp;
    if (eventType != null) result.eventType = eventType;
    if (origem != null) result.origem = origem;
    if (clientName != null) result.clientName = clientName;
    if (tool != null) result.tool = tool;
    if (userId != null) result.userId = userId;
    if (userNome != null) result.userNome = userNome;
    if (grantId != null) result.grantId = grantId;
    return result;
  }

  MyAuditLogEntry._();

  factory MyAuditLogEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyAuditLogEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyAuditLogEntry',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'timestamp')
    ..aOS(2, _omitFieldNames ? '' : 'eventType')
    ..aOS(3, _omitFieldNames ? '' : 'origem')
    ..aOS(4, _omitFieldNames ? '' : 'clientName')
    ..aOS(5, _omitFieldNames ? '' : 'tool')
    ..aI(6, _omitFieldNames ? '' : 'userId')
    ..aOS(7, _omitFieldNames ? '' : 'userNome')
    ..aOS(8, _omitFieldNames ? '' : 'grantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAuditLogEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAuditLogEntry copyWith(void Function(MyAuditLogEntry) updates) =>
      super.copyWith((message) => updates(message as MyAuditLogEntry))
          as MyAuditLogEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyAuditLogEntry create() => MyAuditLogEntry._();
  @$core.override
  MyAuditLogEntry createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyAuditLogEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyAuditLogEntry>(create);
  static MyAuditLogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get timestamp => $_getI64(0);
  @$pb.TagNumber(1)
  set timestamp($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestamp() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestamp() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventType => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventType() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventType() => $_clearField(2);

  /// "mcp" | "painel" — derivada do user_agent, não um campo da tabela.
  @$pb.TagNumber(3)
  $core.String get origem => $_getSZ(2);
  @$pb.TagNumber(3)
  set origem($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOrigem() => $_has(2);
  @$pb.TagNumber(3)
  void clearOrigem() => $_clearField(3);

  /// Nome do aplicativo, quando a origem é mcp. TEXTO DE TERCEIRO: escapar.
  @$pb.TagNumber(4)
  $core.String get clientName => $_getSZ(3);
  @$pb.TagNumber(4)
  set clientName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasClientName() => $_has(3);
  @$pb.TagNumber(4)
  void clearClientName() => $_clearField(4);

  /// Operação chamada pelo agente, quando a origem é mcp.
  @$pb.TagNumber(5)
  $core.String get tool => $_getSZ(4);
  @$pb.TagNumber(5)
  set tool($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTool() => $_has(4);
  @$pb.TagNumber(5)
  void clearTool() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get userId => $_getIZ(5);
  @$pb.TagNumber(6)
  set userId($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasUserId() => $_has(5);
  @$pb.TagNumber(6)
  void clearUserId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get userNome => $_getSZ(6);
  @$pb.TagNumber(7)
  set userNome($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasUserNome() => $_has(6);
  @$pb.TagNumber(7)
  void clearUserNome() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get grantId => $_getSZ(7);
  @$pb.TagNumber(8)
  set grantId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasGrantId() => $_has(7);
  @$pb.TagNumber(8)
  void clearGrantId() => $_clearField(8);
}

class ListMyAuditLogResponse extends $pb.GeneratedMessage {
  factory ListMyAuditLogResponse({
    $core.Iterable<MyAuditLogEntry>? entries,
  }) {
    final result = create();
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  ListMyAuditLogResponse._();

  factory ListMyAuditLogResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyAuditLogResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyAuditLogResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyAuditLogEntry>(1, _omitFieldNames ? '' : 'entries',
        subBuilder: MyAuditLogEntry.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAuditLogResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAuditLogResponse copyWith(
          void Function(ListMyAuditLogResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyAuditLogResponse))
          as ListMyAuditLogResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyAuditLogResponse create() => ListMyAuditLogResponse._();
  @$core.override
  ListMyAuditLogResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyAuditLogResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyAuditLogResponse>(create);
  static ListMyAuditLogResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyAuditLogEntry> get entries => $_getList(0);
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

/// Lê o progresso gravado — a contraparte que faltava do `SetOnboardingProgress`.
///
/// Sem ela o progresso era gravado e nunca lido: quem fechava o app no meio da
/// configuração reabria direto no workspace vazio, sem caminho de volta ao
/// roteiro, com a conta paga e inutilizável.
class GetMyOnboardingProgressRequest extends $pb.GeneratedMessage {
  factory GetMyOnboardingProgressRequest() => create();

  GetMyOnboardingProgressRequest._();

  factory GetMyOnboardingProgressRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyOnboardingProgressRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyOnboardingProgressRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyOnboardingProgressRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyOnboardingProgressRequest copyWith(
          void Function(GetMyOnboardingProgressRequest) updates) =>
      super.copyWith(
              (message) => updates(message as GetMyOnboardingProgressRequest))
          as GetMyOnboardingProgressRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyOnboardingProgressRequest create() =>
      GetMyOnboardingProgressRequest._();
  @$core.override
  GetMyOnboardingProgressRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyOnboardingProgressRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyOnboardingProgressRequest>(create);
  static GetMyOnboardingProgressRequest? _defaultInstance;
}

class GetMyOnboardingProgressResponse extends $pb.GeneratedMessage {
  factory GetMyOnboardingProgressResponse({
    $core.int? passo,
    $core.bool? concluido,
    $core.bool? pagamentoPendente,
    $core.String? assinaturaStatus,
    $core.String? planoNome,
    $core.int? planoId,
  }) {
    final result = create();
    if (passo != null) result.passo = passo;
    if (concluido != null) result.concluido = concluido;
    if (pagamentoPendente != null) result.pagamentoPendente = pagamentoPendente;
    if (assinaturaStatus != null) result.assinaturaStatus = assinaturaStatus;
    if (planoNome != null) result.planoNome = planoNome;
    if (planoId != null) result.planoId = planoId;
    return result;
  }

  GetMyOnboardingProgressResponse._();

  factory GetMyOnboardingProgressResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyOnboardingProgressResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyOnboardingProgressResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'passo')
    ..aOB(2, _omitFieldNames ? '' : 'concluido')
    ..aOB(3, _omitFieldNames ? '' : 'pagamentoPendente')
    ..aOS(4, _omitFieldNames ? '' : 'assinaturaStatus')
    ..aOS(5, _omitFieldNames ? '' : 'planoNome')
    ..aI(6, _omitFieldNames ? '' : 'planoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyOnboardingProgressResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyOnboardingProgressResponse copyWith(
          void Function(GetMyOnboardingProgressResponse) updates) =>
      super.copyWith(
              (message) => updates(message as GetMyOnboardingProgressResponse))
          as GetMyOnboardingProgressResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyOnboardingProgressResponse create() =>
      GetMyOnboardingProgressResponse._();
  @$core.override
  GetMyOnboardingProgressResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyOnboardingProgressResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyOnboardingProgressResponse>(
          create);
  static GetMyOnboardingProgressResponse? _defaultInstance;

  /// 5..8 enquanto o roteiro corre. 0 = nunca registrou nada.
  @$pb.TagNumber(1)
  $core.int get passo => $_getIZ(0);
  @$pb.TagNumber(1)
  set passo($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPasso() => $_has(0);
  @$pb.TagNumber(1)
  void clearPasso() => $_clearField(1);

  /// true = terminou (ou pulou o que faltava); o app vai para o workspace.
  @$pb.TagNumber(2)
  $core.bool get concluido => $_getBF(1);
  @$pb.TagNumber(2)
  set concluido($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConcluido() => $_has(1);
  @$pb.TagNumber(2)
  void clearConcluido() => $_clearField(2);

  /// Campos aditivos: o progresso não dizia nada sobre dinheiro, e por isso o
  /// guard mandava para /configuracao/* quem nunca pagou. Aditivos de propósito —
  /// campo novo em proto3 não quebra cliente antigo, que segue no comportamento
  /// atual (degradado, não quebrado) enquanto não atualiza.
  ///
  /// subscription.status != ACTIVE. Sem assinatura nenhuma também conta como
  /// pendente: o tenant não pode operar.
  @$pb.TagNumber(3)
  $core.bool get pagamentoPendente => $_getBF(2);
  @$pb.TagNumber(3)
  set pagamentoPendente($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPagamentoPendente() => $_has(2);
  @$pb.TagNumber(3)
  void clearPagamentoPendente() => $_clearField(3);

  /// PENDING_PAYMENT | ACTIVE | SUSPENDED | ... Vazio = sem assinatura.
  @$pb.TagNumber(4)
  $core.String get assinaturaStatus => $_getSZ(3);
  @$pb.TagNumber(4)
  set assinaturaStatus($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAssinaturaStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearAssinaturaStatus() => $_clearField(4);

  /// Para a tela dizer o que está sendo cobrado. Vazio = plano não escolhido.
  @$pb.TagNumber(5)
  $core.String get planoNome => $_getSZ(4);
  @$pb.TagNumber(5)
  set planoNome($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPlanoNome() => $_has(4);
  @$pb.TagNumber(5)
  void clearPlanoNome() => $_clearField(5);

  /// 0 = plano não escolhido.
  @$pb.TagNumber(6)
  $core.int get planoId => $_getIZ(5);
  @$pb.TagNumber(6)
  set planoId($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPlanoId() => $_has(5);
  @$pb.TagNumber(6)
  void clearPlanoId() => $_clearField(6);
}

/// Quitação da assinatura **depois do login**.
///
/// O `ConfirmPayment` do wizard exige `signup_token`, que morre com a sessão de
/// cadastro. Sem este RPC, um tenant cuja sessão expirou no meio do wizard entra
/// no app e não tem como pagar: esbarra em "assinatura inadimplente" a cada
/// cadastro e não existe tela que resolva.
///
/// O `tenant_id` vem das **claims**, nunca do request — mesma regra dos demais
/// `*My*`. Exige escopo `tenant:admin`: cobrança é assunto do dono, não do
/// colaborador.
class QuitarMinhaAssinaturaRequest extends $pb.GeneratedMessage {
  factory QuitarMinhaAssinaturaRequest({
    $core.String? provedor,
    $core.String? credencial,
  }) {
    final result = create();
    if (provedor != null) result.provedor = provedor;
    if (credencial != null) result.credencial = credencial;
    return result;
  }

  QuitarMinhaAssinaturaRequest._();

  factory QuitarMinhaAssinaturaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory QuitarMinhaAssinaturaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QuitarMinhaAssinaturaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'provedor')
    ..aOS(2, _omitFieldNames ? '' : 'credencial')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QuitarMinhaAssinaturaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QuitarMinhaAssinaturaRequest copyWith(
          void Function(QuitarMinhaAssinaturaRequest) updates) =>
      super.copyWith(
              (message) => updates(message as QuitarMinhaAssinaturaRequest))
          as QuitarMinhaAssinaturaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static QuitarMinhaAssinaturaRequest create() =>
      QuitarMinhaAssinaturaRequest._();
  @$core.override
  QuitarMinhaAssinaturaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static QuitarMinhaAssinaturaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QuitarMinhaAssinaturaRequest>(create);
  static QuitarMinhaAssinaturaRequest? _defaultInstance;

  /// `id` de um PaymentProvider (hoje só `voucher`).
  @$pb.TagNumber(1)
  $core.String get provedor => $_getSZ(0);
  @$pb.TagNumber(1)
  set provedor($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProvedor() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvedor() => $_clearField(1);

  /// O que o dono digitou. Para `voucher`, o código. É credencial: não entra em
  /// span, log nem auditoria.
  @$pb.TagNumber(2)
  $core.String get credencial => $_getSZ(1);
  @$pb.TagNumber(2)
  set credencial($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCredencial() => $_has(1);
  @$pb.TagNumber(2)
  void clearCredencial() => $_clearField(2);
}

class QuitarMinhaAssinaturaResponse extends $pb.GeneratedMessage {
  factory QuitarMinhaAssinaturaResponse({
    $core.bool? confirmado,
    $core.String? assinaturaStatus,
    $core.String? urlExterna,
    $core.String? motivo,
    $core.String? erroLegivel,
  }) {
    final result = create();
    if (confirmado != null) result.confirmado = confirmado;
    if (assinaturaStatus != null) result.assinaturaStatus = assinaturaStatus;
    if (urlExterna != null) result.urlExterna = urlExterna;
    if (motivo != null) result.motivo = motivo;
    if (erroLegivel != null) result.erroLegivel = erroLegivel;
    return result;
  }

  QuitarMinhaAssinaturaResponse._();

  factory QuitarMinhaAssinaturaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory QuitarMinhaAssinaturaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'QuitarMinhaAssinaturaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'confirmado')
    ..aOS(2, _omitFieldNames ? '' : 'assinaturaStatus')
    ..aOS(3, _omitFieldNames ? '' : 'urlExterna')
    ..aOS(4, _omitFieldNames ? '' : 'motivo')
    ..aOS(5, _omitFieldNames ? '' : 'erroLegivel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QuitarMinhaAssinaturaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  QuitarMinhaAssinaturaResponse copyWith(
          void Function(QuitarMinhaAssinaturaResponse) updates) =>
      super.copyWith(
              (message) => updates(message as QuitarMinhaAssinaturaResponse))
          as QuitarMinhaAssinaturaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static QuitarMinhaAssinaturaResponse create() =>
      QuitarMinhaAssinaturaResponse._();
  @$core.override
  QuitarMinhaAssinaturaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static QuitarMinhaAssinaturaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<QuitarMinhaAssinaturaResponse>(create);
  static QuitarMinhaAssinaturaResponse? _defaultInstance;

  /// true = assinatura ativa ao fim da chamada (inclusive se já estava).
  @$pb.TagNumber(1)
  $core.bool get confirmado => $_getBF(0);
  @$pb.TagNumber(1)
  set confirmado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfirmado() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfirmado() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get assinaturaStatus => $_getSZ(1);
  @$pb.TagNumber(2)
  set assinaturaStatus($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAssinaturaStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearAssinaturaStatus() => $_clearField(2);

  /// Preenchida quando o provedor exige concluir o pagamento fora do app.
  @$pb.TagNumber(3)
  $core.String get urlExterna => $_getSZ(2);
  @$pb.TagNumber(3)
  set urlExterna($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUrlExterna() => $_has(2);
  @$pb.TagNumber(3)
  void clearUrlExterna() => $_clearField(3);

  /// Recusa de negócio (código expirado, já usado...). Vai para junto do campo
  /// na tela, não para um erro de RPC.
  @$pb.TagNumber(4)
  $core.String get motivo => $_getSZ(3);
  @$pb.TagNumber(4)
  set motivo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMotivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearMotivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get erroLegivel => $_getSZ(4);
  @$pb.TagNumber(5)
  set erroLegivel($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErroLegivel() => $_has(4);
  @$pb.TagNumber(5)
  void clearErroLegivel() => $_clearField(5);
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
    $core.String? confiancaMinimaTransferencia,
    $core.String? confiancaMinimaAutomatica,
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
    if (confiancaMinimaTransferencia != null)
      result.confiancaMinimaTransferencia = confiancaMinimaTransferencia;
    if (confiancaMinimaAutomatica != null)
      result.confiancaMinimaAutomatica = confiancaMinimaAutomatica;
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
    ..aOS(21, _omitFieldNames ? '' : 'confiancaMinimaTransferencia')
    ..aOS(22, _omitFieldNames ? '' : 'confiancaMinimaAutomatica')
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

  /// B4 — limiares de confiança da IA, como string decimal ("0.80").
  /// Vazio = não mexer. "0" em confianca_minima_transferencia desliga o veto.
  @$pb.TagNumber(21)
  $core.String get confiancaMinimaTransferencia => $_getSZ(20);
  @$pb.TagNumber(21)
  set confiancaMinimaTransferencia($core.String value) =>
      $_setString(20, value);
  @$pb.TagNumber(21)
  $core.bool hasConfiancaMinimaTransferencia() => $_has(20);
  @$pb.TagNumber(21)
  void clearConfiancaMinimaTransferencia() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.String get confiancaMinimaAutomatica => $_getSZ(21);
  @$pb.TagNumber(22)
  set confiancaMinimaAutomatica($core.String value) => $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasConfiancaMinimaAutomatica() => $_has(21);
  @$pb.TagNumber(22)
  void clearConfiancaMinimaAutomatica() => $_clearField(22);
}

class MyFluxo extends $pb.GeneratedMessage {
  factory MyFluxo({
    $core.int? id,
    $core.int? departamentoId,
    $core.String? departamentoNome,
    $core.String? nome,
    $core.String? descricao,
    $core.bool? ativo,
    $core.int? etapas,
    $core.int? atendimentosAbertos,
    $fixnum.Int64? criadoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (departamentoNome != null) result.departamentoNome = departamentoNome;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (ativo != null) result.ativo = ativo;
    if (etapas != null) result.etapas = etapas;
    if (atendimentosAbertos != null)
      result.atendimentosAbertos = atendimentosAbertos;
    if (criadoEm != null) result.criadoEm = criadoEm;
    return result;
  }

  MyFluxo._();

  factory MyFluxo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyFluxo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyFluxo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'departamentoId')
    ..aOS(3, _omitFieldNames ? '' : 'departamentoNome')
    ..aOS(4, _omitFieldNames ? '' : 'nome')
    ..aOS(5, _omitFieldNames ? '' : 'descricao')
    ..aOB(6, _omitFieldNames ? '' : 'ativo')
    ..aI(7, _omitFieldNames ? '' : 'etapas')
    ..aI(8, _omitFieldNames ? '' : 'atendimentosAbertos')
    ..aInt64(9, _omitFieldNames ? '' : 'criadoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxo copyWith(void Function(MyFluxo) updates) =>
      super.copyWith((message) => updates(message as MyFluxo)) as MyFluxo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyFluxo create() => MyFluxo._();
  @$core.override
  MyFluxo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyFluxo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MyFluxo>(create);
  static MyFluxo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get departamentoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set departamentoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDepartamentoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDepartamentoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get departamentoNome => $_getSZ(2);
  @$pb.TagNumber(3)
  set departamentoNome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDepartamentoNome() => $_has(2);
  @$pb.TagNumber(3)
  void clearDepartamentoNome() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get nome => $_getSZ(3);
  @$pb.TagNumber(4)
  set nome($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNome() => $_has(3);
  @$pb.TagNumber(4)
  void clearNome() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get descricao => $_getSZ(4);
  @$pb.TagNumber(5)
  set descricao($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDescricao() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescricao() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get ativo => $_getBF(5);
  @$pb.TagNumber(6)
  set ativo($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAtivo() => $_has(5);
  @$pb.TagNumber(6)
  void clearAtivo() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get etapas => $_getIZ(6);
  @$pb.TagNumber(7)
  set etapas($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEtapas() => $_has(6);
  @$pb.TagNumber(7)
  void clearEtapas() => $_clearField(7);

  /// Conversas que ainda não terminaram neste fluxo. É o número que diz se
  /// desativá-lo deixaria gente no meio do caminho.
  @$pb.TagNumber(8)
  $core.int get atendimentosAbertos => $_getIZ(7);
  @$pb.TagNumber(8)
  set atendimentosAbertos($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAtendimentosAbertos() => $_has(7);
  @$pb.TagNumber(8)
  void clearAtendimentosAbertos() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get criadoEm => $_getI64(8);
  @$pb.TagNumber(9)
  set criadoEm($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCriadoEm() => $_has(8);
  @$pb.TagNumber(9)
  void clearCriadoEm() => $_clearField(9);
}

class ListMyFluxosRequest extends $pb.GeneratedMessage {
  factory ListMyFluxosRequest() => create();

  ListMyFluxosRequest._();

  factory ListMyFluxosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyFluxosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyFluxosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyFluxosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyFluxosRequest copyWith(void Function(ListMyFluxosRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyFluxosRequest))
          as ListMyFluxosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyFluxosRequest create() => ListMyFluxosRequest._();
  @$core.override
  ListMyFluxosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyFluxosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyFluxosRequest>(create);
  static ListMyFluxosRequest? _defaultInstance;
}

class ListMyFluxosResponse extends $pb.GeneratedMessage {
  factory ListMyFluxosResponse({
    $core.Iterable<MyFluxo>? fluxos,
  }) {
    final result = create();
    if (fluxos != null) result.fluxos.addAll(fluxos);
    return result;
  }

  ListMyFluxosResponse._();

  factory ListMyFluxosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyFluxosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyFluxosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyFluxo>(1, _omitFieldNames ? '' : 'fluxos',
        subBuilder: MyFluxo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyFluxosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyFluxosResponse copyWith(void Function(ListMyFluxosResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyFluxosResponse))
          as ListMyFluxosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyFluxosResponse create() => ListMyFluxosResponse._();
  @$core.override
  ListMyFluxosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyFluxosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyFluxosResponse>(create);
  static ListMyFluxosResponse? _defaultInstance;

  /// Inativos vêm junto: escondê-los deixaria o tenant sem como reativar o que
  /// desativou por engano.
  @$pb.TagNumber(1)
  $pb.PbList<MyFluxo> get fluxos => $_getList(0);
}

class CreateMyFluxoRequest extends $pb.GeneratedMessage {
  factory CreateMyFluxoRequest({
    $core.int? departamentoId,
    $core.String? nome,
    $core.String? descricao,
  }) {
    final result = create();
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    return result;
  }

  CreateMyFluxoRequest._();

  factory CreateMyFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'departamentoId')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyFluxoRequest copyWith(void Function(CreateMyFluxoRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyFluxoRequest))
          as CreateMyFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyFluxoRequest create() => CreateMyFluxoRequest._();
  @$core.override
  CreateMyFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyFluxoRequest>(create);
  static CreateMyFluxoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get departamentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set departamentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDepartamentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDepartamentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nome => $_getSZ(1);
  @$pb.TagNumber(2)
  set nome($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNome() => $_has(1);
  @$pb.TagNumber(2)
  void clearNome() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);
}

class MyFluxoResponse extends $pb.GeneratedMessage {
  factory MyFluxoResponse({
    MyFluxo? fluxo,
  }) {
    final result = create();
    if (fluxo != null) result.fluxo = fluxo;
    return result;
  }

  MyFluxoResponse._();

  factory MyFluxoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyFluxoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyFluxoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyFluxo>(1, _omitFieldNames ? '' : 'fluxo',
        subBuilder: MyFluxo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxoResponse copyWith(void Function(MyFluxoResponse) updates) =>
      super.copyWith((message) => updates(message as MyFluxoResponse))
          as MyFluxoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyFluxoResponse create() => MyFluxoResponse._();
  @$core.override
  MyFluxoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyFluxoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyFluxoResponse>(create);
  static MyFluxoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyFluxo get fluxo => $_getN(0);
  @$pb.TagNumber(1)
  set fluxo(MyFluxo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFluxo() => $_has(0);
  @$pb.TagNumber(1)
  void clearFluxo() => $_clearField(1);
  @$pb.TagNumber(1)
  MyFluxo ensureFluxo() => $_ensure(0);
}

class UpdateMyFluxoRequest extends $pb.GeneratedMessage {
  factory UpdateMyFluxoRequest({
    $core.int? id,
    $core.String? nome,
    $core.String? descricao,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  UpdateMyFluxoRequest._();

  factory UpdateMyFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOB(4, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyFluxoRequest copyWith(void Function(UpdateMyFluxoRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyFluxoRequest))
          as UpdateMyFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyFluxoRequest create() => UpdateMyFluxoRequest._();
  @$core.override
  UpdateMyFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyFluxoRequest>(create);
  static UpdateMyFluxoRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get ativo => $_getBF(3);
  @$pb.TagNumber(4)
  set ativo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtivo() => $_clearField(4);
}

class MyFluxoIdRequest extends $pb.GeneratedMessage {
  factory MyFluxoIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyFluxoIdRequest._();

  factory MyFluxoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyFluxoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyFluxoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyFluxoIdRequest copyWith(void Function(MyFluxoIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyFluxoIdRequest))
          as MyFluxoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyFluxoIdRequest create() => MyFluxoIdRequest._();
  @$core.override
  MyFluxoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyFluxoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyFluxoIdRequest>(create);
  static MyFluxoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class MyEtapaFluxo extends $pb.GeneratedMessage {
  factory MyEtapaFluxo({
    $core.int? id,
    $core.int? fluxoId,
    $core.String? nome,
    $core.String? descricao,
    $core.int? ordem,
    $core.String? cor,
    $core.String? tipoEtapa,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (ordem != null) result.ordem = ordem;
    if (cor != null) result.cor = cor;
    if (tipoEtapa != null) result.tipoEtapa = tipoEtapa;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  MyEtapaFluxo._();

  factory MyEtapaFluxo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyEtapaFluxo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyEtapaFluxo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'fluxoId')
    ..aOS(3, _omitFieldNames ? '' : 'nome')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aI(5, _omitFieldNames ? '' : 'ordem')
    ..aOS(6, _omitFieldNames ? '' : 'cor')
    ..aOS(7, _omitFieldNames ? '' : 'tipoEtapa')
    ..aOB(8, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxo copyWith(void Function(MyEtapaFluxo) updates) =>
      super.copyWith((message) => updates(message as MyEtapaFluxo))
          as MyEtapaFluxo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxo create() => MyEtapaFluxo._();
  @$core.override
  MyEtapaFluxo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyEtapaFluxo>(create);
  static MyEtapaFluxo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get fluxoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set fluxoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFluxoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFluxoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get nome => $_getSZ(2);
  @$pb.TagNumber(3)
  set nome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNome() => $_has(2);
  @$pb.TagNumber(3)
  void clearNome() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get ordem => $_getIZ(4);
  @$pb.TagNumber(5)
  set ordem($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOrdem() => $_has(4);
  @$pb.TagNumber(5)
  void clearOrdem() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get cor => $_getSZ(5);
  @$pb.TagNumber(6)
  set cor($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCor() => $_has(5);
  @$pb.TagNumber(6)
  void clearCor() => $_clearField(6);

  /// Vocabulário fechado: fila, trabalho, espera, finalizacao. Não é enfeite —
  /// o roteamento procura `fila` para saber onde a conversa entra.
  @$pb.TagNumber(7)
  $core.String get tipoEtapa => $_getSZ(6);
  @$pb.TagNumber(7)
  set tipoEtapa($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTipoEtapa() => $_has(6);
  @$pb.TagNumber(7)
  void clearTipoEtapa() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get ativo => $_getBF(7);
  @$pb.TagNumber(8)
  set ativo($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAtivo() => $_has(7);
  @$pb.TagNumber(8)
  void clearAtivo() => $_clearField(8);
}

class ListMyEtapasFluxoResponse extends $pb.GeneratedMessage {
  factory ListMyEtapasFluxoResponse({
    $core.Iterable<MyEtapaFluxo>? etapas,
  }) {
    final result = create();
    if (etapas != null) result.etapas.addAll(etapas);
    return result;
  }

  ListMyEtapasFluxoResponse._();

  factory ListMyEtapasFluxoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyEtapasFluxoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyEtapasFluxoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyEtapaFluxo>(1, _omitFieldNames ? '' : 'etapas',
        subBuilder: MyEtapaFluxo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyEtapasFluxoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyEtapasFluxoResponse copyWith(
          void Function(ListMyEtapasFluxoResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyEtapasFluxoResponse))
          as ListMyEtapasFluxoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyEtapasFluxoResponse create() => ListMyEtapasFluxoResponse._();
  @$core.override
  ListMyEtapasFluxoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyEtapasFluxoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyEtapasFluxoResponse>(create);
  static ListMyEtapasFluxoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyEtapaFluxo> get etapas => $_getList(0);
}

class CreateMyEtapaFluxoRequest extends $pb.GeneratedMessage {
  factory CreateMyEtapaFluxoRequest({
    $core.int? fluxoId,
    $core.String? nome,
    $core.String? tipoEtapa,
    $core.String? cor,
  }) {
    final result = create();
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (nome != null) result.nome = nome;
    if (tipoEtapa != null) result.tipoEtapa = tipoEtapa;
    if (cor != null) result.cor = cor;
    return result;
  }

  CreateMyEtapaFluxoRequest._();

  factory CreateMyEtapaFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyEtapaFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyEtapaFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'fluxoId')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'tipoEtapa')
    ..aOS(4, _omitFieldNames ? '' : 'cor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyEtapaFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyEtapaFluxoRequest copyWith(
          void Function(CreateMyEtapaFluxoRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyEtapaFluxoRequest))
          as CreateMyEtapaFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyEtapaFluxoRequest create() => CreateMyEtapaFluxoRequest._();
  @$core.override
  CreateMyEtapaFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyEtapaFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyEtapaFluxoRequest>(create);
  static CreateMyEtapaFluxoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get fluxoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set fluxoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFluxoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFluxoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nome => $_getSZ(1);
  @$pb.TagNumber(2)
  set nome($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNome() => $_has(1);
  @$pb.TagNumber(2)
  void clearNome() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tipoEtapa => $_getSZ(2);
  @$pb.TagNumber(3)
  set tipoEtapa($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTipoEtapa() => $_has(2);
  @$pb.TagNumber(3)
  void clearTipoEtapa() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get cor => $_getSZ(3);
  @$pb.TagNumber(4)
  set cor($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCor() => $_has(3);
  @$pb.TagNumber(4)
  void clearCor() => $_clearField(4);
}

class MyEtapaFluxoResponse extends $pb.GeneratedMessage {
  factory MyEtapaFluxoResponse({
    MyEtapaFluxo? etapa,
  }) {
    final result = create();
    if (etapa != null) result.etapa = etapa;
    return result;
  }

  MyEtapaFluxoResponse._();

  factory MyEtapaFluxoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyEtapaFluxoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyEtapaFluxoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyEtapaFluxo>(1, _omitFieldNames ? '' : 'etapa',
        subBuilder: MyEtapaFluxo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxoResponse copyWith(void Function(MyEtapaFluxoResponse) updates) =>
      super.copyWith((message) => updates(message as MyEtapaFluxoResponse))
          as MyEtapaFluxoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxoResponse create() => MyEtapaFluxoResponse._();
  @$core.override
  MyEtapaFluxoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyEtapaFluxoResponse>(create);
  static MyEtapaFluxoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyEtapaFluxo get etapa => $_getN(0);
  @$pb.TagNumber(1)
  set etapa(MyEtapaFluxo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEtapa() => $_has(0);
  @$pb.TagNumber(1)
  void clearEtapa() => $_clearField(1);
  @$pb.TagNumber(1)
  MyEtapaFluxo ensureEtapa() => $_ensure(0);
}

class UpdateMyEtapaFluxoRequest extends $pb.GeneratedMessage {
  factory UpdateMyEtapaFluxoRequest({
    $core.int? id,
    $core.String? nome,
    $core.String? descricao,
    $core.String? cor,
    $core.String? tipoEtapa,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (cor != null) result.cor = cor;
    if (tipoEtapa != null) result.tipoEtapa = tipoEtapa;
    return result;
  }

  UpdateMyEtapaFluxoRequest._();

  factory UpdateMyEtapaFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyEtapaFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyEtapaFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOS(4, _omitFieldNames ? '' : 'cor')
    ..aOS(5, _omitFieldNames ? '' : 'tipoEtapa')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyEtapaFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyEtapaFluxoRequest copyWith(
          void Function(UpdateMyEtapaFluxoRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyEtapaFluxoRequest))
          as UpdateMyEtapaFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyEtapaFluxoRequest create() => UpdateMyEtapaFluxoRequest._();
  @$core.override
  UpdateMyEtapaFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyEtapaFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyEtapaFluxoRequest>(create);
  static UpdateMyEtapaFluxoRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get cor => $_getSZ(3);
  @$pb.TagNumber(4)
  set cor($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCor() => $_has(3);
  @$pb.TagNumber(4)
  void clearCor() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tipoEtapa => $_getSZ(4);
  @$pb.TagNumber(5)
  set tipoEtapa($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTipoEtapa() => $_has(4);
  @$pb.TagNumber(5)
  void clearTipoEtapa() => $_clearField(5);
}

class MyEtapaFluxoIdRequest extends $pb.GeneratedMessage {
  factory MyEtapaFluxoIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyEtapaFluxoIdRequest._();

  factory MyEtapaFluxoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyEtapaFluxoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyEtapaFluxoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyEtapaFluxoIdRequest copyWith(
          void Function(MyEtapaFluxoIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyEtapaFluxoIdRequest))
          as MyEtapaFluxoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxoIdRequest create() => MyEtapaFluxoIdRequest._();
  @$core.override
  MyEtapaFluxoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyEtapaFluxoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyEtapaFluxoIdRequest>(create);
  static MyEtapaFluxoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class MoverMyEtapaFluxoRequest extends $pb.GeneratedMessage {
  factory MoverMyEtapaFluxoRequest({
    $core.int? id,
    $core.bool? paraCima,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (paraCima != null) result.paraCima = paraCima;
    return result;
  }

  MoverMyEtapaFluxoRequest._();

  factory MoverMyEtapaFluxoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoverMyEtapaFluxoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoverMyEtapaFluxoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'paraCima')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoverMyEtapaFluxoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoverMyEtapaFluxoRequest copyWith(
          void Function(MoverMyEtapaFluxoRequest) updates) =>
      super.copyWith((message) => updates(message as MoverMyEtapaFluxoRequest))
          as MoverMyEtapaFluxoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoverMyEtapaFluxoRequest create() => MoverMyEtapaFluxoRequest._();
  @$core.override
  MoverMyEtapaFluxoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoverMyEtapaFluxoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoverMyEtapaFluxoRequest>(create);
  static MoverMyEtapaFluxoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get paraCima => $_getBF(1);
  @$pb.TagNumber(2)
  set paraCima($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParaCima() => $_has(1);
  @$pb.TagNumber(2)
  void clearParaCima() => $_clearField(2);
}

class MyContato extends $pb.GeneratedMessage {
  factory MyContato({
    $core.int? id,
    $core.String? telefone,
    $core.String? nomeContato,
    $core.String? nomePerfilWhatsapp,
    $core.String? email,
    $core.bool? ativo,
    $fixnum.Int64? ultimaInteracao,
    $fixnum.Int64? cadastradoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (telefone != null) result.telefone = telefone;
    if (nomeContato != null) result.nomeContato = nomeContato;
    if (nomePerfilWhatsapp != null)
      result.nomePerfilWhatsapp = nomePerfilWhatsapp;
    if (email != null) result.email = email;
    if (ativo != null) result.ativo = ativo;
    if (ultimaInteracao != null) result.ultimaInteracao = ultimaInteracao;
    if (cadastradoEm != null) result.cadastradoEm = cadastradoEm;
    return result;
  }

  MyContato._();

  factory MyContato.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyContato.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyContato',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'telefone')
    ..aOS(3, _omitFieldNames ? '' : 'nomeContato')
    ..aOS(4, _omitFieldNames ? '' : 'nomePerfilWhatsapp')
    ..aOS(5, _omitFieldNames ? '' : 'email')
    ..aOB(6, _omitFieldNames ? '' : 'ativo')
    ..aInt64(7, _omitFieldNames ? '' : 'ultimaInteracao')
    ..aInt64(8, _omitFieldNames ? '' : 'cadastradoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyContato clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyContato copyWith(void Function(MyContato) updates) =>
      super.copyWith((message) => updates(message as MyContato)) as MyContato;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyContato create() => MyContato._();
  @$core.override
  MyContato createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyContato getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MyContato>(create);
  static MyContato? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get telefone => $_getSZ(1);
  @$pb.TagNumber(2)
  set telefone($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTelefone() => $_has(1);
  @$pb.TagNumber(2)
  void clearTelefone() => $_clearField(2);

  /// Nome cadastrado. Vazio quando o contato só existe pelo WhatsApp.
  @$pb.TagNumber(3)
  $core.String get nomeContato => $_getSZ(2);
  @$pb.TagNumber(3)
  set nomeContato($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNomeContato() => $_has(2);
  @$pb.TagNumber(3)
  void clearNomeContato() => $_clearField(3);

  /// Como a pessoa se identifica no WhatsApp — muitas vezes é o único nome
  /// que se tem.
  @$pb.TagNumber(4)
  $core.String get nomePerfilWhatsapp => $_getSZ(3);
  @$pb.TagNumber(4)
  set nomePerfilWhatsapp($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNomePerfilWhatsapp() => $_has(3);
  @$pb.TagNumber(4)
  void clearNomePerfilWhatsapp() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get email => $_getSZ(4);
  @$pb.TagNumber(5)
  set email($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEmail() => $_has(4);
  @$pb.TagNumber(5)
  void clearEmail() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get ativo => $_getBF(5);
  @$pb.TagNumber(6)
  set ativo($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAtivo() => $_has(5);
  @$pb.TagNumber(6)
  void clearAtivo() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get ultimaInteracao => $_getI64(6);
  @$pb.TagNumber(7)
  set ultimaInteracao($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasUltimaInteracao() => $_has(6);
  @$pb.TagNumber(7)
  void clearUltimaInteracao() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get cadastradoEm => $_getI64(7);
  @$pb.TagNumber(8)
  set cadastradoEm($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCadastradoEm() => $_has(7);
  @$pb.TagNumber(8)
  void clearCadastradoEm() => $_clearField(8);
}

class OpcaoCampo extends $pb.GeneratedMessage {
  factory OpcaoCampo({
    $core.String? id,
    $core.String? rotulo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (rotulo != null) result.rotulo = rotulo;
    return result;
  }

  OpcaoCampo._();

  factory OpcaoCampo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OpcaoCampo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpcaoCampo',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'rotulo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpcaoCampo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpcaoCampo copyWith(void Function(OpcaoCampo) updates) =>
      super.copyWith((message) => updates(message as OpcaoCampo)) as OpcaoCampo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OpcaoCampo create() => OpcaoCampo._();
  @$core.override
  OpcaoCampo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OpcaoCampo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpcaoCampo>(create);
  static OpcaoCampo? _defaultInstance;

  /// Id estavel: e ele que fica gravado no valor. Renomear o rotulo depois nao
  /// pode invalidar o que ja foi preenchido.
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
}

class MyCampoPersonalizado extends $pb.GeneratedMessage {
  factory MyCampoPersonalizado({
    $fixnum.Int64? id,
    $core.String? slug,
    $core.String? nome,
    $core.String? descricao,
    $core.String? escopo,
    $core.int? fluxoId,
    $core.String? tipo,
    $core.Iterable<OpcaoCampo>? opcoes,
    $core.bool? obrigatorio,
    $core.bool? extrairAutomaticamente,
    $core.String? extrairHint,
    $core.bool? mostrarNoCard,
    $core.int? ordem,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (slug != null) result.slug = slug;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (escopo != null) result.escopo = escopo;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (tipo != null) result.tipo = tipo;
    if (opcoes != null) result.opcoes.addAll(opcoes);
    if (obrigatorio != null) result.obrigatorio = obrigatorio;
    if (extrairAutomaticamente != null)
      result.extrairAutomaticamente = extrairAutomaticamente;
    if (extrairHint != null) result.extrairHint = extrairHint;
    if (mostrarNoCard != null) result.mostrarNoCard = mostrarNoCard;
    if (ordem != null) result.ordem = ordem;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  MyCampoPersonalizado._();

  factory MyCampoPersonalizado.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyCampoPersonalizado.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyCampoPersonalizado',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'slug')
    ..aOS(3, _omitFieldNames ? '' : 'nome')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aOS(5, _omitFieldNames ? '' : 'escopo')
    ..aI(6, _omitFieldNames ? '' : 'fluxoId')
    ..aOS(7, _omitFieldNames ? '' : 'tipo')
    ..pPM<OpcaoCampo>(8, _omitFieldNames ? '' : 'opcoes',
        subBuilder: OpcaoCampo.create)
    ..aOB(9, _omitFieldNames ? '' : 'obrigatorio')
    ..aOB(10, _omitFieldNames ? '' : 'extrairAutomaticamente')
    ..aOS(11, _omitFieldNames ? '' : 'extrairHint')
    ..aOB(12, _omitFieldNames ? '' : 'mostrarNoCard')
    ..aI(13, _omitFieldNames ? '' : 'ordem')
    ..aOB(14, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoPersonalizado clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoPersonalizado copyWith(void Function(MyCampoPersonalizado) updates) =>
      super.copyWith((message) => updates(message as MyCampoPersonalizado))
          as MyCampoPersonalizado;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyCampoPersonalizado create() => MyCampoPersonalizado._();
  @$core.override
  MyCampoPersonalizado createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyCampoPersonalizado getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyCampoPersonalizado>(create);
  static MyCampoPersonalizado? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get slug => $_getSZ(1);
  @$pb.TagNumber(2)
  set slug($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSlug() => $_has(1);
  @$pb.TagNumber(2)
  void clearSlug() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get nome => $_getSZ(2);
  @$pb.TagNumber(3)
  set nome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNome() => $_has(2);
  @$pb.TagNumber(3)
  void clearNome() => $_clearField(3);

  /// Serve a duas leituras: explica o campo para quem preenche a mao e diz a
  /// IA o que procurar. E a "descricao completa" do pedido original.
  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  /// GLOBAL (todo atendimento) ou FLUXO (so o quadro escolhido).
  @$pb.TagNumber(5)
  $core.String get escopo => $_getSZ(4);
  @$pb.TagNumber(5)
  set escopo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEscopo() => $_has(4);
  @$pb.TagNumber(5)
  void clearEscopo() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get fluxoId => $_getIZ(5);
  @$pb.TagNumber(6)
  set fluxoId($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFluxoId() => $_has(5);
  @$pb.TagNumber(6)
  void clearFluxoId() => $_clearField(6);

  /// texto | numero | data | booleano | lista
  @$pb.TagNumber(7)
  $core.String get tipo => $_getSZ(6);
  @$pb.TagNumber(7)
  set tipo($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTipo() => $_has(6);
  @$pb.TagNumber(7)
  void clearTipo() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<OpcaoCampo> get opcoes => $_getList(7);

  /// Regra de TELA: impede concluir o atendimento sem o campo.
  @$pb.TagNumber(9)
  $core.bool get obrigatorio => $_getBF(8);
  @$pb.TagNumber(9)
  set obrigatorio($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasObrigatorio() => $_has(8);
  @$pb.TagNumber(9)
  void clearObrigatorio() => $_clearField(9);

  /// Regra de PROMPT: a IA tenta obter no meio da conversa. Sao coisas
  /// diferentes, e trata-las como uma so foi um defeito real (C2).
  @$pb.TagNumber(10)
  $core.bool get extrairAutomaticamente => $_getBF(9);
  @$pb.TagNumber(10)
  set extrairAutomaticamente($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasExtrairAutomaticamente() => $_has(9);
  @$pb.TagNumber(10)
  void clearExtrairAutomaticamente() => $_clearField(10);

  /// Como perguntar sem soar interrogatorio.
  @$pb.TagNumber(11)
  $core.String get extrairHint => $_getSZ(10);
  @$pb.TagNumber(11)
  set extrairHint($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasExtrairHint() => $_has(10);
  @$pb.TagNumber(11)
  void clearExtrairHint() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get mostrarNoCard => $_getBF(11);
  @$pb.TagNumber(12)
  set mostrarNoCard($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMostrarNoCard() => $_has(11);
  @$pb.TagNumber(12)
  void clearMostrarNoCard() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get ordem => $_getIZ(12);
  @$pb.TagNumber(13)
  set ordem($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasOrdem() => $_has(12);
  @$pb.TagNumber(13)
  void clearOrdem() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get ativo => $_getBF(13);
  @$pb.TagNumber(14)
  set ativo($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasAtivo() => $_has(13);
  @$pb.TagNumber(14)
  void clearAtivo() => $_clearField(14);
}

class ListMyCamposRequest extends $pb.GeneratedMessage {
  factory ListMyCamposRequest({
    $core.int? fluxoId,
  }) {
    final result = create();
    if (fluxoId != null) result.fluxoId = fluxoId;
    return result;
  }

  ListMyCamposRequest._();

  factory ListMyCamposRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyCamposRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyCamposRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'fluxoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyCamposRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyCamposRequest copyWith(void Function(ListMyCamposRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyCamposRequest))
          as ListMyCamposRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyCamposRequest create() => ListMyCamposRequest._();
  @$core.override
  ListMyCamposRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyCamposRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyCamposRequest>(create);
  static ListMyCamposRequest? _defaultInstance;

  /// Vazio = todos. Com fluxo, devolve os GLOBAL mais os daquele quadro.
  @$pb.TagNumber(1)
  $core.int get fluxoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set fluxoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFluxoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFluxoId() => $_clearField(1);
}

class ListMyCamposResponse extends $pb.GeneratedMessage {
  factory ListMyCamposResponse({
    $core.Iterable<MyCampoPersonalizado>? campos,
  }) {
    final result = create();
    if (campos != null) result.campos.addAll(campos);
    return result;
  }

  ListMyCamposResponse._();

  factory ListMyCamposResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyCamposResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyCamposResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyCampoPersonalizado>(1, _omitFieldNames ? '' : 'campos',
        subBuilder: MyCampoPersonalizado.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyCamposResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyCamposResponse copyWith(void Function(ListMyCamposResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyCamposResponse))
          as ListMyCamposResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyCamposResponse create() => ListMyCamposResponse._();
  @$core.override
  ListMyCamposResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyCamposResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyCamposResponse>(create);
  static ListMyCamposResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyCampoPersonalizado> get campos => $_getList(0);
}

class CreateMyCampoRequest extends $pb.GeneratedMessage {
  factory CreateMyCampoRequest({
    $core.String? nome,
    $core.String? descricao,
    $core.String? escopo,
    $core.int? fluxoId,
    $core.String? tipo,
    $core.Iterable<OpcaoCampo>? opcoes,
    $core.bool? obrigatorio,
    $core.bool? extrairAutomaticamente,
    $core.String? extrairHint,
    $core.bool? mostrarNoCard,
    $core.int? ordem,
  }) {
    final result = create();
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (escopo != null) result.escopo = escopo;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (tipo != null) result.tipo = tipo;
    if (opcoes != null) result.opcoes.addAll(opcoes);
    if (obrigatorio != null) result.obrigatorio = obrigatorio;
    if (extrairAutomaticamente != null)
      result.extrairAutomaticamente = extrairAutomaticamente;
    if (extrairHint != null) result.extrairHint = extrairHint;
    if (mostrarNoCard != null) result.mostrarNoCard = mostrarNoCard;
    if (ordem != null) result.ordem = ordem;
    return result;
  }

  CreateMyCampoRequest._();

  factory CreateMyCampoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyCampoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyCampoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nome')
    ..aOS(2, _omitFieldNames ? '' : 'descricao')
    ..aOS(3, _omitFieldNames ? '' : 'escopo')
    ..aI(4, _omitFieldNames ? '' : 'fluxoId')
    ..aOS(5, _omitFieldNames ? '' : 'tipo')
    ..pPM<OpcaoCampo>(6, _omitFieldNames ? '' : 'opcoes',
        subBuilder: OpcaoCampo.create)
    ..aOB(7, _omitFieldNames ? '' : 'obrigatorio')
    ..aOB(8, _omitFieldNames ? '' : 'extrairAutomaticamente')
    ..aOS(9, _omitFieldNames ? '' : 'extrairHint')
    ..aOB(10, _omitFieldNames ? '' : 'mostrarNoCard')
    ..aI(11, _omitFieldNames ? '' : 'ordem')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyCampoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyCampoRequest copyWith(void Function(CreateMyCampoRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyCampoRequest))
          as CreateMyCampoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyCampoRequest create() => CreateMyCampoRequest._();
  @$core.override
  CreateMyCampoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyCampoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyCampoRequest>(create);
  static CreateMyCampoRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get escopo => $_getSZ(2);
  @$pb.TagNumber(3)
  set escopo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEscopo() => $_has(2);
  @$pb.TagNumber(3)
  void clearEscopo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get fluxoId => $_getIZ(3);
  @$pb.TagNumber(4)
  set fluxoId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFluxoId() => $_has(3);
  @$pb.TagNumber(4)
  void clearFluxoId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tipo => $_getSZ(4);
  @$pb.TagNumber(5)
  set tipo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTipo() => $_has(4);
  @$pb.TagNumber(5)
  void clearTipo() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<OpcaoCampo> get opcoes => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get obrigatorio => $_getBF(6);
  @$pb.TagNumber(7)
  set obrigatorio($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasObrigatorio() => $_has(6);
  @$pb.TagNumber(7)
  void clearObrigatorio() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get extrairAutomaticamente => $_getBF(7);
  @$pb.TagNumber(8)
  set extrairAutomaticamente($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExtrairAutomaticamente() => $_has(7);
  @$pb.TagNumber(8)
  void clearExtrairAutomaticamente() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get extrairHint => $_getSZ(8);
  @$pb.TagNumber(9)
  set extrairHint($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasExtrairHint() => $_has(8);
  @$pb.TagNumber(9)
  void clearExtrairHint() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get mostrarNoCard => $_getBF(9);
  @$pb.TagNumber(10)
  set mostrarNoCard($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMostrarNoCard() => $_has(9);
  @$pb.TagNumber(10)
  void clearMostrarNoCard() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get ordem => $_getIZ(10);
  @$pb.TagNumber(11)
  set ordem($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasOrdem() => $_has(10);
  @$pb.TagNumber(11)
  void clearOrdem() => $_clearField(11);
}

class MyCampoResponse extends $pb.GeneratedMessage {
  factory MyCampoResponse({
    MyCampoPersonalizado? campo,
  }) {
    final result = create();
    if (campo != null) result.campo = campo;
    return result;
  }

  MyCampoResponse._();

  factory MyCampoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyCampoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyCampoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyCampoPersonalizado>(1, _omitFieldNames ? '' : 'campo',
        subBuilder: MyCampoPersonalizado.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoResponse copyWith(void Function(MyCampoResponse) updates) =>
      super.copyWith((message) => updates(message as MyCampoResponse))
          as MyCampoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyCampoResponse create() => MyCampoResponse._();
  @$core.override
  MyCampoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyCampoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyCampoResponse>(create);
  static MyCampoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyCampoPersonalizado get campo => $_getN(0);
  @$pb.TagNumber(1)
  set campo(MyCampoPersonalizado value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCampo() => $_has(0);
  @$pb.TagNumber(1)
  void clearCampo() => $_clearField(1);
  @$pb.TagNumber(1)
  MyCampoPersonalizado ensureCampo() => $_ensure(0);
}

class UpdateMyCampoRequest extends $pb.GeneratedMessage {
  factory UpdateMyCampoRequest({
    $fixnum.Int64? id,
    $core.String? nome,
    $core.String? descricao,
    $core.String? tipo,
    $core.Iterable<OpcaoCampo>? opcoes,
    $core.bool? obrigatorio,
    $core.bool? extrairAutomaticamente,
    $core.String? extrairHint,
    $core.bool? mostrarNoCard,
    $core.int? ordem,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (tipo != null) result.tipo = tipo;
    if (opcoes != null) result.opcoes.addAll(opcoes);
    if (obrigatorio != null) result.obrigatorio = obrigatorio;
    if (extrairAutomaticamente != null)
      result.extrairAutomaticamente = extrairAutomaticamente;
    if (extrairHint != null) result.extrairHint = extrairHint;
    if (mostrarNoCard != null) result.mostrarNoCard = mostrarNoCard;
    if (ordem != null) result.ordem = ordem;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  UpdateMyCampoRequest._();

  factory UpdateMyCampoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyCampoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyCampoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOS(4, _omitFieldNames ? '' : 'tipo')
    ..pPM<OpcaoCampo>(5, _omitFieldNames ? '' : 'opcoes',
        subBuilder: OpcaoCampo.create)
    ..aOB(6, _omitFieldNames ? '' : 'obrigatorio')
    ..aOB(7, _omitFieldNames ? '' : 'extrairAutomaticamente')
    ..aOS(8, _omitFieldNames ? '' : 'extrairHint')
    ..aOB(9, _omitFieldNames ? '' : 'mostrarNoCard')
    ..aI(10, _omitFieldNames ? '' : 'ordem')
    ..aOB(11, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyCampoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyCampoRequest copyWith(void Function(UpdateMyCampoRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyCampoRequest))
          as UpdateMyCampoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyCampoRequest create() => UpdateMyCampoRequest._();
  @$core.override
  UpdateMyCampoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyCampoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyCampoRequest>(create);
  static UpdateMyCampoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
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

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get tipo => $_getSZ(3);
  @$pb.TagNumber(4)
  set tipo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTipo() => $_has(3);
  @$pb.TagNumber(4)
  void clearTipo() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<OpcaoCampo> get opcoes => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get obrigatorio => $_getBF(5);
  @$pb.TagNumber(6)
  set obrigatorio($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasObrigatorio() => $_has(5);
  @$pb.TagNumber(6)
  void clearObrigatorio() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get extrairAutomaticamente => $_getBF(6);
  @$pb.TagNumber(7)
  set extrairAutomaticamente($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExtrairAutomaticamente() => $_has(6);
  @$pb.TagNumber(7)
  void clearExtrairAutomaticamente() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get extrairHint => $_getSZ(7);
  @$pb.TagNumber(8)
  set extrairHint($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExtrairHint() => $_has(7);
  @$pb.TagNumber(8)
  void clearExtrairHint() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get mostrarNoCard => $_getBF(8);
  @$pb.TagNumber(9)
  set mostrarNoCard($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasMostrarNoCard() => $_has(8);
  @$pb.TagNumber(9)
  void clearMostrarNoCard() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get ordem => $_getIZ(9);
  @$pb.TagNumber(10)
  set ordem($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasOrdem() => $_has(9);
  @$pb.TagNumber(10)
  void clearOrdem() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get ativo => $_getBF(10);
  @$pb.TagNumber(11)
  set ativo($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasAtivo() => $_has(10);
  @$pb.TagNumber(11)
  void clearAtivo() => $_clearField(11);
}

class MyCampoIdRequest extends $pb.GeneratedMessage {
  factory MyCampoIdRequest({
    $fixnum.Int64? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyCampoIdRequest._();

  factory MyCampoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyCampoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyCampoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCampoIdRequest copyWith(void Function(MyCampoIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyCampoIdRequest))
          as MyCampoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyCampoIdRequest create() => MyCampoIdRequest._();
  @$core.override
  MyCampoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyCampoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyCampoIdRequest>(create);
  static MyCampoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

/// Preenchimento manual, pelo operador. A origem fica registrada: um valor
/// escrito por gente nao pode ser sobrescrito pela IA depois.
class SetMyValorCampoRequest extends $pb.GeneratedMessage {
  factory SetMyValorCampoRequest({
    $core.int? atendimentoId,
    $fixnum.Int64? campoId,
    $core.String? valorJson,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (campoId != null) result.campoId = campoId;
    if (valorJson != null) result.valorJson = valorJson;
    return result;
  }

  SetMyValorCampoRequest._();

  factory SetMyValorCampoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetMyValorCampoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMyValorCampoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aInt64(2, _omitFieldNames ? '' : 'campoId')
    ..aOS(3, _omitFieldNames ? '' : 'valorJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyValorCampoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMyValorCampoRequest copyWith(
          void Function(SetMyValorCampoRequest) updates) =>
      super.copyWith((message) => updates(message as SetMyValorCampoRequest))
          as SetMyValorCampoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetMyValorCampoRequest create() => SetMyValorCampoRequest._();
  @$core.override
  SetMyValorCampoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetMyValorCampoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMyValorCampoRequest>(create);
  static SetMyValorCampoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get campoId => $_getI64(1);
  @$pb.TagNumber(2)
  set campoId($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCampoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCampoId() => $_clearField(2);

  /// JSON na forma do `tipo`. `null` = apagar de proposito, que e diferente de
  /// nunca ter sido preenchido: a IA nao repreenche o que alguem apagou.
  @$pb.TagNumber(3)
  $core.String get valorJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set valorJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValorJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearValorJson() => $_clearField(3);
}

class ListMyContatosRequest extends $pb.GeneratedMessage {
  factory ListMyContatosRequest({
    $core.String? busca,
    $core.int? limite,
  }) {
    final result = create();
    if (busca != null) result.busca = busca;
    if (limite != null) result.limite = limite;
    return result;
  }

  ListMyContatosRequest._();

  factory ListMyContatosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyContatosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyContatosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'busca')
    ..aI(2, _omitFieldNames ? '' : 'limite')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosRequest copyWith(
          void Function(ListMyContatosRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyContatosRequest))
          as ListMyContatosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyContatosRequest create() => ListMyContatosRequest._();
  @$core.override
  ListMyContatosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyContatosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyContatosRequest>(create);
  static ListMyContatosRequest? _defaultInstance;

  /// Casa contra nome, telefone e nome do perfil. Vazio = sem filtro.
  @$pb.TagNumber(1)
  $core.String get busca => $_getSZ(0);
  @$pb.TagNumber(1)
  set busca($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBusca() => $_has(0);
  @$pb.TagNumber(1)
  void clearBusca() => $_clearField(1);

  /// 0 = padrão do servidor (50). Teto de 200.
  @$pb.TagNumber(2)
  $core.int get limite => $_getIZ(1);
  @$pb.TagNumber(2)
  set limite($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimite() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimite() => $_clearField(2);
}

class ListMyContatosResponse extends $pb.GeneratedMessage {
  factory ListMyContatosResponse({
    $core.Iterable<MyContato>? contatos,
  }) {
    final result = create();
    if (contatos != null) result.contatos.addAll(contatos);
    return result;
  }

  ListMyContatosResponse._();

  factory ListMyContatosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyContatosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyContatosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyContato>(1, _omitFieldNames ? '' : 'contatos',
        subBuilder: MyContato.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosResponse copyWith(
          void Function(ListMyContatosResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyContatosResponse))
          as ListMyContatosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyContatosResponse create() => ListMyContatosResponse._();
  @$core.override
  ListMyContatosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyContatosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyContatosResponse>(create);
  static ListMyContatosResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyContato> get contatos => $_getList(0);
}

class CreateMyContatoRequest extends $pb.GeneratedMessage {
  factory CreateMyContatoRequest({
    $core.String? telefone,
    $core.String? nomeContato,
    $core.String? email,
  }) {
    final result = create();
    if (telefone != null) result.telefone = telefone;
    if (nomeContato != null) result.nomeContato = nomeContato;
    if (email != null) result.email = email;
    return result;
  }

  CreateMyContatoRequest._();

  factory CreateMyContatoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyContatoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyContatoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'telefone')
    ..aOS(2, _omitFieldNames ? '' : 'nomeContato')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyContatoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyContatoRequest copyWith(
          void Function(CreateMyContatoRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyContatoRequest))
          as CreateMyContatoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyContatoRequest create() => CreateMyContatoRequest._();
  @$core.override
  CreateMyContatoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyContatoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyContatoRequest>(create);
  static CreateMyContatoRequest? _defaultInstance;

  /// Como a pessoa digitou. O servidor normaliza para o mesmo formato que a
  /// ingestao grava (so digitos, com DDI) — sem isso o contato cadastrado a
  /// mao e o mesmo numero que chega pelo WhatsApp virariam duas pessoas.
  @$pb.TagNumber(1)
  $core.String get telefone => $_getSZ(0);
  @$pb.TagNumber(1)
  set telefone($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTelefone() => $_has(0);
  @$pb.TagNumber(1)
  void clearTelefone() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nomeContato => $_getSZ(1);
  @$pb.TagNumber(2)
  set nomeContato($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNomeContato() => $_has(1);
  @$pb.TagNumber(2)
  void clearNomeContato() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);
}

class MyContatoResponse extends $pb.GeneratedMessage {
  factory MyContatoResponse({
    MyContato? contato,
  }) {
    final result = create();
    if (contato != null) result.contato = contato;
    return result;
  }

  MyContatoResponse._();

  factory MyContatoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyContatoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyContatoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyContato>(1, _omitFieldNames ? '' : 'contato',
        subBuilder: MyContato.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyContatoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyContatoResponse copyWith(void Function(MyContatoResponse) updates) =>
      super.copyWith((message) => updates(message as MyContatoResponse))
          as MyContatoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyContatoResponse create() => MyContatoResponse._();
  @$core.override
  MyContatoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyContatoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyContatoResponse>(create);
  static MyContatoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyContato get contato => $_getN(0);
  @$pb.TagNumber(1)
  set contato(MyContato value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasContato() => $_has(0);
  @$pb.TagNumber(1)
  void clearContato() => $_clearField(1);
  @$pb.TagNumber(1)
  MyContato ensureContato() => $_ensure(0);
}

class UpdateMyContatoRequest extends $pb.GeneratedMessage {
  factory UpdateMyContatoRequest({
    $core.int? id,
    $core.String? nomeContato,
    $core.String? email,
    $core.String? telefone,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nomeContato != null) result.nomeContato = nomeContato;
    if (email != null) result.email = email;
    if (telefone != null) result.telefone = telefone;
    return result;
  }

  UpdateMyContatoRequest._();

  factory UpdateMyContatoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyContatoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyContatoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nomeContato')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'telefone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyContatoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyContatoRequest copyWith(
          void Function(UpdateMyContatoRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyContatoRequest))
          as UpdateMyContatoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyContatoRequest create() => UpdateMyContatoRequest._();
  @$core.override
  UpdateMyContatoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyContatoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyContatoRequest>(create);
  static UpdateMyContatoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get nomeContato => $_getSZ(1);
  @$pb.TagNumber(2)
  set nomeContato($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNomeContato() => $_has(1);
  @$pb.TagNumber(2)
  void clearNomeContato() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  /// Vazio = nao mexe. So e aceito enquanto o contato nao tem conversa: o
  /// historico esta amarrado ao numero, e troca-lo passaria as mensagens de
  /// uma pessoa para outra.
  @$pb.TagNumber(4)
  $core.String get telefone => $_getSZ(3);
  @$pb.TagNumber(4)
  set telefone($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTelefone() => $_has(3);
  @$pb.TagNumber(4)
  void clearTelefone() => $_clearField(4);
}

class DefinirMyContatoAtivoRequest extends $pb.GeneratedMessage {
  factory DefinirMyContatoAtivoRequest({
    $core.int? id,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  DefinirMyContatoAtivoRequest._();

  factory DefinirMyContatoAtivoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirMyContatoAtivoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirMyContatoAtivoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirMyContatoAtivoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirMyContatoAtivoRequest copyWith(
          void Function(DefinirMyContatoAtivoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as DefinirMyContatoAtivoRequest))
          as DefinirMyContatoAtivoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirMyContatoAtivoRequest create() =>
      DefinirMyContatoAtivoRequest._();
  @$core.override
  DefinirMyContatoAtivoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirMyContatoAtivoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirMyContatoAtivoRequest>(create);
  static DefinirMyContatoAtivoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get ativo => $_getBF(1);
  @$pb.TagNumber(2)
  set ativo($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtivo() => $_clearField(2);
}

/// --- B10 (N11 E5): clientes (PJ/PF) ---
/// CNPJ/CPF e endereco sao dado protegido: nunca em log.
class DadosMyCliente extends $pb.GeneratedMessage {
  factory DadosMyCliente({
    $core.String? nomeFantasia,
    $core.String? razaoSocial,
    $core.String? tipo,
    $core.String? cnpj,
    $core.String? cpf,
    $core.String? telefone,
    $core.String? site,
    $core.String? ramoAtividade,
    $core.String? observacoes,
    $core.String? cep,
    $core.String? logradouro,
    $core.String? numero,
    $core.String? complemento,
    $core.String? bairro,
    $core.String? cidade,
    $core.String? uf,
  }) {
    final result = create();
    if (nomeFantasia != null) result.nomeFantasia = nomeFantasia;
    if (razaoSocial != null) result.razaoSocial = razaoSocial;
    if (tipo != null) result.tipo = tipo;
    if (cnpj != null) result.cnpj = cnpj;
    if (cpf != null) result.cpf = cpf;
    if (telefone != null) result.telefone = telefone;
    if (site != null) result.site = site;
    if (ramoAtividade != null) result.ramoAtividade = ramoAtividade;
    if (observacoes != null) result.observacoes = observacoes;
    if (cep != null) result.cep = cep;
    if (logradouro != null) result.logradouro = logradouro;
    if (numero != null) result.numero = numero;
    if (complemento != null) result.complemento = complemento;
    if (bairro != null) result.bairro = bairro;
    if (cidade != null) result.cidade = cidade;
    if (uf != null) result.uf = uf;
    return result;
  }

  DadosMyCliente._();

  factory DadosMyCliente.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DadosMyCliente.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DadosMyCliente',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nomeFantasia')
    ..aOS(2, _omitFieldNames ? '' : 'razaoSocial')
    ..aOS(3, _omitFieldNames ? '' : 'tipo')
    ..aOS(4, _omitFieldNames ? '' : 'cnpj')
    ..aOS(5, _omitFieldNames ? '' : 'cpf')
    ..aOS(6, _omitFieldNames ? '' : 'telefone')
    ..aOS(7, _omitFieldNames ? '' : 'site')
    ..aOS(8, _omitFieldNames ? '' : 'ramoAtividade')
    ..aOS(9, _omitFieldNames ? '' : 'observacoes')
    ..aOS(10, _omitFieldNames ? '' : 'cep')
    ..aOS(11, _omitFieldNames ? '' : 'logradouro')
    ..aOS(12, _omitFieldNames ? '' : 'numero')
    ..aOS(13, _omitFieldNames ? '' : 'complemento')
    ..aOS(14, _omitFieldNames ? '' : 'bairro')
    ..aOS(15, _omitFieldNames ? '' : 'cidade')
    ..aOS(16, _omitFieldNames ? '' : 'uf')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DadosMyCliente clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DadosMyCliente copyWith(void Function(DadosMyCliente) updates) =>
      super.copyWith((message) => updates(message as DadosMyCliente))
          as DadosMyCliente;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DadosMyCliente create() => DadosMyCliente._();
  @$core.override
  DadosMyCliente createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DadosMyCliente getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DadosMyCliente>(create);
  static DadosMyCliente? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nomeFantasia => $_getSZ(0);
  @$pb.TagNumber(1)
  set nomeFantasia($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNomeFantasia() => $_has(0);
  @$pb.TagNumber(1)
  void clearNomeFantasia() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get razaoSocial => $_getSZ(1);
  @$pb.TagNumber(2)
  set razaoSocial($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRazaoSocial() => $_has(1);
  @$pb.TagNumber(2)
  void clearRazaoSocial() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get tipo => $_getSZ(2);
  @$pb.TagNumber(3)
  set tipo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTipo() => $_has(2);
  @$pb.TagNumber(3)
  void clearTipo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get cnpj => $_getSZ(3);
  @$pb.TagNumber(4)
  set cnpj($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCnpj() => $_has(3);
  @$pb.TagNumber(4)
  void clearCnpj() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get cpf => $_getSZ(4);
  @$pb.TagNumber(5)
  set cpf($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCpf() => $_has(4);
  @$pb.TagNumber(5)
  void clearCpf() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get telefone => $_getSZ(5);
  @$pb.TagNumber(6)
  set telefone($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTelefone() => $_has(5);
  @$pb.TagNumber(6)
  void clearTelefone() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get site => $_getSZ(6);
  @$pb.TagNumber(7)
  set site($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSite() => $_has(6);
  @$pb.TagNumber(7)
  void clearSite() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get ramoAtividade => $_getSZ(7);
  @$pb.TagNumber(8)
  set ramoAtividade($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRamoAtividade() => $_has(7);
  @$pb.TagNumber(8)
  void clearRamoAtividade() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get observacoes => $_getSZ(8);
  @$pb.TagNumber(9)
  set observacoes($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasObservacoes() => $_has(8);
  @$pb.TagNumber(9)
  void clearObservacoes() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get cep => $_getSZ(9);
  @$pb.TagNumber(10)
  set cep($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCep() => $_has(9);
  @$pb.TagNumber(10)
  void clearCep() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get logradouro => $_getSZ(10);
  @$pb.TagNumber(11)
  set logradouro($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLogradouro() => $_has(10);
  @$pb.TagNumber(11)
  void clearLogradouro() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get numero => $_getSZ(11);
  @$pb.TagNumber(12)
  set numero($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasNumero() => $_has(11);
  @$pb.TagNumber(12)
  void clearNumero() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get complemento => $_getSZ(12);
  @$pb.TagNumber(13)
  set complemento($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasComplemento() => $_has(12);
  @$pb.TagNumber(13)
  void clearComplemento() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get bairro => $_getSZ(13);
  @$pb.TagNumber(14)
  set bairro($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasBairro() => $_has(13);
  @$pb.TagNumber(14)
  void clearBairro() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get cidade => $_getSZ(14);
  @$pb.TagNumber(15)
  set cidade($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasCidade() => $_has(14);
  @$pb.TagNumber(15)
  void clearCidade() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get uf => $_getSZ(15);
  @$pb.TagNumber(16)
  set uf($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasUf() => $_has(15);
  @$pb.TagNumber(16)
  void clearUf() => $_clearField(16);
}

class MyCliente extends $pb.GeneratedMessage {
  factory MyCliente({
    $core.int? id,
    DadosMyCliente? dados,
    $core.bool? ativo,
    $core.int? contatos,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (dados != null) result.dados = dados;
    if (ativo != null) result.ativo = ativo;
    if (contatos != null) result.contatos = contatos;
    return result;
  }

  MyCliente._();

  factory MyCliente.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyCliente.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyCliente',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOM<DadosMyCliente>(2, _omitFieldNames ? '' : 'dados',
        subBuilder: DadosMyCliente.create)
    ..aOB(3, _omitFieldNames ? '' : 'ativo')
    ..aI(4, _omitFieldNames ? '' : 'contatos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCliente clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyCliente copyWith(void Function(MyCliente) updates) =>
      super.copyWith((message) => updates(message as MyCliente)) as MyCliente;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyCliente create() => MyCliente._();
  @$core.override
  MyCliente createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyCliente getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MyCliente>(create);
  static MyCliente? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  DadosMyCliente get dados => $_getN(1);
  @$pb.TagNumber(2)
  set dados(DadosMyCliente value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDados() => $_has(1);
  @$pb.TagNumber(2)
  void clearDados() => $_clearField(2);
  @$pb.TagNumber(2)
  DadosMyCliente ensureDados() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get ativo => $_getBF(2);
  @$pb.TagNumber(3)
  set ativo($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAtivo() => $_has(2);
  @$pb.TagNumber(3)
  void clearAtivo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get contatos => $_getIZ(3);
  @$pb.TagNumber(4)
  set contatos($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContatos() => $_has(3);
  @$pb.TagNumber(4)
  void clearContatos() => $_clearField(4);
}

class ListMyClientesRequest extends $pb.GeneratedMessage {
  factory ListMyClientesRequest({
    $core.String? busca,
    $core.bool? incluirInativos,
    $core.int? limite,
  }) {
    final result = create();
    if (busca != null) result.busca = busca;
    if (incluirInativos != null) result.incluirInativos = incluirInativos;
    if (limite != null) result.limite = limite;
    return result;
  }

  ListMyClientesRequest._();

  factory ListMyClientesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyClientesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyClientesRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'busca')
    ..aOB(2, _omitFieldNames ? '' : 'incluirInativos')
    ..aI(3, _omitFieldNames ? '' : 'limite')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyClientesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyClientesRequest copyWith(
          void Function(ListMyClientesRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyClientesRequest))
          as ListMyClientesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyClientesRequest create() => ListMyClientesRequest._();
  @$core.override
  ListMyClientesRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyClientesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyClientesRequest>(create);
  static ListMyClientesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get busca => $_getSZ(0);
  @$pb.TagNumber(1)
  set busca($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBusca() => $_has(0);
  @$pb.TagNumber(1)
  void clearBusca() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get incluirInativos => $_getBF(1);
  @$pb.TagNumber(2)
  set incluirInativos($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncluirInativos() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncluirInativos() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get limite => $_getIZ(2);
  @$pb.TagNumber(3)
  set limite($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLimite() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimite() => $_clearField(3);
}

class ListMyClientesResponse extends $pb.GeneratedMessage {
  factory ListMyClientesResponse({
    $core.Iterable<MyCliente>? clientes,
  }) {
    final result = create();
    if (clientes != null) result.clientes.addAll(clientes);
    return result;
  }

  ListMyClientesResponse._();

  factory ListMyClientesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyClientesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyClientesResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyCliente>(1, _omitFieldNames ? '' : 'clientes',
        subBuilder: MyCliente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyClientesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyClientesResponse copyWith(
          void Function(ListMyClientesResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyClientesResponse))
          as ListMyClientesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyClientesResponse create() => ListMyClientesResponse._();
  @$core.override
  ListMyClientesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyClientesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyClientesResponse>(create);
  static ListMyClientesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyCliente> get clientes => $_getList(0);
}

class CreateMyClienteRequest extends $pb.GeneratedMessage {
  factory CreateMyClienteRequest({
    DadosMyCliente? dados,
  }) {
    final result = create();
    if (dados != null) result.dados = dados;
    return result;
  }

  CreateMyClienteRequest._();

  factory CreateMyClienteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyClienteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyClienteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<DadosMyCliente>(1, _omitFieldNames ? '' : 'dados',
        subBuilder: DadosMyCliente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyClienteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyClienteRequest copyWith(
          void Function(CreateMyClienteRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyClienteRequest))
          as CreateMyClienteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyClienteRequest create() => CreateMyClienteRequest._();
  @$core.override
  CreateMyClienteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyClienteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyClienteRequest>(create);
  static CreateMyClienteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DadosMyCliente get dados => $_getN(0);
  @$pb.TagNumber(1)
  set dados(DadosMyCliente value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasDados() => $_has(0);
  @$pb.TagNumber(1)
  void clearDados() => $_clearField(1);
  @$pb.TagNumber(1)
  DadosMyCliente ensureDados() => $_ensure(0);
}

class MyClienteResponse extends $pb.GeneratedMessage {
  factory MyClienteResponse({
    MyCliente? cliente,
  }) {
    final result = create();
    if (cliente != null) result.cliente = cliente;
    return result;
  }

  MyClienteResponse._();

  factory MyClienteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyClienteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyClienteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyCliente>(1, _omitFieldNames ? '' : 'cliente',
        subBuilder: MyCliente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyClienteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyClienteResponse copyWith(void Function(MyClienteResponse) updates) =>
      super.copyWith((message) => updates(message as MyClienteResponse))
          as MyClienteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyClienteResponse create() => MyClienteResponse._();
  @$core.override
  MyClienteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyClienteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyClienteResponse>(create);
  static MyClienteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyCliente get cliente => $_getN(0);
  @$pb.TagNumber(1)
  set cliente(MyCliente value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCliente() => $_has(0);
  @$pb.TagNumber(1)
  void clearCliente() => $_clearField(1);
  @$pb.TagNumber(1)
  MyCliente ensureCliente() => $_ensure(0);
}

class UpdateMyClienteRequest extends $pb.GeneratedMessage {
  factory UpdateMyClienteRequest({
    $core.int? id,
    DadosMyCliente? dados,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (dados != null) result.dados = dados;
    return result;
  }

  UpdateMyClienteRequest._();

  factory UpdateMyClienteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyClienteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyClienteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOM<DadosMyCliente>(2, _omitFieldNames ? '' : 'dados',
        subBuilder: DadosMyCliente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyClienteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyClienteRequest copyWith(
          void Function(UpdateMyClienteRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyClienteRequest))
          as UpdateMyClienteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyClienteRequest create() => UpdateMyClienteRequest._();
  @$core.override
  UpdateMyClienteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyClienteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyClienteRequest>(create);
  static UpdateMyClienteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  DadosMyCliente get dados => $_getN(1);
  @$pb.TagNumber(2)
  set dados(DadosMyCliente value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDados() => $_has(1);
  @$pb.TagNumber(2)
  void clearDados() => $_clearField(2);
  @$pb.TagNumber(2)
  DadosMyCliente ensureDados() => $_ensure(1);
}

class DefinirMyClienteAtivoRequest extends $pb.GeneratedMessage {
  factory DefinirMyClienteAtivoRequest({
    $core.int? id,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  DefinirMyClienteAtivoRequest._();

  factory DefinirMyClienteAtivoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirMyClienteAtivoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirMyClienteAtivoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirMyClienteAtivoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirMyClienteAtivoRequest copyWith(
          void Function(DefinirMyClienteAtivoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as DefinirMyClienteAtivoRequest))
          as DefinirMyClienteAtivoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirMyClienteAtivoRequest create() =>
      DefinirMyClienteAtivoRequest._();
  @$core.override
  DefinirMyClienteAtivoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirMyClienteAtivoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirMyClienteAtivoRequest>(create);
  static DefinirMyClienteAtivoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get ativo => $_getBF(1);
  @$pb.TagNumber(2)
  set ativo($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtivo() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtivo() => $_clearField(2);
}

class MyClienteIdRequest extends $pb.GeneratedMessage {
  factory MyClienteIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyClienteIdRequest._();

  factory MyClienteIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyClienteIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyClienteIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyClienteIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyClienteIdRequest copyWith(void Function(MyClienteIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyClienteIdRequest))
          as MyClienteIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyClienteIdRequest create() => MyClienteIdRequest._();
  @$core.override
  MyClienteIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyClienteIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyClienteIdRequest>(create);
  static MyClienteIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class ContatoDoCliente extends $pb.GeneratedMessage {
  factory ContatoDoCliente({
    $core.int? id,
    $core.String? nome,
    $core.String? telefone,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (telefone != null) result.telefone = telefone;
    return result;
  }

  ContatoDoCliente._();

  factory ContatoDoCliente.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ContatoDoCliente.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ContatoDoCliente',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'telefone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContatoDoCliente clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ContatoDoCliente copyWith(void Function(ContatoDoCliente) updates) =>
      super.copyWith((message) => updates(message as ContatoDoCliente))
          as ContatoDoCliente;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContatoDoCliente create() => ContatoDoCliente._();
  @$core.override
  ContatoDoCliente createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ContatoDoCliente getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ContatoDoCliente>(create);
  static ContatoDoCliente? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get telefone => $_getSZ(2);
  @$pb.TagNumber(3)
  set telefone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTelefone() => $_has(2);
  @$pb.TagNumber(3)
  void clearTelefone() => $_clearField(3);
}

class ListMyContatosDoClienteResponse extends $pb.GeneratedMessage {
  factory ListMyContatosDoClienteResponse({
    $core.Iterable<ContatoDoCliente>? contatos,
  }) {
    final result = create();
    if (contatos != null) result.contatos.addAll(contatos);
    return result;
  }

  ListMyContatosDoClienteResponse._();

  factory ListMyContatosDoClienteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyContatosDoClienteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyContatosDoClienteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<ContatoDoCliente>(1, _omitFieldNames ? '' : 'contatos',
        subBuilder: ContatoDoCliente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosDoClienteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyContatosDoClienteResponse copyWith(
          void Function(ListMyContatosDoClienteResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyContatosDoClienteResponse))
          as ListMyContatosDoClienteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyContatosDoClienteResponse create() =>
      ListMyContatosDoClienteResponse._();
  @$core.override
  ListMyContatosDoClienteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyContatosDoClienteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyContatosDoClienteResponse>(
          create);
  static ListMyContatosDoClienteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ContatoDoCliente> get contatos => $_getList(0);
}

class VincularMyContatoClienteRequest extends $pb.GeneratedMessage {
  factory VincularMyContatoClienteRequest({
    $core.int? clienteId,
    $core.int? contatoId,
    $core.bool? vincular,
  }) {
    final result = create();
    if (clienteId != null) result.clienteId = clienteId;
    if (contatoId != null) result.contatoId = contatoId;
    if (vincular != null) result.vincular = vincular;
    return result;
  }

  VincularMyContatoClienteRequest._();

  factory VincularMyContatoClienteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VincularMyContatoClienteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VincularMyContatoClienteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'clienteId')
    ..aI(2, _omitFieldNames ? '' : 'contatoId')
    ..aOB(3, _omitFieldNames ? '' : 'vincular')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VincularMyContatoClienteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VincularMyContatoClienteRequest copyWith(
          void Function(VincularMyContatoClienteRequest) updates) =>
      super.copyWith(
              (message) => updates(message as VincularMyContatoClienteRequest))
          as VincularMyContatoClienteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VincularMyContatoClienteRequest create() =>
      VincularMyContatoClienteRequest._();
  @$core.override
  VincularMyContatoClienteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VincularMyContatoClienteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VincularMyContatoClienteRequest>(
          create);
  static VincularMyContatoClienteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get clienteId => $_getIZ(0);
  @$pb.TagNumber(1)
  set clienteId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClienteId() => $_has(0);
  @$pb.TagNumber(1)
  void clearClienteId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get contatoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set contatoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContatoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearContatoId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get vincular => $_getBF(2);
  @$pb.TagNumber(3)
  set vincular($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVincular() => $_has(2);
  @$pb.TagNumber(3)
  void clearVincular() => $_clearField(3);
}

class GetMyPainelRequest extends $pb.GeneratedMessage {
  factory GetMyPainelRequest() => create();

  GetMyPainelRequest._();

  factory GetMyPainelRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyPainelRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyPainelRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyPainelRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyPainelRequest copyWith(void Function(GetMyPainelRequest) updates) =>
      super.copyWith((message) => updates(message as GetMyPainelRequest))
          as GetMyPainelRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyPainelRequest create() => GetMyPainelRequest._();
  @$core.override
  GetMyPainelRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyPainelRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyPainelRequest>(create);
  static GetMyPainelRequest? _defaultInstance;
}

class GetMyPainelResponse extends $pb.GeneratedMessage {
  factory GetMyPainelResponse({
    $core.int? emAndamento,
    $core.int? aguardando,
    $core.int? mensagens24h,
    $core.int? conexoesAtivas,
    $core.int? conexoesTotal,
    $core.int? departamentos,
    $core.int? treinamentosAtivos,
    $core.int? primeiraRespostaMedianaS,
  }) {
    final result = create();
    if (emAndamento != null) result.emAndamento = emAndamento;
    if (aguardando != null) result.aguardando = aguardando;
    if (mensagens24h != null) result.mensagens24h = mensagens24h;
    if (conexoesAtivas != null) result.conexoesAtivas = conexoesAtivas;
    if (conexoesTotal != null) result.conexoesTotal = conexoesTotal;
    if (departamentos != null) result.departamentos = departamentos;
    if (treinamentosAtivos != null)
      result.treinamentosAtivos = treinamentosAtivos;
    if (primeiraRespostaMedianaS != null)
      result.primeiraRespostaMedianaS = primeiraRespostaMedianaS;
    return result;
  }

  GetMyPainelResponse._();

  factory GetMyPainelResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyPainelResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyPainelResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'emAndamento')
    ..aI(2, _omitFieldNames ? '' : 'aguardando')
    ..aI(3, _omitFieldNames ? '' : 'mensagens24h', protoName: 'mensagens_24h')
    ..aI(4, _omitFieldNames ? '' : 'conexoesAtivas')
    ..aI(5, _omitFieldNames ? '' : 'conexoesTotal')
    ..aI(6, _omitFieldNames ? '' : 'departamentos')
    ..aI(7, _omitFieldNames ? '' : 'treinamentosAtivos')
    ..aI(8, _omitFieldNames ? '' : 'primeiraRespostaMedianaS')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyPainelResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyPainelResponse copyWith(void Function(GetMyPainelResponse) updates) =>
      super.copyWith((message) => updates(message as GetMyPainelResponse))
          as GetMyPainelResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyPainelResponse create() => GetMyPainelResponse._();
  @$core.override
  GetMyPainelResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyPainelResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyPainelResponse>(create);
  static GetMyPainelResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get emAndamento => $_getIZ(0);
  @$pb.TagNumber(1)
  set emAndamento($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmAndamento() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmAndamento() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get aguardando => $_getIZ(1);
  @$pb.TagNumber(2)
  set aguardando($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAguardando() => $_has(1);
  @$pb.TagNumber(2)
  void clearAguardando() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get mensagens24h => $_getIZ(2);
  @$pb.TagNumber(3)
  set mensagens24h($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMensagens24h() => $_has(2);
  @$pb.TagNumber(3)
  void clearMensagens24h() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get conexoesAtivas => $_getIZ(3);
  @$pb.TagNumber(4)
  set conexoesAtivas($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConexoesAtivas() => $_has(3);
  @$pb.TagNumber(4)
  void clearConexoesAtivas() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get conexoesTotal => $_getIZ(4);
  @$pb.TagNumber(5)
  set conexoesTotal($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasConexoesTotal() => $_has(4);
  @$pb.TagNumber(5)
  void clearConexoesTotal() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get departamentos => $_getIZ(5);
  @$pb.TagNumber(6)
  set departamentos($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDepartamentos() => $_has(5);
  @$pb.TagNumber(6)
  void clearDepartamentos() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get treinamentosAtivos => $_getIZ(6);
  @$pb.TagNumber(7)
  set treinamentosAtivos($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTreinamentosAtivos() => $_has(6);
  @$pb.TagNumber(7)
  void clearTreinamentosAtivos() => $_clearField(7);

  /// P6 — mediana do tempo ate a primeira resposta nas ultimas 24h, em
  /// segundos. -1 = ninguem foi respondido ainda nessa janela (diferente de
  /// "respondido em zero segundo").
  @$pb.TagNumber(8)
  $core.int get primeiraRespostaMedianaS => $_getIZ(7);
  @$pb.TagNumber(8)
  set primeiraRespostaMedianaS($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPrimeiraRespostaMedianaS() => $_has(7);
  @$pb.TagNumber(8)
  void clearPrimeiraRespostaMedianaS() => $_clearField(8);
}

class MyDepartamento extends $pb.GeneratedMessage {
  factory MyDepartamento({
    $core.int? id,
    $core.String? nome,
    $core.String? slug,
    $core.String? descricao,
    $core.bool? ativo,
    $fixnum.Int64? criadoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (slug != null) result.slug = slug;
    if (descricao != null) result.descricao = descricao;
    if (ativo != null) result.ativo = ativo;
    if (criadoEm != null) result.criadoEm = criadoEm;
    return result;
  }

  MyDepartamento._();

  factory MyDepartamento.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyDepartamento.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyDepartamento',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'slug')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aOB(5, _omitFieldNames ? '' : 'ativo')
    ..aInt64(6, _omitFieldNames ? '' : 'criadoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyDepartamento clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyDepartamento copyWith(void Function(MyDepartamento) updates) =>
      super.copyWith((message) => updates(message as MyDepartamento))
          as MyDepartamento;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyDepartamento create() => MyDepartamento._();
  @$core.override
  MyDepartamento createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyDepartamento getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyDepartamento>(create);
  static MyDepartamento? _defaultInstance;

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

  /// Referência estável: NÃO muda ao renomear, porque há registros que apontam
  /// para o departamento por ele.
  @$pb.TagNumber(3)
  $core.String get slug => $_getSZ(2);
  @$pb.TagNumber(3)
  set slug($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSlug() => $_has(2);
  @$pb.TagNumber(3)
  void clearSlug() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get ativo => $_getBF(4);
  @$pb.TagNumber(5)
  set ativo($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAtivo() => $_has(4);
  @$pb.TagNumber(5)
  void clearAtivo() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get criadoEm => $_getI64(5);
  @$pb.TagNumber(6)
  set criadoEm($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCriadoEm() => $_has(5);
  @$pb.TagNumber(6)
  void clearCriadoEm() => $_clearField(6);
}

class ListMyDepartamentosRequest extends $pb.GeneratedMessage {
  factory ListMyDepartamentosRequest() => create();

  ListMyDepartamentosRequest._();

  factory ListMyDepartamentosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyDepartamentosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyDepartamentosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyDepartamentosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyDepartamentosRequest copyWith(
          void Function(ListMyDepartamentosRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyDepartamentosRequest))
          as ListMyDepartamentosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyDepartamentosRequest create() => ListMyDepartamentosRequest._();
  @$core.override
  ListMyDepartamentosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyDepartamentosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyDepartamentosRequest>(create);
  static ListMyDepartamentosRequest? _defaultInstance;
}

class ListMyDepartamentosResponse extends $pb.GeneratedMessage {
  factory ListMyDepartamentosResponse({
    $core.Iterable<MyDepartamento>? departamentos,
  }) {
    final result = create();
    if (departamentos != null) result.departamentos.addAll(departamentos);
    return result;
  }

  ListMyDepartamentosResponse._();

  factory ListMyDepartamentosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyDepartamentosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyDepartamentosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyDepartamento>(1, _omitFieldNames ? '' : 'departamentos',
        subBuilder: MyDepartamento.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyDepartamentosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyDepartamentosResponse copyWith(
          void Function(ListMyDepartamentosResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyDepartamentosResponse))
          as ListMyDepartamentosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyDepartamentosResponse create() =>
      ListMyDepartamentosResponse._();
  @$core.override
  ListMyDepartamentosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyDepartamentosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyDepartamentosResponse>(create);
  static ListMyDepartamentosResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyDepartamento> get departamentos => $_getList(0);
}

class UpdateMyDepartamentoRequest extends $pb.GeneratedMessage {
  factory UpdateMyDepartamentoRequest({
    $core.int? id,
    $core.String? nome,
    $core.String? descricao,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  UpdateMyDepartamentoRequest._();

  factory UpdateMyDepartamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyDepartamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyDepartamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOB(4, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyDepartamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyDepartamentoRequest copyWith(
          void Function(UpdateMyDepartamentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateMyDepartamentoRequest))
          as UpdateMyDepartamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyDepartamentoRequest create() =>
      UpdateMyDepartamentoRequest._();
  @$core.override
  UpdateMyDepartamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyDepartamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyDepartamentoRequest>(create);
  static UpdateMyDepartamentoRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get ativo => $_getBF(3);
  @$pb.TagNumber(4)
  set ativo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtivo() => $_clearField(4);
}

class MyDepartamentoIdRequest extends $pb.GeneratedMessage {
  factory MyDepartamentoIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyDepartamentoIdRequest._();

  factory MyDepartamentoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyDepartamentoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyDepartamentoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyDepartamentoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyDepartamentoIdRequest copyWith(
          void Function(MyDepartamentoIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyDepartamentoIdRequest))
          as MyDepartamentoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyDepartamentoIdRequest create() => MyDepartamentoIdRequest._();
  @$core.override
  MyDepartamentoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyDepartamentoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyDepartamentoIdRequest>(create);
  static MyDepartamentoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class MyAtendente extends $pb.GeneratedMessage {
  factory MyAtendente({
    $core.int? id,
    $core.String? nome,
    $core.String? email,
    $core.String? cargo,
    $core.int? departamentoId,
    $core.bool? ativo,
    $core.bool? disponivel,
    $core.int? maxAtendimentosSimultaneos,
    $core.int? fluxoId,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (email != null) result.email = email;
    if (cargo != null) result.cargo = cargo;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (ativo != null) result.ativo = ativo;
    if (disponivel != null) result.disponivel = disponivel;
    if (maxAtendimentosSimultaneos != null)
      result.maxAtendimentosSimultaneos = maxAtendimentosSimultaneos;
    if (fluxoId != null) result.fluxoId = fluxoId;
    return result;
  }

  MyAtendente._();

  factory MyAtendente.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyAtendente.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyAtendente',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'email')
    ..aOS(4, _omitFieldNames ? '' : 'cargo')
    ..aI(5, _omitFieldNames ? '' : 'departamentoId')
    ..aOB(6, _omitFieldNames ? '' : 'ativo')
    ..aOB(7, _omitFieldNames ? '' : 'disponivel')
    ..aI(8, _omitFieldNames ? '' : 'maxAtendimentosSimultaneos')
    ..aI(9, _omitFieldNames ? '' : 'fluxoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendente clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendente copyWith(void Function(MyAtendente) updates) =>
      super.copyWith((message) => updates(message as MyAtendente))
          as MyAtendente;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyAtendente create() => MyAtendente._();
  @$core.override
  MyAtendente createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyAtendente getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyAtendente>(create);
  static MyAtendente? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get email => $_getSZ(2);
  @$pb.TagNumber(3)
  set email($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmail() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmail() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get cargo => $_getSZ(3);
  @$pb.TagNumber(4)
  set cargo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCargo() => $_has(3);
  @$pb.TagNumber(4)
  void clearCargo() => $_clearField(4);

  /// 0 = sem departamento.
  @$pb.TagNumber(5)
  $core.int get departamentoId => $_getIZ(4);
  @$pb.TagNumber(5)
  set departamentoId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDepartamentoId() => $_has(4);
  @$pb.TagNumber(5)
  void clearDepartamentoId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get ativo => $_getBF(5);
  @$pb.TagNumber(6)
  set ativo($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAtivo() => $_has(5);
  @$pb.TagNumber(6)
  void clearAtivo() => $_clearField(6);

  /// Aceitando conversa agora — diferente de `ativo`, que é o cadastro.
  @$pb.TagNumber(7)
  $core.bool get disponivel => $_getBF(6);
  @$pb.TagNumber(7)
  set disponivel($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDisponivel() => $_has(6);
  @$pb.TagNumber(7)
  void clearDisponivel() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxAtendimentosSimultaneos => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxAtendimentosSimultaneos($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxAtendimentosSimultaneos() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxAtendimentosSimultaneos() => $_clearField(8);

  /// O quadro em que trabalha. Sem ele a edição não teria o que preencher no
  /// seletor de fluxo, e salvar reatribuiria a pessoa por acidente.
  @$pb.TagNumber(9)
  $core.int get fluxoId => $_getIZ(8);
  @$pb.TagNumber(9)
  set fluxoId($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasFluxoId() => $_has(8);
  @$pb.TagNumber(9)
  void clearFluxoId() => $_clearField(9);
}

class ListMyAtendentesRequest extends $pb.GeneratedMessage {
  factory ListMyAtendentesRequest() => create();

  ListMyAtendentesRequest._();

  factory ListMyAtendentesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyAtendentesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyAtendentesRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAtendentesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAtendentesRequest copyWith(
          void Function(ListMyAtendentesRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyAtendentesRequest))
          as ListMyAtendentesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyAtendentesRequest create() => ListMyAtendentesRequest._();
  @$core.override
  ListMyAtendentesRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyAtendentesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyAtendentesRequest>(create);
  static ListMyAtendentesRequest? _defaultInstance;
}

class ListMyAtendentesResponse extends $pb.GeneratedMessage {
  factory ListMyAtendentesResponse({
    $core.Iterable<MyAtendente>? atendentes,
  }) {
    final result = create();
    if (atendentes != null) result.atendentes.addAll(atendentes);
    return result;
  }

  ListMyAtendentesResponse._();

  factory ListMyAtendentesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyAtendentesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyAtendentesResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyAtendente>(1, _omitFieldNames ? '' : 'atendentes',
        subBuilder: MyAtendente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAtendentesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyAtendentesResponse copyWith(
          void Function(ListMyAtendentesResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyAtendentesResponse))
          as ListMyAtendentesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyAtendentesResponse create() => ListMyAtendentesResponse._();
  @$core.override
  ListMyAtendentesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyAtendentesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyAtendentesResponse>(create);
  static ListMyAtendentesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyAtendente> get atendentes => $_getList(0);
}

class CreateMyAtendenteRequest extends $pb.GeneratedMessage {
  factory CreateMyAtendenteRequest({
    $core.String? nome,
    $core.String? email,
    $core.String? cargo,
    $core.int? fluxoId,
    $core.int? departamentoId,
  }) {
    final result = create();
    if (nome != null) result.nome = nome;
    if (email != null) result.email = email;
    if (cargo != null) result.cargo = cargo;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (departamentoId != null) result.departamentoId = departamentoId;
    return result;
  }

  CreateMyAtendenteRequest._();

  factory CreateMyAtendenteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyAtendenteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyAtendenteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nome')
    ..aOS(2, _omitFieldNames ? '' : 'email')
    ..aOS(3, _omitFieldNames ? '' : 'cargo')
    ..aI(4, _omitFieldNames ? '' : 'fluxoId')
    ..aI(5, _omitFieldNames ? '' : 'departamentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyAtendenteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyAtendenteRequest copyWith(
          void Function(CreateMyAtendenteRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMyAtendenteRequest))
          as CreateMyAtendenteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyAtendenteRequest create() => CreateMyAtendenteRequest._();
  @$core.override
  CreateMyAtendenteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyAtendenteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyAtendenteRequest>(create);
  static CreateMyAtendenteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nome => $_getSZ(0);
  @$pb.TagNumber(1)
  set nome($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNome() => $_has(0);
  @$pb.TagNumber(1)
  void clearNome() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get email => $_getSZ(1);
  @$pb.TagNumber(2)
  set email($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmail() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmail() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get cargo => $_getSZ(2);
  @$pb.TagNumber(3)
  set cargo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCargo() => $_has(2);
  @$pb.TagNumber(3)
  void clearCargo() => $_clearField(3);

  /// Obrigatório: é o quadro em que a pessoa trabalha, e a coluna é NOT NULL.
  @$pb.TagNumber(4)
  $core.int get fluxoId => $_getIZ(3);
  @$pb.TagNumber(4)
  set fluxoId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFluxoId() => $_has(3);
  @$pb.TagNumber(4)
  void clearFluxoId() => $_clearField(4);

  /// 0 = sem departamento.
  @$pb.TagNumber(5)
  $core.int get departamentoId => $_getIZ(4);
  @$pb.TagNumber(5)
  set departamentoId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDepartamentoId() => $_has(4);
  @$pb.TagNumber(5)
  void clearDepartamentoId() => $_clearField(5);
}

class MyAtendenteResponse extends $pb.GeneratedMessage {
  factory MyAtendenteResponse({
    MyAtendente? atendente,
  }) {
    final result = create();
    if (atendente != null) result.atendente = atendente;
    return result;
  }

  MyAtendenteResponse._();

  factory MyAtendenteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyAtendenteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyAtendenteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyAtendente>(1, _omitFieldNames ? '' : 'atendente',
        subBuilder: MyAtendente.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendenteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendenteResponse copyWith(void Function(MyAtendenteResponse) updates) =>
      super.copyWith((message) => updates(message as MyAtendenteResponse))
          as MyAtendenteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyAtendenteResponse create() => MyAtendenteResponse._();
  @$core.override
  MyAtendenteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyAtendenteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyAtendenteResponse>(create);
  static MyAtendenteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyAtendente get atendente => $_getN(0);
  @$pb.TagNumber(1)
  set atendente(MyAtendente value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendente() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendente() => $_clearField(1);
  @$pb.TagNumber(1)
  MyAtendente ensureAtendente() => $_ensure(0);
}

class UpdateMyAtendenteRequest extends $pb.GeneratedMessage {
  factory UpdateMyAtendenteRequest({
    $core.int? id,
    $core.String? nome,
    $core.String? cargo,
    $core.int? departamentoId,
    $core.int? fluxoId,
    $core.bool? ativo,
    $core.bool? disponivel,
    $core.int? maxAtendimentosSimultaneos,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (cargo != null) result.cargo = cargo;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (fluxoId != null) result.fluxoId = fluxoId;
    if (ativo != null) result.ativo = ativo;
    if (disponivel != null) result.disponivel = disponivel;
    if (maxAtendimentosSimultaneos != null)
      result.maxAtendimentosSimultaneos = maxAtendimentosSimultaneos;
    return result;
  }

  UpdateMyAtendenteRequest._();

  factory UpdateMyAtendenteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyAtendenteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyAtendenteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'cargo')
    ..aI(4, _omitFieldNames ? '' : 'departamentoId')
    ..aI(5, _omitFieldNames ? '' : 'fluxoId')
    ..aOB(6, _omitFieldNames ? '' : 'ativo')
    ..aOB(7, _omitFieldNames ? '' : 'disponivel')
    ..aI(8, _omitFieldNames ? '' : 'maxAtendimentosSimultaneos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyAtendenteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyAtendenteRequest copyWith(
          void Function(UpdateMyAtendenteRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyAtendenteRequest))
          as UpdateMyAtendenteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyAtendenteRequest create() => UpdateMyAtendenteRequest._();
  @$core.override
  UpdateMyAtendenteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyAtendenteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyAtendenteRequest>(create);
  static UpdateMyAtendenteRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get cargo => $_getSZ(2);
  @$pb.TagNumber(3)
  set cargo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCargo() => $_has(2);
  @$pb.TagNumber(3)
  void clearCargo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get departamentoId => $_getIZ(3);
  @$pb.TagNumber(4)
  set departamentoId($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDepartamentoId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDepartamentoId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get fluxoId => $_getIZ(4);
  @$pb.TagNumber(5)
  set fluxoId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFluxoId() => $_has(4);
  @$pb.TagNumber(5)
  void clearFluxoId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get ativo => $_getBF(5);
  @$pb.TagNumber(6)
  set ativo($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAtivo() => $_has(5);
  @$pb.TagNumber(6)
  void clearAtivo() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get disponivel => $_getBF(6);
  @$pb.TagNumber(7)
  set disponivel($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDisponivel() => $_has(6);
  @$pb.TagNumber(7)
  void clearDisponivel() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get maxAtendimentosSimultaneos => $_getIZ(7);
  @$pb.TagNumber(8)
  set maxAtendimentosSimultaneos($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMaxAtendimentosSimultaneos() => $_has(7);
  @$pb.TagNumber(8)
  void clearMaxAtendimentosSimultaneos() => $_clearField(8);
}

class MyAtendenteIdRequest extends $pb.GeneratedMessage {
  factory MyAtendenteIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyAtendenteIdRequest._();

  factory MyAtendenteIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyAtendenteIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyAtendenteIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendenteIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyAtendenteIdRequest copyWith(void Function(MyAtendenteIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyAtendenteIdRequest))
          as MyAtendenteIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyAtendenteIdRequest create() => MyAtendenteIdRequest._();
  @$core.override
  MyAtendenteIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyAtendenteIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyAtendenteIdRequest>(create);
  static MyAtendenteIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class MyWhatsappInstance extends $pb.GeneratedMessage {
  factory MyWhatsappInstance({
    $core.int? id,
    $core.String? name,
    $core.String? phoneNumber,
    $core.String? connectionState,
    $core.bool? active,
    $core.String? provider,
    $fixnum.Int64? createdAt,
    $core.bool? respostaBot,
    $core.int? departamentoId,
    $core.String? departamentoNome,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (phoneNumber != null) result.phoneNumber = phoneNumber;
    if (connectionState != null) result.connectionState = connectionState;
    if (active != null) result.active = active;
    if (provider != null) result.provider = provider;
    if (createdAt != null) result.createdAt = createdAt;
    if (respostaBot != null) result.respostaBot = respostaBot;
    if (departamentoId != null) result.departamentoId = departamentoId;
    if (departamentoNome != null) result.departamentoNome = departamentoNome;
    return result;
  }

  MyWhatsappInstance._();

  factory MyWhatsappInstance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyWhatsappInstance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyWhatsappInstance',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'phoneNumber')
    ..aOS(4, _omitFieldNames ? '' : 'connectionState')
    ..aOB(5, _omitFieldNames ? '' : 'active')
    ..aOS(6, _omitFieldNames ? '' : 'provider')
    ..aInt64(7, _omitFieldNames ? '' : 'createdAt')
    ..aOB(8, _omitFieldNames ? '' : 'respostaBot')
    ..aI(9, _omitFieldNames ? '' : 'departamentoId')
    ..aOS(10, _omitFieldNames ? '' : 'departamentoNome')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyWhatsappInstance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyWhatsappInstance copyWith(void Function(MyWhatsappInstance) updates) =>
      super.copyWith((message) => updates(message as MyWhatsappInstance))
          as MyWhatsappInstance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyWhatsappInstance create() => MyWhatsappInstance._();
  @$core.override
  MyWhatsappInstance createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyWhatsappInstance getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyWhatsappInstance>(create);
  static MyWhatsappInstance? _defaultInstance;

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

  /// Número pareado; vazio enquanto o QR não foi lido.
  @$pb.TagNumber(3)
  $core.String get phoneNumber => $_getSZ(2);
  @$pb.TagNumber(3)
  set phoneNumber($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPhoneNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhoneNumber() => $_clearField(3);

  /// Vocabulário de `whatsapp_instance.connection_state`: connected,
  /// connecting, disconnected, unknown.
  @$pb.TagNumber(4)
  $core.String get connectionState => $_getSZ(3);
  @$pb.TagNumber(4)
  set connectionState($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConnectionState() => $_has(3);
  @$pb.TagNumber(4)
  void clearConnectionState() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get active => $_getBF(4);
  @$pb.TagNumber(5)
  set active($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasActive() => $_has(4);
  @$pb.TagNumber(5)
  void clearActive() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get provider => $_getSZ(5);
  @$pb.TagNumber(6)
  set provider($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProvider() => $_has(5);
  @$pb.TagNumber(6)
  void clearProvider() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAt => $_getI64(6);
  @$pb.TagNumber(7)
  set createdAt($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAt() => $_clearField(7);

  /// D3 — quando false, a IA nao responde NENHUMA conversa desta conexao.
  /// Aditivo: cliente antigo o le como `false` por omissao, mas nunca o mostra,
  /// entao segue no comportamento de hoje.
  @$pb.TagNumber(8)
  $core.bool get respostaBot => $_getBF(7);
  @$pb.TagNumber(8)
  set respostaBot($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRespostaBot() => $_has(7);
  @$pb.TagNumber(8)
  void clearRespostaBot() => $_clearField(8);

  /// P7 — a v1 roteava por número: a conversa que chega nesta conexão entra no
  /// fluxo do departamento dela. 0 = sem departamento, e o roteamento cai no
  /// primeiro fluxo ativo do tenant, como era até aqui.
  @$pb.TagNumber(9)
  $core.int get departamentoId => $_getIZ(8);
  @$pb.TagNumber(9)
  set departamentoId($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDepartamentoId() => $_has(8);
  @$pb.TagNumber(9)
  void clearDepartamentoId() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get departamentoNome => $_getSZ(9);
  @$pb.TagNumber(10)
  set departamentoNome($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDepartamentoNome() => $_has(9);
  @$pb.TagNumber(10)
  void clearDepartamentoNome() => $_clearField(10);
}

/// D3 — liga/desliga a resposta automatica da IA para a conexao inteira.
///
/// Equivale ao `instances/<pk>/toggle-bot/` da v1. O `tenant_id` vem das claims:
/// ninguem cala o bot da conexao de outro tenant mandando o id na mensagem.
class DefinirRespostaBotInstanciaRequest extends $pb.GeneratedMessage {
  factory DefinirRespostaBotInstanciaRequest({
    $core.int? id,
    $core.bool? habilitado,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (habilitado != null) result.habilitado = habilitado;
    return result;
  }

  DefinirRespostaBotInstanciaRequest._();

  factory DefinirRespostaBotInstanciaRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirRespostaBotInstanciaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirRespostaBotInstanciaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOB(2, _omitFieldNames ? '' : 'habilitado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirRespostaBotInstanciaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirRespostaBotInstanciaRequest copyWith(
          void Function(DefinirRespostaBotInstanciaRequest) updates) =>
      super.copyWith((message) =>
              updates(message as DefinirRespostaBotInstanciaRequest))
          as DefinirRespostaBotInstanciaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirRespostaBotInstanciaRequest create() =>
      DefinirRespostaBotInstanciaRequest._();
  @$core.override
  DefinirRespostaBotInstanciaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirRespostaBotInstanciaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirRespostaBotInstanciaRequest>(
          create);
  static DefinirRespostaBotInstanciaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Sem default no servidor: "nao mandou" e erro de contrato, nao "desligue".
  @$pb.TagNumber(2)
  $core.bool get habilitado => $_getBF(1);
  @$pb.TagNumber(2)
  set habilitado($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHabilitado() => $_has(1);
  @$pb.TagNumber(2)
  void clearHabilitado() => $_clearField(2);
}

class DefinirRespostaBotInstanciaResponse extends $pb.GeneratedMessage {
  factory DefinirRespostaBotInstanciaResponse({
    $core.bool? habilitado,
  }) {
    final result = create();
    if (habilitado != null) result.habilitado = habilitado;
    return result;
  }

  DefinirRespostaBotInstanciaResponse._();

  factory DefinirRespostaBotInstanciaResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirRespostaBotInstanciaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirRespostaBotInstanciaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'habilitado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirRespostaBotInstanciaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirRespostaBotInstanciaResponse copyWith(
          void Function(DefinirRespostaBotInstanciaResponse) updates) =>
      super.copyWith((message) =>
              updates(message as DefinirRespostaBotInstanciaResponse))
          as DefinirRespostaBotInstanciaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirRespostaBotInstanciaResponse create() =>
      DefinirRespostaBotInstanciaResponse._();
  @$core.override
  DefinirRespostaBotInstanciaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirRespostaBotInstanciaResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          DefinirRespostaBotInstanciaResponse>(create);
  static DefinirRespostaBotInstanciaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get habilitado => $_getBF(0);
  @$pb.TagNumber(1)
  set habilitado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHabilitado() => $_has(0);
  @$pb.TagNumber(1)
  void clearHabilitado() => $_clearField(1);
}

/// D3 — liga/desliga a IA nesta conversa.
///
/// O caminho de volta que faltava: assumir o atendimento desliga o bot, e nada
/// devolvia o valor. Uma conversa que passou por um humano ficava sem bot para
/// sempre.
class DefinirBotDaConversaRequest extends $pb.GeneratedMessage {
  factory DefinirBotDaConversaRequest({
    $core.int? atendimentoId,
    $core.bool? habilitado,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (habilitado != null) result.habilitado = habilitado;
    return result;
  }

  DefinirBotDaConversaRequest._();

  factory DefinirBotDaConversaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirBotDaConversaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirBotDaConversaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOB(2, _omitFieldNames ? '' : 'habilitado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirBotDaConversaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirBotDaConversaRequest copyWith(
          void Function(DefinirBotDaConversaRequest) updates) =>
      super.copyWith(
              (message) => updates(message as DefinirBotDaConversaRequest))
          as DefinirBotDaConversaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirBotDaConversaRequest create() =>
      DefinirBotDaConversaRequest._();
  @$core.override
  DefinirBotDaConversaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirBotDaConversaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirBotDaConversaRequest>(create);
  static DefinirBotDaConversaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get habilitado => $_getBF(1);
  @$pb.TagNumber(2)
  set habilitado($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHabilitado() => $_has(1);
  @$pb.TagNumber(2)
  void clearHabilitado() => $_clearField(2);
}

class DefinirBotDaConversaResponse extends $pb.GeneratedMessage {
  factory DefinirBotDaConversaResponse({
    $core.bool? habilitado,
  }) {
    final result = create();
    if (habilitado != null) result.habilitado = habilitado;
    return result;
  }

  DefinirBotDaConversaResponse._();

  factory DefinirBotDaConversaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirBotDaConversaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirBotDaConversaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'habilitado')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirBotDaConversaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirBotDaConversaResponse copyWith(
          void Function(DefinirBotDaConversaResponse) updates) =>
      super.copyWith(
              (message) => updates(message as DefinirBotDaConversaResponse))
          as DefinirBotDaConversaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirBotDaConversaResponse create() =>
      DefinirBotDaConversaResponse._();
  @$core.override
  DefinirBotDaConversaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirBotDaConversaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DefinirBotDaConversaResponse>(create);
  static DefinirBotDaConversaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get habilitado => $_getBF(0);
  @$pb.TagNumber(1)
  set habilitado($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHabilitado() => $_has(0);
  @$pb.TagNumber(1)
  void clearHabilitado() => $_clearField(1);
}

class MarcarAtendimentoLidoRequest extends $pb.GeneratedMessage {
  factory MarcarAtendimentoLidoRequest({
    $core.int? atendimentoId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    return result;
  }

  MarcarAtendimentoLidoRequest._();

  factory MarcarAtendimentoLidoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MarcarAtendimentoLidoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MarcarAtendimentoLidoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarcarAtendimentoLidoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarcarAtendimentoLidoRequest copyWith(
          void Function(MarcarAtendimentoLidoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as MarcarAtendimentoLidoRequest))
          as MarcarAtendimentoLidoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarcarAtendimentoLidoRequest create() =>
      MarcarAtendimentoLidoRequest._();
  @$core.override
  MarcarAtendimentoLidoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MarcarAtendimentoLidoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MarcarAtendimentoLidoRequest>(create);
  static MarcarAtendimentoLidoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);
}

class MarcarAtendimentoLidoResponse extends $pb.GeneratedMessage {
  factory MarcarAtendimentoLidoResponse({
    $core.int? marcadas,
  }) {
    final result = create();
    if (marcadas != null) result.marcadas = marcadas;
    return result;
  }

  MarcarAtendimentoLidoResponse._();

  factory MarcarAtendimentoLidoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MarcarAtendimentoLidoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MarcarAtendimentoLidoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'marcadas')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarcarAtendimentoLidoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarcarAtendimentoLidoResponse copyWith(
          void Function(MarcarAtendimentoLidoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as MarcarAtendimentoLidoResponse))
          as MarcarAtendimentoLidoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MarcarAtendimentoLidoResponse create() =>
      MarcarAtendimentoLidoResponse._();
  @$core.override
  MarcarAtendimentoLidoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MarcarAtendimentoLidoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MarcarAtendimentoLidoResponse>(create);
  static MarcarAtendimentoLidoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get marcadas => $_getIZ(0);
  @$pb.TagNumber(1)
  set marcadas($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMarcadas() => $_has(0);
  @$pb.TagNumber(1)
  void clearMarcadas() => $_clearField(1);
}

class ListMyWhatsappInstancesRequest extends $pb.GeneratedMessage {
  factory ListMyWhatsappInstancesRequest() => create();

  ListMyWhatsappInstancesRequest._();

  factory ListMyWhatsappInstancesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyWhatsappInstancesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyWhatsappInstancesRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyWhatsappInstancesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyWhatsappInstancesRequest copyWith(
          void Function(ListMyWhatsappInstancesRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyWhatsappInstancesRequest))
          as ListMyWhatsappInstancesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyWhatsappInstancesRequest create() =>
      ListMyWhatsappInstancesRequest._();
  @$core.override
  ListMyWhatsappInstancesRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyWhatsappInstancesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyWhatsappInstancesRequest>(create);
  static ListMyWhatsappInstancesRequest? _defaultInstance;
}

class ListMyWhatsappInstancesResponse extends $pb.GeneratedMessage {
  factory ListMyWhatsappInstancesResponse({
    $core.Iterable<MyWhatsappInstance>? instancias,
  }) {
    final result = create();
    if (instancias != null) result.instancias.addAll(instancias);
    return result;
  }

  ListMyWhatsappInstancesResponse._();

  factory ListMyWhatsappInstancesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyWhatsappInstancesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyWhatsappInstancesResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyWhatsappInstance>(1, _omitFieldNames ? '' : 'instancias',
        subBuilder: MyWhatsappInstance.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyWhatsappInstancesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyWhatsappInstancesResponse copyWith(
          void Function(ListMyWhatsappInstancesResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyWhatsappInstancesResponse))
          as ListMyWhatsappInstancesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyWhatsappInstancesResponse create() =>
      ListMyWhatsappInstancesResponse._();
  @$core.override
  ListMyWhatsappInstancesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyWhatsappInstancesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyWhatsappInstancesResponse>(
          create);
  static ListMyWhatsappInstancesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyWhatsappInstance> get instancias => $_getList(0);
}

class MyWhatsappInstanceIdRequest extends $pb.GeneratedMessage {
  factory MyWhatsappInstanceIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyWhatsappInstanceIdRequest._();

  factory MyWhatsappInstanceIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyWhatsappInstanceIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyWhatsappInstanceIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyWhatsappInstanceIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyWhatsappInstanceIdRequest copyWith(
          void Function(MyWhatsappInstanceIdRequest) updates) =>
      super.copyWith(
              (message) => updates(message as MyWhatsappInstanceIdRequest))
          as MyWhatsappInstanceIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyWhatsappInstanceIdRequest create() =>
      MyWhatsappInstanceIdRequest._();
  @$core.override
  MyWhatsappInstanceIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyWhatsappInstanceIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyWhatsappInstanceIdRequest>(create);
  static MyWhatsappInstanceIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

/// P7 — roteamento por conexão. `departamento_id = 0` desfaz o vínculo.
class DefinirDepartamentoDaConexaoRequest extends $pb.GeneratedMessage {
  factory DefinirDepartamentoDaConexaoRequest({
    $core.int? id,
    $core.int? departamentoId,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (departamentoId != null) result.departamentoId = departamentoId;
    return result;
  }

  DefinirDepartamentoDaConexaoRequest._();

  factory DefinirDepartamentoDaConexaoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DefinirDepartamentoDaConexaoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DefinirDepartamentoDaConexaoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'departamentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirDepartamentoDaConexaoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DefinirDepartamentoDaConexaoRequest copyWith(
          void Function(DefinirDepartamentoDaConexaoRequest) updates) =>
      super.copyWith((message) =>
              updates(message as DefinirDepartamentoDaConexaoRequest))
          as DefinirDepartamentoDaConexaoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DefinirDepartamentoDaConexaoRequest create() =>
      DefinirDepartamentoDaConexaoRequest._();
  @$core.override
  DefinirDepartamentoDaConexaoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DefinirDepartamentoDaConexaoRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          DefinirDepartamentoDaConexaoRequest>(create);
  static DefinirDepartamentoDaConexaoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get departamentoId => $_getIZ(1);
  @$pb.TagNumber(2)
  set departamentoId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDepartamentoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDepartamentoId() => $_clearField(2);
}

/// P7 — o detalhe da conexão: o que não cabe na lista e quem investiga precisa.
class DetalheDaConexaoRequest extends $pb.GeneratedMessage {
  factory DetalheDaConexaoRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  DetalheDaConexaoRequest._();

  factory DetalheDaConexaoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DetalheDaConexaoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DetalheDaConexaoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheDaConexaoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheDaConexaoRequest copyWith(
          void Function(DetalheDaConexaoRequest) updates) =>
      super.copyWith((message) => updates(message as DetalheDaConexaoRequest))
          as DetalheDaConexaoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DetalheDaConexaoRequest create() => DetalheDaConexaoRequest._();
  @$core.override
  DetalheDaConexaoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DetalheDaConexaoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DetalheDaConexaoRequest>(create);
  static DetalheDaConexaoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class DetalheDaConexaoResponse extends $pb.GeneratedMessage {
  factory DetalheDaConexaoResponse({
    MyWhatsappInstance? conexao,
    $fixnum.Int64? ultimaChecagem,
    $core.String? instanciaNoProvedor,
    $core.int? atendimentosAbertos,
    $core.int? mensagens24h,
  }) {
    final result = create();
    if (conexao != null) result.conexao = conexao;
    if (ultimaChecagem != null) result.ultimaChecagem = ultimaChecagem;
    if (instanciaNoProvedor != null)
      result.instanciaNoProvedor = instanciaNoProvedor;
    if (atendimentosAbertos != null)
      result.atendimentosAbertos = atendimentosAbertos;
    if (mensagens24h != null) result.mensagens24h = mensagens24h;
    return result;
  }

  DetalheDaConexaoResponse._();

  factory DetalheDaConexaoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DetalheDaConexaoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DetalheDaConexaoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyWhatsappInstance>(1, _omitFieldNames ? '' : 'conexao',
        subBuilder: MyWhatsappInstance.create)
    ..aInt64(2, _omitFieldNames ? '' : 'ultimaChecagem')
    ..aOS(3, _omitFieldNames ? '' : 'instanciaNoProvedor')
    ..aI(4, _omitFieldNames ? '' : 'atendimentosAbertos')
    ..aI(5, _omitFieldNames ? '' : 'mensagens24h', protoName: 'mensagens_24h')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheDaConexaoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheDaConexaoResponse copyWith(
          void Function(DetalheDaConexaoResponse) updates) =>
      super.copyWith((message) => updates(message as DetalheDaConexaoResponse))
          as DetalheDaConexaoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DetalheDaConexaoResponse create() => DetalheDaConexaoResponse._();
  @$core.override
  DetalheDaConexaoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DetalheDaConexaoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DetalheDaConexaoResponse>(create);
  static DetalheDaConexaoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyWhatsappInstance get conexao => $_getN(0);
  @$pb.TagNumber(1)
  set conexao(MyWhatsappInstance value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasConexao() => $_has(0);
  @$pb.TagNumber(1)
  void clearConexao() => $_clearField(1);
  @$pb.TagNumber(1)
  MyWhatsappInstance ensureConexao() => $_ensure(0);

  /// Quando o estado foi conferido com o provedor pela última vez. 0 = nunca.
  @$pb.TagNumber(2)
  $fixnum.Int64 get ultimaChecagem => $_getI64(1);
  @$pb.TagNumber(2)
  set ultimaChecagem($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUltimaChecagem() => $_has(1);
  @$pb.TagNumber(2)
  void clearUltimaChecagem() => $_clearField(2);

  /// O identificador da instância NO PROVEDOR — o que aparece no log da
  /// evolution-go e o que se manda para o suporte.
  @$pb.TagNumber(3)
  $core.String get instanciaNoProvedor => $_getSZ(2);
  @$pb.TagNumber(3)
  set instanciaNoProvedor($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInstanciaNoProvedor() => $_has(2);
  @$pb.TagNumber(3)
  void clearInstanciaNoProvedor() => $_clearField(3);

  /// Do TENANT, não desta conexão: o atendimento não guarda por qual conexão
  /// entrou. Vale como "desligar agora deixa gente no meio do caminho?", que é
  /// a pergunta de quem está prestes a encerrar a sessão — e, com uma conexão
  /// só, é exatamente o número dela.
  @$pb.TagNumber(4)
  $core.int get atendimentosAbertos => $_getIZ(3);
  @$pb.TagNumber(4)
  set atendimentosAbertos($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtendimentosAbertos() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtendimentosAbertos() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get mensagens24h => $_getIZ(4);
  @$pb.TagNumber(5)
  set mensagens24h($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMensagens24h() => $_has(4);
  @$pb.TagNumber(5)
  void clearMensagens24h() => $_clearField(5);
}

class MensagemNaoEntregue extends $pb.GeneratedMessage {
  factory MensagemNaoEntregue({
    $core.int? id,
    $core.int? mensagemId,
    $core.int? atendimentoId,
    $core.String? motivo,
    $fixnum.Int64? criadoEm,
    $core.String? trecho,
    $core.String? contato,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (mensagemId != null) result.mensagemId = mensagemId;
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (motivo != null) result.motivo = motivo;
    if (criadoEm != null) result.criadoEm = criadoEm;
    if (trecho != null) result.trecho = trecho;
    if (contato != null) result.contato = contato;
    return result;
  }

  MensagemNaoEntregue._();

  factory MensagemNaoEntregue.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MensagemNaoEntregue.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MensagemNaoEntregue',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aI(2, _omitFieldNames ? '' : 'mensagemId')
    ..aI(3, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(4, _omitFieldNames ? '' : 'motivo')
    ..aInt64(5, _omitFieldNames ? '' : 'criadoEm')
    ..aOS(6, _omitFieldNames ? '' : 'trecho')
    ..aOS(7, _omitFieldNames ? '' : 'contato')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MensagemNaoEntregue clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MensagemNaoEntregue copyWith(void Function(MensagemNaoEntregue) updates) =>
      super.copyWith((message) => updates(message as MensagemNaoEntregue))
          as MensagemNaoEntregue;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MensagemNaoEntregue create() => MensagemNaoEntregue._();
  @$core.override
  MensagemNaoEntregue createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MensagemNaoEntregue getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MensagemNaoEntregue>(create);
  static MensagemNaoEntregue? _defaultInstance;

  /// Id do registro de dead-letter — é ele que o reenvio recebe.
  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get mensagemId => $_getIZ(1);
  @$pb.TagNumber(2)
  set mensagemId($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMensagemId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMensagemId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get atendimentoId => $_getIZ(2);
  @$pb.TagNumber(3)
  set atendimentoId($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAtendimentoId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAtendimentoId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get motivo => $_getSZ(3);
  @$pb.TagNumber(4)
  set motivo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMotivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearMotivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get criadoEm => $_getI64(4);
  @$pb.TagNumber(5)
  set criadoEm($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCriadoEm() => $_has(4);
  @$pb.TagNumber(5)
  void clearCriadoEm() => $_clearField(5);

  /// Início do texto, para o atendente reconhecer a mensagem sem abrir a
  /// conversa. É PII como todo conteúdo de mensagem.
  @$pb.TagNumber(6)
  $core.String get trecho => $_getSZ(5);
  @$pb.TagNumber(6)
  set trecho($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTrecho() => $_has(5);
  @$pb.TagNumber(6)
  void clearTrecho() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get contato => $_getSZ(6);
  @$pb.TagNumber(7)
  set contato($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasContato() => $_has(6);
  @$pb.TagNumber(7)
  void clearContato() => $_clearField(7);
}

/// Só as pendentes: as já reenviadas não pedem ação de ninguém.
class ListMyMensagensNaoEntreguesRequest extends $pb.GeneratedMessage {
  factory ListMyMensagensNaoEntreguesRequest() => create();

  ListMyMensagensNaoEntreguesRequest._();

  factory ListMyMensagensNaoEntreguesRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyMensagensNaoEntreguesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyMensagensNaoEntreguesRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyMensagensNaoEntreguesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyMensagensNaoEntreguesRequest copyWith(
          void Function(ListMyMensagensNaoEntreguesRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ListMyMensagensNaoEntreguesRequest))
          as ListMyMensagensNaoEntreguesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyMensagensNaoEntreguesRequest create() =>
      ListMyMensagensNaoEntreguesRequest._();
  @$core.override
  ListMyMensagensNaoEntreguesRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyMensagensNaoEntreguesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyMensagensNaoEntreguesRequest>(
          create);
  static ListMyMensagensNaoEntreguesRequest? _defaultInstance;
}

class ListMyMensagensNaoEntreguesResponse extends $pb.GeneratedMessage {
  factory ListMyMensagensNaoEntreguesResponse({
    $core.Iterable<MensagemNaoEntregue>? itens,
  }) {
    final result = create();
    if (itens != null) result.itens.addAll(itens);
    return result;
  }

  ListMyMensagensNaoEntreguesResponse._();

  factory ListMyMensagensNaoEntreguesResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyMensagensNaoEntreguesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyMensagensNaoEntreguesResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MensagemNaoEntregue>(1, _omitFieldNames ? '' : 'itens',
        subBuilder: MensagemNaoEntregue.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyMensagensNaoEntreguesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyMensagensNaoEntreguesResponse copyWith(
          void Function(ListMyMensagensNaoEntreguesResponse) updates) =>
      super.copyWith((message) =>
              updates(message as ListMyMensagensNaoEntreguesResponse))
          as ListMyMensagensNaoEntreguesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyMensagensNaoEntreguesResponse create() =>
      ListMyMensagensNaoEntreguesResponse._();
  @$core.override
  ListMyMensagensNaoEntreguesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyMensagensNaoEntreguesResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ListMyMensagensNaoEntreguesResponse>(create);
  static ListMyMensagensNaoEntreguesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MensagemNaoEntregue> get itens => $_getList(0);
}

class ReenviarMensagemNaoEntregueRequest extends $pb.GeneratedMessage {
  factory ReenviarMensagemNaoEntregueRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  ReenviarMensagemNaoEntregueRequest._();

  factory ReenviarMensagemNaoEntregueRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReenviarMensagemNaoEntregueRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReenviarMensagemNaoEntregueRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarMensagemNaoEntregueRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarMensagemNaoEntregueRequest copyWith(
          void Function(ReenviarMensagemNaoEntregueRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ReenviarMensagemNaoEntregueRequest))
          as ReenviarMensagemNaoEntregueRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReenviarMensagemNaoEntregueRequest create() =>
      ReenviarMensagemNaoEntregueRequest._();
  @$core.override
  ReenviarMensagemNaoEntregueRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReenviarMensagemNaoEntregueRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReenviarMensagemNaoEntregueRequest>(
          create);
  static ReenviarMensagemNaoEntregueRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class ReenviarMensagemNaoEntregueResponse extends $pb.GeneratedMessage {
  factory ReenviarMensagemNaoEntregueResponse({
    $core.String? status,
  }) {
    final result = create();
    if (status != null) result.status = status;
    return result;
  }

  ReenviarMensagemNaoEntregueResponse._();

  factory ReenviarMensagemNaoEntregueResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReenviarMensagemNaoEntregueResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReenviarMensagemNaoEntregueResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarMensagemNaoEntregueResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReenviarMensagemNaoEntregueResponse copyWith(
          void Function(ReenviarMensagemNaoEntregueResponse) updates) =>
      super.copyWith((message) =>
              updates(message as ReenviarMensagemNaoEntregueResponse))
          as ReenviarMensagemNaoEntregueResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReenviarMensagemNaoEntregueResponse create() =>
      ReenviarMensagemNaoEntregueResponse._();
  @$core.override
  ReenviarMensagemNaoEntregueResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReenviarMensagemNaoEntregueResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          ReenviarMensagemNaoEntregueResponse>(create);
  static ReenviarMensagemNaoEntregueResponse? _defaultInstance;

  /// `reprocessada` (voltou ao outbox, agora ou antes), `ainda_sem_destino` ou
  /// `nao_encontrada`. O segundo NÃO é erro: é a resposta honesta de que o
  /// contato continua sem conexão ativa, e a tela precisa dizer isso.
  @$pb.TagNumber(1)
  $core.String get status => $_getSZ(0);
  @$pb.TagNumber(1)
  set status($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);
}

class GetVersaoDoAppRequest extends $pb.GeneratedMessage {
  factory GetVersaoDoAppRequest({
    $core.String? plataforma,
  }) {
    final result = create();
    if (plataforma != null) result.plataforma = plataforma;
    return result;
  }

  GetVersaoDoAppRequest._();

  factory GetVersaoDoAppRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetVersaoDoAppRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetVersaoDoAppRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'plataforma')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetVersaoDoAppRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetVersaoDoAppRequest copyWith(
          void Function(GetVersaoDoAppRequest) updates) =>
      super.copyWith((message) => updates(message as GetVersaoDoAppRequest))
          as GetVersaoDoAppRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetVersaoDoAppRequest create() => GetVersaoDoAppRequest._();
  @$core.override
  GetVersaoDoAppRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetVersaoDoAppRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetVersaoDoAppRequest>(create);
  static GetVersaoDoAppRequest? _defaultInstance;

  /// "windows" hoje. Um campo, e não um RPC por plataforma, para o dia em que
  /// houver instalador de outro sistema.
  @$pb.TagNumber(1)
  $core.String get plataforma => $_getSZ(0);
  @$pb.TagNumber(1)
  set plataforma($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlataforma() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlataforma() => $_clearField(1);
}

class GetVersaoDoAppResponse extends $pb.GeneratedMessage {
  factory GetVersaoDoAppResponse({
    $fixnum.Int64? buildAtual,
    $core.String? urlDownload,
    $core.String? notas,
  }) {
    final result = create();
    if (buildAtual != null) result.buildAtual = buildAtual;
    if (urlDownload != null) result.urlDownload = urlDownload;
    if (notas != null) result.notas = notas;
    return result;
  }

  GetVersaoDoAppResponse._();

  factory GetVersaoDoAppResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetVersaoDoAppResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetVersaoDoAppResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'buildAtual')
    ..aOS(2, _omitFieldNames ? '' : 'urlDownload')
    ..aOS(3, _omitFieldNames ? '' : 'notas')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetVersaoDoAppResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetVersaoDoAppResponse copyWith(
          void Function(GetVersaoDoAppResponse) updates) =>
      super.copyWith((message) => updates(message as GetVersaoDoAppResponse))
          as GetVersaoDoAppResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetVersaoDoAppResponse create() => GetVersaoDoAppResponse._();
  @$core.override
  GetVersaoDoAppResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetVersaoDoAppResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetVersaoDoAppResponse>(create);
  static GetVersaoDoAppResponse? _defaultInstance;

  /// Número de build (AAAAMMDDhhmm do commit). 0 = ninguém publicou ainda, e aí
  /// não há o que avisar.
  @$pb.TagNumber(1)
  $fixnum.Int64 get buildAtual => $_getI64(0);
  @$pb.TagNumber(1)
  set buildAtual($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBuildAtual() => $_has(0);
  @$pb.TagNumber(1)
  void clearBuildAtual() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get urlDownload => $_getSZ(1);
  @$pb.TagNumber(2)
  set urlDownload($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrlDownload() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrlDownload() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get notas => $_getSZ(2);
  @$pb.TagNumber(3)
  set notas($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNotas() => $_has(2);
  @$pb.TagNumber(3)
  void clearNotas() => $_clearField(3);
}

class TestarProvedorIaRequest extends $pb.GeneratedMessage {
  factory TestarProvedorIaRequest({
    $core.String? tenantId,
  }) {
    final result = create();
    if (tenantId != null) result.tenantId = tenantId;
    return result;
  }

  TestarProvedorIaRequest._();

  factory TestarProvedorIaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestarProvedorIaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestarProvedorIaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tenantId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarProvedorIaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarProvedorIaRequest copyWith(
          void Function(TestarProvedorIaRequest) updates) =>
      super.copyWith((message) => updates(message as TestarProvedorIaRequest))
          as TestarProvedorIaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestarProvedorIaRequest create() => TestarProvedorIaRequest._();
  @$core.override
  TestarProvedorIaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestarProvedorIaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestarProvedorIaRequest>(create);
  static TestarProvedorIaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tenantId => $_getSZ(0);
  @$pb.TagNumber(1)
  set tenantId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTenantId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTenantId() => $_clearField(1);
}

class TestarProvedorIaResponse extends $pb.GeneratedMessage {
  factory TestarProvedorIaResponse({
    $core.bool? ok,
    $core.int? latenciaMs,
    $core.int? dimensoes,
    $core.String? erro,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    if (latenciaMs != null) result.latenciaMs = latenciaMs;
    if (dimensoes != null) result.dimensoes = dimensoes;
    if (erro != null) result.erro = erro;
    return result;
  }

  TestarProvedorIaResponse._();

  factory TestarProvedorIaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestarProvedorIaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestarProvedorIaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aI(2, _omitFieldNames ? '' : 'latenciaMs')
    ..aI(3, _omitFieldNames ? '' : 'dimensoes')
    ..aOS(4, _omitFieldNames ? '' : 'erro')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarProvedorIaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarProvedorIaResponse copyWith(
          void Function(TestarProvedorIaResponse) updates) =>
      super.copyWith((message) => updates(message as TestarProvedorIaResponse))
          as TestarProvedorIaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestarProvedorIaResponse create() => TestarProvedorIaResponse._();
  @$core.override
  TestarProvedorIaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestarProvedorIaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestarProvedorIaResponse>(create);
  static TestarProvedorIaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get latenciaMs => $_getIZ(1);
  @$pb.TagNumber(2)
  set latenciaMs($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLatenciaMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLatenciaMs() => $_clearField(2);

  /// Tamanho do vetor devolvido. Zero com `ok` falso; diferente do esperado
  /// pelo índice é sinal de modelo trocado por fora.
  @$pb.TagNumber(3)
  $core.int get dimensoes => $_getIZ(2);
  @$pb.TagNumber(3)
  set dimensoes($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDimensoes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDimensoes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get erro => $_getSZ(3);
  @$pb.TagNumber(4)
  set erro($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErro() => $_has(3);
  @$pb.TagNumber(4)
  void clearErro() => $_clearField(4);
}

/// --- P7: numeros ignorados ---
///
/// A v1 chamava de "whitelist", e o nome mentia: a lista não libera ninguém, ela
/// IGNORA. Número que está nela não abre atendimento, não aciona a IA e não
/// recebe pesquisa de satisfação. Serve para o número da própria equipe, o do
/// contador, o do fornecedor que só manda boleto — conversas que não são
/// atendimento e que sujavam o quadro.
///
/// A regra já era aplicada na ingestão desde o começo; o que não existia era
/// meio de ver ou mexer na lista sem SQL.
class MyNumeroIgnorado extends $pb.GeneratedMessage {
  factory MyNumeroIgnorado({
    $core.int? id,
    $core.String? nome,
    $core.String? telefone,
    $core.bool? ativo,
    $fixnum.Int64? criadoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (telefone != null) result.telefone = telefone;
    if (ativo != null) result.ativo = ativo;
    if (criadoEm != null) result.criadoEm = criadoEm;
    return result;
  }

  MyNumeroIgnorado._();

  factory MyNumeroIgnorado.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyNumeroIgnorado.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyNumeroIgnorado',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'telefone')
    ..aOB(4, _omitFieldNames ? '' : 'ativo')
    ..aInt64(5, _omitFieldNames ? '' : 'criadoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyNumeroIgnorado clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyNumeroIgnorado copyWith(void Function(MyNumeroIgnorado) updates) =>
      super.copyWith((message) => updates(message as MyNumeroIgnorado))
          as MyNumeroIgnorado;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyNumeroIgnorado create() => MyNumeroIgnorado._();
  @$core.override
  MyNumeroIgnorado createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyNumeroIgnorado getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyNumeroIgnorado>(create);
  static MyNumeroIgnorado? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get telefone => $_getSZ(2);
  @$pb.TagNumber(3)
  set telefone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTelefone() => $_has(2);
  @$pb.TagNumber(3)
  void clearTelefone() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get ativo => $_getBF(3);
  @$pb.TagNumber(4)
  set ativo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get criadoEm => $_getI64(4);
  @$pb.TagNumber(5)
  set criadoEm($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCriadoEm() => $_has(4);
  @$pb.TagNumber(5)
  void clearCriadoEm() => $_clearField(5);
}

/// Traz também os inativos: desligar um número é a forma de voltar a atender
/// alguém sem perder o registro de que ele já esteve fora.
class ListMyNumerosIgnoradosRequest extends $pb.GeneratedMessage {
  factory ListMyNumerosIgnoradosRequest() => create();

  ListMyNumerosIgnoradosRequest._();

  factory ListMyNumerosIgnoradosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyNumerosIgnoradosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyNumerosIgnoradosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyNumerosIgnoradosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyNumerosIgnoradosRequest copyWith(
          void Function(ListMyNumerosIgnoradosRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyNumerosIgnoradosRequest))
          as ListMyNumerosIgnoradosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyNumerosIgnoradosRequest create() =>
      ListMyNumerosIgnoradosRequest._();
  @$core.override
  ListMyNumerosIgnoradosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyNumerosIgnoradosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyNumerosIgnoradosRequest>(create);
  static ListMyNumerosIgnoradosRequest? _defaultInstance;
}

class ListMyNumerosIgnoradosResponse extends $pb.GeneratedMessage {
  factory ListMyNumerosIgnoradosResponse({
    $core.Iterable<MyNumeroIgnorado>? itens,
  }) {
    final result = create();
    if (itens != null) result.itens.addAll(itens);
    return result;
  }

  ListMyNumerosIgnoradosResponse._();

  factory ListMyNumerosIgnoradosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyNumerosIgnoradosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyNumerosIgnoradosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyNumeroIgnorado>(1, _omitFieldNames ? '' : 'itens',
        subBuilder: MyNumeroIgnorado.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyNumerosIgnoradosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyNumerosIgnoradosResponse copyWith(
          void Function(ListMyNumerosIgnoradosResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyNumerosIgnoradosResponse))
          as ListMyNumerosIgnoradosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyNumerosIgnoradosResponse create() =>
      ListMyNumerosIgnoradosResponse._();
  @$core.override
  ListMyNumerosIgnoradosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyNumerosIgnoradosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyNumerosIgnoradosResponse>(create);
  static ListMyNumerosIgnoradosResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyNumeroIgnorado> get itens => $_getList(0);
}

class CriarNumeroIgnoradoRequest extends $pb.GeneratedMessage {
  factory CriarNumeroIgnoradoRequest({
    $core.String? nome,
    $core.String? telefone,
  }) {
    final result = create();
    if (nome != null) result.nome = nome;
    if (telefone != null) result.telefone = telefone;
    return result;
  }

  CriarNumeroIgnoradoRequest._();

  factory CriarNumeroIgnoradoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CriarNumeroIgnoradoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CriarNumeroIgnoradoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nome')
    ..aOS(2, _omitFieldNames ? '' : 'telefone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CriarNumeroIgnoradoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CriarNumeroIgnoradoRequest copyWith(
          void Function(CriarNumeroIgnoradoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CriarNumeroIgnoradoRequest))
          as CriarNumeroIgnoradoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CriarNumeroIgnoradoRequest create() => CriarNumeroIgnoradoRequest._();
  @$core.override
  CriarNumeroIgnoradoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CriarNumeroIgnoradoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CriarNumeroIgnoradoRequest>(create);
  static CriarNumeroIgnoradoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nome => $_getSZ(0);
  @$pb.TagNumber(1)
  set nome($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNome() => $_has(0);
  @$pb.TagNumber(1)
  void clearNome() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get telefone => $_getSZ(1);
  @$pb.TagNumber(2)
  set telefone($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTelefone() => $_has(1);
  @$pb.TagNumber(2)
  void clearTelefone() => $_clearField(2);
}

class MyNumeroIgnoradoResponse extends $pb.GeneratedMessage {
  factory MyNumeroIgnoradoResponse({
    MyNumeroIgnorado? item,
  }) {
    final result = create();
    if (item != null) result.item = item;
    return result;
  }

  MyNumeroIgnoradoResponse._();

  factory MyNumeroIgnoradoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyNumeroIgnoradoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyNumeroIgnoradoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyNumeroIgnorado>(1, _omitFieldNames ? '' : 'item',
        subBuilder: MyNumeroIgnorado.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyNumeroIgnoradoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyNumeroIgnoradoResponse copyWith(
          void Function(MyNumeroIgnoradoResponse) updates) =>
      super.copyWith((message) => updates(message as MyNumeroIgnoradoResponse))
          as MyNumeroIgnoradoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyNumeroIgnoradoResponse create() => MyNumeroIgnoradoResponse._();
  @$core.override
  MyNumeroIgnoradoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyNumeroIgnoradoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyNumeroIgnoradoResponse>(create);
  static MyNumeroIgnoradoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyNumeroIgnorado get item => $_getN(0);
  @$pb.TagNumber(1)
  set item(MyNumeroIgnorado value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasItem() => $_has(0);
  @$pb.TagNumber(1)
  void clearItem() => $_clearField(1);
  @$pb.TagNumber(1)
  MyNumeroIgnorado ensureItem() => $_ensure(0);
}

class AtualizarNumeroIgnoradoRequest extends $pb.GeneratedMessage {
  factory AtualizarNumeroIgnoradoRequest({
    $core.int? id,
    $core.String? nome,
    $core.String? telefone,
    $core.bool? ativo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (telefone != null) result.telefone = telefone;
    if (ativo != null) result.ativo = ativo;
    return result;
  }

  AtualizarNumeroIgnoradoRequest._();

  factory AtualizarNumeroIgnoradoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtualizarNumeroIgnoradoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtualizarNumeroIgnoradoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'telefone')
    ..aOB(4, _omitFieldNames ? '' : 'ativo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtualizarNumeroIgnoradoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtualizarNumeroIgnoradoRequest copyWith(
          void Function(AtualizarNumeroIgnoradoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as AtualizarNumeroIgnoradoRequest))
          as AtualizarNumeroIgnoradoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtualizarNumeroIgnoradoRequest create() =>
      AtualizarNumeroIgnoradoRequest._();
  @$core.override
  AtualizarNumeroIgnoradoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtualizarNumeroIgnoradoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtualizarNumeroIgnoradoRequest>(create);
  static AtualizarNumeroIgnoradoRequest? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get telefone => $_getSZ(2);
  @$pb.TagNumber(3)
  set telefone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTelefone() => $_has(2);
  @$pb.TagNumber(3)
  void clearTelefone() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get ativo => $_getBF(3);
  @$pb.TagNumber(4)
  set ativo($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtivo() => $_clearField(4);
}

class NumeroIgnoradoIdRequest extends $pb.GeneratedMessage {
  factory NumeroIgnoradoIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  NumeroIgnoradoIdRequest._();

  factory NumeroIgnoradoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NumeroIgnoradoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NumeroIgnoradoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NumeroIgnoradoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NumeroIgnoradoIdRequest copyWith(
          void Function(NumeroIgnoradoIdRequest) updates) =>
      super.copyWith((message) => updates(message as NumeroIgnoradoIdRequest))
          as NumeroIgnoradoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NumeroIgnoradoIdRequest create() => NumeroIgnoradoIdRequest._();
  @$core.override
  NumeroIgnoradoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NumeroIgnoradoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NumeroIgnoradoIdRequest>(create);
  static NumeroIgnoradoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class MyTreinamento extends $pb.GeneratedMessage {
  factory MyTreinamento({
    $core.int? id,
    $core.String? tag,
    $core.String? grupo,
    $core.String? conteudo,
    $core.bool? finalizado,
    $core.bool? vetorizado,
    $fixnum.Int64? criadoEm,
    $fixnum.Int64? atualizadoEm,
    $core.String? arquivoNome,
    $core.String? extracaoStatus,
    $core.String? extracaoErro,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (tag != null) result.tag = tag;
    if (grupo != null) result.grupo = grupo;
    if (conteudo != null) result.conteudo = conteudo;
    if (finalizado != null) result.finalizado = finalizado;
    if (vetorizado != null) result.vetorizado = vetorizado;
    if (criadoEm != null) result.criadoEm = criadoEm;
    if (atualizadoEm != null) result.atualizadoEm = atualizadoEm;
    if (arquivoNome != null) result.arquivoNome = arquivoNome;
    if (extracaoStatus != null) result.extracaoStatus = extracaoStatus;
    if (extracaoErro != null) result.extracaoErro = extracaoErro;
    return result;
  }

  MyTreinamento._();

  factory MyTreinamento.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyTreinamento.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyTreinamento',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'tag')
    ..aOS(3, _omitFieldNames ? '' : 'grupo')
    ..aOS(4, _omitFieldNames ? '' : 'conteudo')
    ..aOB(5, _omitFieldNames ? '' : 'finalizado')
    ..aOB(6, _omitFieldNames ? '' : 'vetorizado')
    ..aInt64(7, _omitFieldNames ? '' : 'criadoEm')
    ..aInt64(8, _omitFieldNames ? '' : 'atualizadoEm')
    ..aOS(9, _omitFieldNames ? '' : 'arquivoNome')
    ..aOS(10, _omitFieldNames ? '' : 'extracaoStatus')
    ..aOS(11, _omitFieldNames ? '' : 'extracaoErro')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyTreinamento clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyTreinamento copyWith(void Function(MyTreinamento) updates) =>
      super.copyWith((message) => updates(message as MyTreinamento))
          as MyTreinamento;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyTreinamento create() => MyTreinamento._();
  @$core.override
  MyTreinamento createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyTreinamento getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyTreinamento>(create);
  static MyTreinamento? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Assunto e agrupamento — a dupla identifica o treinamento no tenant.
  @$pb.TagNumber(2)
  $core.String get tag => $_getSZ(1);
  @$pb.TagNumber(2)
  set tag($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearTag() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get grupo => $_getSZ(2);
  @$pb.TagNumber(3)
  set grupo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGrupo() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrupo() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get conteudo => $_getSZ(3);
  @$pb.TagNumber(4)
  set conteudo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConteudo() => $_has(3);
  @$pb.TagNumber(4)
  void clearConteudo() => $_clearField(4);

  /// Aceito pelo usuário e enviado para vetorização.
  @$pb.TagNumber(5)
  $core.bool get finalizado => $_getBF(4);
  @$pb.TagNumber(5)
  set finalizado($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFinalizado() => $_has(4);
  @$pb.TagNumber(5)
  void clearFinalizado() => $_clearField(5);

  /// Já virou vetor: a partir daqui o assistente usa este material.
  @$pb.TagNumber(6)
  $core.bool get vetorizado => $_getBF(5);
  @$pb.TagNumber(6)
  set vetorizado($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasVetorizado() => $_has(5);
  @$pb.TagNumber(6)
  void clearVetorizado() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get criadoEm => $_getI64(6);
  @$pb.TagNumber(7)
  set criadoEm($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCriadoEm() => $_has(6);
  @$pb.TagNumber(7)
  void clearCriadoEm() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get atualizadoEm => $_getI64(7);
  @$pb.TagNumber(8)
  set atualizadoEm($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAtualizadoEm() => $_has(7);
  @$pb.TagNumber(8)
  void clearAtualizadoEm() => $_clearField(8);

  /// B9 (N10 E5) - vazios quando o treinamento e de texto colado.
  @$pb.TagNumber(9)
  $core.String get arquivoNome => $_getSZ(8);
  @$pb.TagNumber(9)
  set arquivoNome($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasArquivoNome() => $_has(8);
  @$pb.TagNumber(9)
  void clearArquivoNome() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get extracaoStatus => $_getSZ(9);
  @$pb.TagNumber(10)
  set extracaoStatus($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasExtracaoStatus() => $_has(9);
  @$pb.TagNumber(10)
  void clearExtracaoStatus() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get extracaoErro => $_getSZ(10);
  @$pb.TagNumber(11)
  set extracaoErro($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasExtracaoErro() => $_has(10);
  @$pb.TagNumber(11)
  void clearExtracaoErro() => $_clearField(11);
}

/// B9 (N10 E5) - passo 1 do treinamento por arquivo: onde subir.
class SolicitarUploadTreinamentoRequest extends $pb.GeneratedMessage {
  factory SolicitarUploadTreinamentoRequest({
    $core.String? nomeArquivo,
    $core.String? mimetype,
    $fixnum.Int64? bytes,
  }) {
    final result = create();
    if (nomeArquivo != null) result.nomeArquivo = nomeArquivo;
    if (mimetype != null) result.mimetype = mimetype;
    if (bytes != null) result.bytes = bytes;
    return result;
  }

  SolicitarUploadTreinamentoRequest._();

  factory SolicitarUploadTreinamentoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolicitarUploadTreinamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolicitarUploadTreinamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nomeArquivo')
    ..aOS(2, _omitFieldNames ? '' : 'mimetype')
    ..aInt64(3, _omitFieldNames ? '' : 'bytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadTreinamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadTreinamentoRequest copyWith(
          void Function(SolicitarUploadTreinamentoRequest) updates) =>
      super.copyWith((message) =>
              updates(message as SolicitarUploadTreinamentoRequest))
          as SolicitarUploadTreinamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolicitarUploadTreinamentoRequest create() =>
      SolicitarUploadTreinamentoRequest._();
  @$core.override
  SolicitarUploadTreinamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolicitarUploadTreinamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolicitarUploadTreinamentoRequest>(
          create);
  static SolicitarUploadTreinamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nomeArquivo => $_getSZ(0);
  @$pb.TagNumber(1)
  set nomeArquivo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNomeArquivo() => $_has(0);
  @$pb.TagNumber(1)
  void clearNomeArquivo() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimetype => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimetype($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMimetype() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimetype() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytes => $_getI64(2);
  @$pb.TagNumber(3)
  set bytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytes() => $_clearField(3);
}

class SolicitarUploadTreinamentoResponse extends $pb.GeneratedMessage {
  factory SolicitarUploadTreinamentoResponse({
    $core.String? urlUpload,
    $core.String? chave,
    $core.String? contentType,
    $fixnum.Int64? expiraEmSegundos,
  }) {
    final result = create();
    if (urlUpload != null) result.urlUpload = urlUpload;
    if (chave != null) result.chave = chave;
    if (contentType != null) result.contentType = contentType;
    if (expiraEmSegundos != null) result.expiraEmSegundos = expiraEmSegundos;
    return result;
  }

  SolicitarUploadTreinamentoResponse._();

  factory SolicitarUploadTreinamentoResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolicitarUploadTreinamentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolicitarUploadTreinamentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'urlUpload')
    ..aOS(2, _omitFieldNames ? '' : 'chave')
    ..aOS(3, _omitFieldNames ? '' : 'contentType')
    ..aInt64(4, _omitFieldNames ? '' : 'expiraEmSegundos')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadTreinamentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolicitarUploadTreinamentoResponse copyWith(
          void Function(SolicitarUploadTreinamentoResponse) updates) =>
      super.copyWith((message) =>
              updates(message as SolicitarUploadTreinamentoResponse))
          as SolicitarUploadTreinamentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolicitarUploadTreinamentoResponse create() =>
      SolicitarUploadTreinamentoResponse._();
  @$core.override
  SolicitarUploadTreinamentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolicitarUploadTreinamentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolicitarUploadTreinamentoResponse>(
          create);
  static SolicitarUploadTreinamentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get urlUpload => $_getSZ(0);
  @$pb.TagNumber(1)
  set urlUpload($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrlUpload() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrlUpload() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get chave => $_getSZ(1);
  @$pb.TagNumber(2)
  set chave($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChave() => $_has(1);
  @$pb.TagNumber(2)
  void clearChave() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get contentType => $_getSZ(2);
  @$pb.TagNumber(3)
  set contentType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContentType() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentType() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expiraEmSegundos => $_getI64(3);
  @$pb.TagNumber(4)
  set expiraEmSegundos($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpiraEmSegundos() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpiraEmSegundos() => $_clearField(4);
}

/// B9 (N10 E5) - passo 3: o arquivo subiu; cria o treinamento.
class CreateMyTreinamentoComArquivoRequest extends $pb.GeneratedMessage {
  factory CreateMyTreinamentoComArquivoRequest({
    $core.String? tag,
    $core.String? grupo,
    $core.String? chave,
    $core.String? nomeArquivo,
    $core.String? mimetype,
  }) {
    final result = create();
    if (tag != null) result.tag = tag;
    if (grupo != null) result.grupo = grupo;
    if (chave != null) result.chave = chave;
    if (nomeArquivo != null) result.nomeArquivo = nomeArquivo;
    if (mimetype != null) result.mimetype = mimetype;
    return result;
  }

  CreateMyTreinamentoComArquivoRequest._();

  factory CreateMyTreinamentoComArquivoRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyTreinamentoComArquivoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyTreinamentoComArquivoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tag')
    ..aOS(2, _omitFieldNames ? '' : 'grupo')
    ..aOS(3, _omitFieldNames ? '' : 'chave')
    ..aOS(4, _omitFieldNames ? '' : 'nomeArquivo')
    ..aOS(5, _omitFieldNames ? '' : 'mimetype')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyTreinamentoComArquivoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyTreinamentoComArquivoRequest copyWith(
          void Function(CreateMyTreinamentoComArquivoRequest) updates) =>
      super.copyWith((message) =>
              updates(message as CreateMyTreinamentoComArquivoRequest))
          as CreateMyTreinamentoComArquivoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyTreinamentoComArquivoRequest create() =>
      CreateMyTreinamentoComArquivoRequest._();
  @$core.override
  CreateMyTreinamentoComArquivoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyTreinamentoComArquivoRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          CreateMyTreinamentoComArquivoRequest>(create);
  static CreateMyTreinamentoComArquivoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tag => $_getSZ(0);
  @$pb.TagNumber(1)
  set tag($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearTag() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get grupo => $_getSZ(1);
  @$pb.TagNumber(2)
  set grupo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGrupo() => $_has(1);
  @$pb.TagNumber(2)
  void clearGrupo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get chave => $_getSZ(2);
  @$pb.TagNumber(3)
  set chave($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChave() => $_has(2);
  @$pb.TagNumber(3)
  void clearChave() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get nomeArquivo => $_getSZ(3);
  @$pb.TagNumber(4)
  set nomeArquivo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNomeArquivo() => $_has(3);
  @$pb.TagNumber(4)
  void clearNomeArquivo() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get mimetype => $_getSZ(4);
  @$pb.TagNumber(5)
  set mimetype($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMimetype() => $_has(4);
  @$pb.TagNumber(5)
  void clearMimetype() => $_clearField(5);
}

class CreateMyTreinamentoRequest extends $pb.GeneratedMessage {
  factory CreateMyTreinamentoRequest({
    $core.String? tag,
    $core.String? grupo,
    $core.String? conteudo,
  }) {
    final result = create();
    if (tag != null) result.tag = tag;
    if (grupo != null) result.grupo = grupo;
    if (conteudo != null) result.conteudo = conteudo;
    return result;
  }

  CreateMyTreinamentoRequest._();

  factory CreateMyTreinamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMyTreinamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMyTreinamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tag')
    ..aOS(2, _omitFieldNames ? '' : 'grupo')
    ..aOS(3, _omitFieldNames ? '' : 'conteudo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyTreinamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMyTreinamentoRequest copyWith(
          void Function(CreateMyTreinamentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateMyTreinamentoRequest))
          as CreateMyTreinamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMyTreinamentoRequest create() => CreateMyTreinamentoRequest._();
  @$core.override
  CreateMyTreinamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMyTreinamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMyTreinamentoRequest>(create);
  static CreateMyTreinamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tag => $_getSZ(0);
  @$pb.TagNumber(1)
  set tag($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearTag() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get grupo => $_getSZ(1);
  @$pb.TagNumber(2)
  set grupo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGrupo() => $_has(1);
  @$pb.TagNumber(2)
  void clearGrupo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get conteudo => $_getSZ(2);
  @$pb.TagNumber(3)
  set conteudo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConteudo() => $_has(2);
  @$pb.TagNumber(3)
  void clearConteudo() => $_clearField(3);
}

class MyTreinamentoResponse extends $pb.GeneratedMessage {
  factory MyTreinamentoResponse({
    MyTreinamento? treinamento,
  }) {
    final result = create();
    if (treinamento != null) result.treinamento = treinamento;
    return result;
  }

  MyTreinamentoResponse._();

  factory MyTreinamentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyTreinamentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyTreinamentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyTreinamento>(1, _omitFieldNames ? '' : 'treinamento',
        subBuilder: MyTreinamento.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyTreinamentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyTreinamentoResponse copyWith(
          void Function(MyTreinamentoResponse) updates) =>
      super.copyWith((message) => updates(message as MyTreinamentoResponse))
          as MyTreinamentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyTreinamentoResponse create() => MyTreinamentoResponse._();
  @$core.override
  MyTreinamentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyTreinamentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyTreinamentoResponse>(create);
  static MyTreinamentoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyTreinamento get treinamento => $_getN(0);
  @$pb.TagNumber(1)
  set treinamento(MyTreinamento value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTreinamento() => $_has(0);
  @$pb.TagNumber(1)
  void clearTreinamento() => $_clearField(1);
  @$pb.TagNumber(1)
  MyTreinamento ensureTreinamento() => $_ensure(0);
}

class ListMyTreinamentosRequest extends $pb.GeneratedMessage {
  factory ListMyTreinamentosRequest() => create();

  ListMyTreinamentosRequest._();

  factory ListMyTreinamentosRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyTreinamentosRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyTreinamentosRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyTreinamentosRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyTreinamentosRequest copyWith(
          void Function(ListMyTreinamentosRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyTreinamentosRequest))
          as ListMyTreinamentosRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyTreinamentosRequest create() => ListMyTreinamentosRequest._();
  @$core.override
  ListMyTreinamentosRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyTreinamentosRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyTreinamentosRequest>(create);
  static ListMyTreinamentosRequest? _defaultInstance;
}

class ListMyTreinamentosResponse extends $pb.GeneratedMessage {
  factory ListMyTreinamentosResponse({
    $core.Iterable<MyTreinamento>? treinamentos,
  }) {
    final result = create();
    if (treinamentos != null) result.treinamentos.addAll(treinamentos);
    return result;
  }

  ListMyTreinamentosResponse._();

  factory ListMyTreinamentosResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyTreinamentosResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyTreinamentosResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyTreinamento>(1, _omitFieldNames ? '' : 'treinamentos',
        subBuilder: MyTreinamento.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyTreinamentosResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyTreinamentosResponse copyWith(
          void Function(ListMyTreinamentosResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListMyTreinamentosResponse))
          as ListMyTreinamentosResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyTreinamentosResponse create() => ListMyTreinamentosResponse._();
  @$core.override
  ListMyTreinamentosResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyTreinamentosResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyTreinamentosResponse>(create);
  static ListMyTreinamentosResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyTreinamento> get treinamentos => $_getList(0);
}

class GetMyTreinamentoRequest extends $pb.GeneratedMessage {
  factory GetMyTreinamentoRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  GetMyTreinamentoRequest._();

  factory GetMyTreinamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetMyTreinamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMyTreinamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyTreinamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMyTreinamentoRequest copyWith(
          void Function(GetMyTreinamentoRequest) updates) =>
      super.copyWith((message) => updates(message as GetMyTreinamentoRequest))
          as GetMyTreinamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetMyTreinamentoRequest create() => GetMyTreinamentoRequest._();
  @$core.override
  GetMyTreinamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetMyTreinamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMyTreinamentoRequest>(create);
  static GetMyTreinamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class FinalizarMyTreinamentoRequest extends $pb.GeneratedMessage {
  factory FinalizarMyTreinamentoRequest({
    $core.int? id,
    $core.String? conteudo,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (conteudo != null) result.conteudo = conteudo;
    return result;
  }

  FinalizarMyTreinamentoRequest._();

  factory FinalizarMyTreinamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FinalizarMyTreinamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinalizarMyTreinamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'conteudo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizarMyTreinamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinalizarMyTreinamentoRequest copyWith(
          void Function(FinalizarMyTreinamentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as FinalizarMyTreinamentoRequest))
          as FinalizarMyTreinamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinalizarMyTreinamentoRequest create() =>
      FinalizarMyTreinamentoRequest._();
  @$core.override
  FinalizarMyTreinamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FinalizarMyTreinamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinalizarMyTreinamentoRequest>(create);
  static FinalizarMyTreinamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// O texto como ficou depois da revisão — é ele que vira vetor.
  @$pb.TagNumber(2)
  $core.String get conteudo => $_getSZ(1);
  @$pb.TagNumber(2)
  set conteudo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConteudo() => $_has(1);
  @$pb.TagNumber(2)
  void clearConteudo() => $_clearField(2);
}

class RemoverMyTreinamentoRequest extends $pb.GeneratedMessage {
  factory RemoverMyTreinamentoRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  RemoverMyTreinamentoRequest._();

  factory RemoverMyTreinamentoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RemoverMyTreinamentoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoverMyTreinamentoRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoverMyTreinamentoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoverMyTreinamentoRequest copyWith(
          void Function(RemoverMyTreinamentoRequest) updates) =>
      super.copyWith(
              (message) => updates(message as RemoverMyTreinamentoRequest))
          as RemoverMyTreinamentoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoverMyTreinamentoRequest create() =>
      RemoverMyTreinamentoRequest._();
  @$core.override
  RemoverMyTreinamentoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RemoverMyTreinamentoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoverMyTreinamentoRequest>(create);
  static RemoverMyTreinamentoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class SimpleOkResponse extends $pb.GeneratedMessage {
  factory SimpleOkResponse({
    $core.bool? sucesso,
  }) {
    final result = create();
    if (sucesso != null) result.sucesso = sucesso;
    return result;
  }

  SimpleOkResponse._();

  factory SimpleOkResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SimpleOkResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SimpleOkResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'sucesso')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimpleOkResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimpleOkResponse copyWith(void Function(SimpleOkResponse) updates) =>
      super.copyWith((message) => updates(message as SimpleOkResponse))
          as SimpleOkResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SimpleOkResponse create() => SimpleOkResponse._();
  @$core.override
  SimpleOkResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SimpleOkResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SimpleOkResponse>(create);
  static SimpleOkResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get sucesso => $_getBF(0);
  @$pb.TagNumber(1)
  set sucesso($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSucesso() => $_has(0);
  @$pb.TagNumber(1)
  void clearSucesso() => $_clearField(1);
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

class MyIntent extends $pb.GeneratedMessage {
  factory MyIntent({
    $core.int? id,
    $core.String? tag,
    $core.String? grupo,
    $core.String? descricao,
    $core.String? exemplo,
    $core.String? comportamento,
    $core.bool? vetorizada,
    $fixnum.Int64? criadoEm,
    $fixnum.Int64? atualizadoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (tag != null) result.tag = tag;
    if (grupo != null) result.grupo = grupo;
    if (descricao != null) result.descricao = descricao;
    if (exemplo != null) result.exemplo = exemplo;
    if (comportamento != null) result.comportamento = comportamento;
    if (vetorizada != null) result.vetorizada = vetorizada;
    if (criadoEm != null) result.criadoEm = criadoEm;
    if (atualizadoEm != null) result.atualizadoEm = atualizadoEm;
    return result;
  }

  MyIntent._();

  factory MyIntent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyIntent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyIntent',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'tag')
    ..aOS(3, _omitFieldNames ? '' : 'grupo')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aOS(5, _omitFieldNames ? '' : 'exemplo')
    ..aOS(6, _omitFieldNames ? '' : 'comportamento')
    ..aOB(7, _omitFieldNames ? '' : 'vetorizada')
    ..aInt64(8, _omitFieldNames ? '' : 'criadoEm')
    ..aInt64(9, _omitFieldNames ? '' : 'atualizadoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntent copyWith(void Function(MyIntent) updates) =>
      super.copyWith((message) => updates(message as MyIntent)) as MyIntent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyIntent create() => MyIntent._();
  @$core.override
  MyIntent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyIntent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MyIntent>(create);
  static MyIntent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tag => $_getSZ(1);
  @$pb.TagNumber(2)
  set tag($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearTag() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get grupo => $_getSZ(2);
  @$pb.TagNumber(3)
  set grupo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGrupo() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrupo() => $_clearField(3);

  /// Quando esta intencao se aplica. Entra no texto que vira vetor.
  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  /// Uma pergunta tipica do cliente. Tambem entra no vetor.
  @$pb.TagNumber(5)
  $core.String get exemplo => $_getSZ(4);
  @$pb.TagNumber(5)
  set exemplo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasExemplo() => $_has(4);
  @$pb.TagNumber(5)
  void clearExemplo() => $_clearField(5);

  /// O que a IA passa a fazer quando a intencao casa.
  @$pb.TagNumber(6)
  $core.String get comportamento => $_getSZ(5);
  @$pb.TagNumber(6)
  set comportamento($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasComportamento() => $_has(5);
  @$pb.TagNumber(6)
  void clearComportamento() => $_clearField(6);

  /// `false` enquanto o worker nao gerou o vetor. Ate la a intencao existe no
  /// cadastro e NAO existe para a IA -- a busca semantica filtra por embedding.
  @$pb.TagNumber(7)
  $core.bool get vetorizada => $_getBF(6);
  @$pb.TagNumber(7)
  set vetorizada($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasVetorizada() => $_has(6);
  @$pb.TagNumber(7)
  void clearVetorizada() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get criadoEm => $_getI64(7);
  @$pb.TagNumber(8)
  set criadoEm($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCriadoEm() => $_has(7);
  @$pb.TagNumber(8)
  void clearCriadoEm() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get atualizadoEm => $_getI64(8);
  @$pb.TagNumber(9)
  set atualizadoEm($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAtualizadoEm() => $_has(8);
  @$pb.TagNumber(9)
  void clearAtualizadoEm() => $_clearField(9);
}

class ListMyIntentsRequest extends $pb.GeneratedMessage {
  factory ListMyIntentsRequest() => create();

  ListMyIntentsRequest._();

  factory ListMyIntentsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyIntentsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyIntentsRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyIntentsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyIntentsRequest copyWith(void Function(ListMyIntentsRequest) updates) =>
      super.copyWith((message) => updates(message as ListMyIntentsRequest))
          as ListMyIntentsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyIntentsRequest create() => ListMyIntentsRequest._();
  @$core.override
  ListMyIntentsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyIntentsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyIntentsRequest>(create);
  static ListMyIntentsRequest? _defaultInstance;
}

class ListMyIntentsResponse extends $pb.GeneratedMessage {
  factory ListMyIntentsResponse({
    $core.Iterable<MyIntent>? intents,
  }) {
    final result = create();
    if (intents != null) result.intents.addAll(intents);
    return result;
  }

  ListMyIntentsResponse._();

  factory ListMyIntentsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListMyIntentsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMyIntentsResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<MyIntent>(1, _omitFieldNames ? '' : 'intents',
        subBuilder: MyIntent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyIntentsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMyIntentsResponse copyWith(
          void Function(ListMyIntentsResponse) updates) =>
      super.copyWith((message) => updates(message as ListMyIntentsResponse))
          as ListMyIntentsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListMyIntentsResponse create() => ListMyIntentsResponse._();
  @$core.override
  ListMyIntentsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListMyIntentsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMyIntentsResponse>(create);
  static ListMyIntentsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<MyIntent> get intents => $_getList(0);
}

class MyIntentDados extends $pb.GeneratedMessage {
  factory MyIntentDados({
    $core.String? tag,
    $core.String? grupo,
    $core.String? descricao,
    $core.String? exemplo,
    $core.String? comportamento,
  }) {
    final result = create();
    if (tag != null) result.tag = tag;
    if (grupo != null) result.grupo = grupo;
    if (descricao != null) result.descricao = descricao;
    if (exemplo != null) result.exemplo = exemplo;
    if (comportamento != null) result.comportamento = comportamento;
    return result;
  }

  MyIntentDados._();

  factory MyIntentDados.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyIntentDados.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyIntentDados',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'tag')
    ..aOS(2, _omitFieldNames ? '' : 'grupo')
    ..aOS(3, _omitFieldNames ? '' : 'descricao')
    ..aOS(4, _omitFieldNames ? '' : 'exemplo')
    ..aOS(5, _omitFieldNames ? '' : 'comportamento')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentDados clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentDados copyWith(void Function(MyIntentDados) updates) =>
      super.copyWith((message) => updates(message as MyIntentDados))
          as MyIntentDados;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyIntentDados create() => MyIntentDados._();
  @$core.override
  MyIntentDados createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyIntentDados getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyIntentDados>(create);
  static MyIntentDados? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tag => $_getSZ(0);
  @$pb.TagNumber(1)
  set tag($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearTag() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get grupo => $_getSZ(1);
  @$pb.TagNumber(2)
  set grupo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGrupo() => $_has(1);
  @$pb.TagNumber(2)
  void clearGrupo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get descricao => $_getSZ(2);
  @$pb.TagNumber(3)
  set descricao($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescricao() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescricao() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get exemplo => $_getSZ(3);
  @$pb.TagNumber(4)
  set exemplo($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExemplo() => $_has(3);
  @$pb.TagNumber(4)
  void clearExemplo() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get comportamento => $_getSZ(4);
  @$pb.TagNumber(5)
  set comportamento($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasComportamento() => $_has(4);
  @$pb.TagNumber(5)
  void clearComportamento() => $_clearField(5);
}

class MyIntentResponse extends $pb.GeneratedMessage {
  factory MyIntentResponse({
    MyIntent? intent,
  }) {
    final result = create();
    if (intent != null) result.intent = intent;
    return result;
  }

  MyIntentResponse._();

  factory MyIntentResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyIntentResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyIntentResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<MyIntent>(1, _omitFieldNames ? '' : 'intent',
        subBuilder: MyIntent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentResponse copyWith(void Function(MyIntentResponse) updates) =>
      super.copyWith((message) => updates(message as MyIntentResponse))
          as MyIntentResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyIntentResponse create() => MyIntentResponse._();
  @$core.override
  MyIntentResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyIntentResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyIntentResponse>(create);
  static MyIntentResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MyIntent get intent => $_getN(0);
  @$pb.TagNumber(1)
  set intent(MyIntent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasIntent() => $_has(0);
  @$pb.TagNumber(1)
  void clearIntent() => $_clearField(1);
  @$pb.TagNumber(1)
  MyIntent ensureIntent() => $_ensure(0);
}

class UpdateMyIntentRequest extends $pb.GeneratedMessage {
  factory UpdateMyIntentRequest({
    $core.int? id,
    MyIntentDados? dados,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (dados != null) result.dados = dados;
    return result;
  }

  UpdateMyIntentRequest._();

  factory UpdateMyIntentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateMyIntentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateMyIntentRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..aOM<MyIntentDados>(2, _omitFieldNames ? '' : 'dados',
        subBuilder: MyIntentDados.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyIntentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateMyIntentRequest copyWith(
          void Function(UpdateMyIntentRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateMyIntentRequest))
          as UpdateMyIntentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateMyIntentRequest create() => UpdateMyIntentRequest._();
  @$core.override
  UpdateMyIntentRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateMyIntentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateMyIntentRequest>(create);
  static UpdateMyIntentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  MyIntentDados get dados => $_getN(1);
  @$pb.TagNumber(2)
  set dados(MyIntentDados value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDados() => $_has(1);
  @$pb.TagNumber(2)
  void clearDados() => $_clearField(2);
  @$pb.TagNumber(2)
  MyIntentDados ensureDados() => $_ensure(1);
}

class MyIntentIdRequest extends $pb.GeneratedMessage {
  factory MyIntentIdRequest({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  MyIntentIdRequest._();

  factory MyIntentIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MyIntentIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MyIntentIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MyIntentIdRequest copyWith(void Function(MyIntentIdRequest) updates) =>
      super.copyWith((message) => updates(message as MyIntentIdRequest))
          as MyIntentIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MyIntentIdRequest create() => MyIntentIdRequest._();
  @$core.override
  MyIntentIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MyIntentIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MyIntentIdRequest>(create);
  static MyIntentIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class TestarPerguntaRequest extends $pb.GeneratedMessage {
  factory TestarPerguntaRequest({
    $core.String? pergunta,
  }) {
    final result = create();
    if (pergunta != null) result.pergunta = pergunta;
    return result;
  }

  TestarPerguntaRequest._();

  factory TestarPerguntaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestarPerguntaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestarPerguntaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'pergunta')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarPerguntaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarPerguntaRequest copyWith(
          void Function(TestarPerguntaRequest) updates) =>
      super.copyWith((message) => updates(message as TestarPerguntaRequest))
          as TestarPerguntaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestarPerguntaRequest create() => TestarPerguntaRequest._();
  @$core.override
  TestarPerguntaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestarPerguntaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestarPerguntaRequest>(create);
  static TestarPerguntaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pergunta => $_getSZ(0);
  @$pb.TagNumber(1)
  set pergunta($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPergunta() => $_has(0);
  @$pb.TagNumber(1)
  void clearPergunta() => $_clearField(1);
}

/// / Um trecho de material que a IA usou para responder.
class TrechoUsado extends $pb.GeneratedMessage {
  factory TrechoUsado({
    $core.String? conteudo,
    $core.double? distancia,
  }) {
    final result = create();
    if (conteudo != null) result.conteudo = conteudo;
    if (distancia != null) result.distancia = distancia;
    return result;
  }

  TrechoUsado._();

  factory TrechoUsado.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TrechoUsado.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TrechoUsado',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conteudo')
    ..aD(2, _omitFieldNames ? '' : 'distancia')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrechoUsado clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrechoUsado copyWith(void Function(TrechoUsado) updates) =>
      super.copyWith((message) => updates(message as TrechoUsado))
          as TrechoUsado;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TrechoUsado create() => TrechoUsado._();
  @$core.override
  TrechoUsado createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TrechoUsado getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TrechoUsado>(create);
  static TrechoUsado? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conteudo => $_getSZ(0);
  @$pb.TagNumber(1)
  set conteudo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConteudo() => $_has(0);
  @$pb.TagNumber(1)
  void clearConteudo() => $_clearField(1);

  /// Distancia de cosseno: quanto MENOR, mais parecido. Aparece na tela porque
  /// e o que explica por que um trecho entrou e outro nao.
  @$pb.TagNumber(2)
  $core.double get distancia => $_getN(1);
  @$pb.TagNumber(2)
  set distancia($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDistancia() => $_has(1);
  @$pb.TagNumber(2)
  void clearDistancia() => $_clearField(2);
}

class TestarPerguntaResponse extends $pb.GeneratedMessage {
  factory TestarPerguntaResponse({
    $core.String? resposta,
    $core.String? comportamentoAplicado,
    $core.Iterable<TrechoUsado>? trechos,
    $core.double? confiabilidade,
    $core.bool? transferiria,
    $core.String? fluxoTransferencia,
  }) {
    final result = create();
    if (resposta != null) result.resposta = resposta;
    if (comportamentoAplicado != null)
      result.comportamentoAplicado = comportamentoAplicado;
    if (trechos != null) result.trechos.addAll(trechos);
    if (confiabilidade != null) result.confiabilidade = confiabilidade;
    if (transferiria != null) result.transferiria = transferiria;
    if (fluxoTransferencia != null)
      result.fluxoTransferencia = fluxoTransferencia;
    return result;
  }

  TestarPerguntaResponse._();

  factory TestarPerguntaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TestarPerguntaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TestarPerguntaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'resposta')
    ..aOS(2, _omitFieldNames ? '' : 'comportamentoAplicado')
    ..pPM<TrechoUsado>(3, _omitFieldNames ? '' : 'trechos',
        subBuilder: TrechoUsado.create)
    ..aD(4, _omitFieldNames ? '' : 'confiabilidade')
    ..aOB(5, _omitFieldNames ? '' : 'transferiria')
    ..aOS(6, _omitFieldNames ? '' : 'fluxoTransferencia')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarPerguntaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TestarPerguntaResponse copyWith(
          void Function(TestarPerguntaResponse) updates) =>
      super.copyWith((message) => updates(message as TestarPerguntaResponse))
          as TestarPerguntaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TestarPerguntaResponse create() => TestarPerguntaResponse._();
  @$core.override
  TestarPerguntaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TestarPerguntaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TestarPerguntaResponse>(create);
  static TestarPerguntaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get resposta => $_getSZ(0);
  @$pb.TagNumber(1)
  set resposta($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResposta() => $_has(0);
  @$pb.TagNumber(1)
  void clearResposta() => $_clearField(1);

  /// Intencao que casou, se alguma. Vazio = nenhuma dentro do limiar.
  @$pb.TagNumber(2)
  $core.String get comportamentoAplicado => $_getSZ(1);
  @$pb.TagNumber(2)
  set comportamentoAplicado($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasComportamentoAplicado() => $_has(1);
  @$pb.TagNumber(2)
  void clearComportamentoAplicado() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<TrechoUsado> get trechos => $_getList(2);

  @$pb.TagNumber(4)
  $core.double get confiabilidade => $_getN(3);
  @$pb.TagNumber(4)
  set confiabilidade($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConfiabilidade() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiabilidade() => $_clearField(4);

  /// `true` quando a IA decidiu transferir em vez de responder.
  @$pb.TagNumber(5)
  $core.bool get transferiria => $_getBF(4);
  @$pb.TagNumber(5)
  set transferiria($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTransferiria() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransferiria() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get fluxoTransferencia => $_getSZ(5);
  @$pb.TagNumber(6)
  set fluxoTransferencia($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFluxoTransferencia() => $_has(5);
  @$pb.TagNumber(6)
  void clearFluxoTransferencia() => $_clearField(6);
}

/// B9 (N10 E6) - a avaliacao de um ensaio, com a resposta correta. E correcao
/// supervisionada: insumo de curadoria, nao um joinha.
class RegistrarFeedbackTesteRequest extends $pb.GeneratedMessage {
  factory RegistrarFeedbackTesteRequest({
    $core.String? pergunta,
    $core.String? respostaObtida,
    $core.String? respostaCorreta,
    $core.String? avaliacao,
    $core.String? comportamentoAplicado,
    $core.double? confiabilidade,
  }) {
    final result = create();
    if (pergunta != null) result.pergunta = pergunta;
    if (respostaObtida != null) result.respostaObtida = respostaObtida;
    if (respostaCorreta != null) result.respostaCorreta = respostaCorreta;
    if (avaliacao != null) result.avaliacao = avaliacao;
    if (comportamentoAplicado != null)
      result.comportamentoAplicado = comportamentoAplicado;
    if (confiabilidade != null) result.confiabilidade = confiabilidade;
    return result;
  }

  RegistrarFeedbackTesteRequest._();

  factory RegistrarFeedbackTesteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegistrarFeedbackTesteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegistrarFeedbackTesteRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'pergunta')
    ..aOS(2, _omitFieldNames ? '' : 'respostaObtida')
    ..aOS(3, _omitFieldNames ? '' : 'respostaCorreta')
    ..aOS(4, _omitFieldNames ? '' : 'avaliacao')
    ..aOS(5, _omitFieldNames ? '' : 'comportamentoAplicado')
    ..aD(6, _omitFieldNames ? '' : 'confiabilidade')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegistrarFeedbackTesteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegistrarFeedbackTesteRequest copyWith(
          void Function(RegistrarFeedbackTesteRequest) updates) =>
      super.copyWith(
              (message) => updates(message as RegistrarFeedbackTesteRequest))
          as RegistrarFeedbackTesteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegistrarFeedbackTesteRequest create() =>
      RegistrarFeedbackTesteRequest._();
  @$core.override
  RegistrarFeedbackTesteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegistrarFeedbackTesteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegistrarFeedbackTesteRequest>(create);
  static RegistrarFeedbackTesteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pergunta => $_getSZ(0);
  @$pb.TagNumber(1)
  set pergunta($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPergunta() => $_has(0);
  @$pb.TagNumber(1)
  void clearPergunta() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get respostaObtida => $_getSZ(1);
  @$pb.TagNumber(2)
  set respostaObtida($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRespostaObtida() => $_has(1);
  @$pb.TagNumber(2)
  void clearRespostaObtida() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get respostaCorreta => $_getSZ(2);
  @$pb.TagNumber(3)
  set respostaCorreta($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRespostaCorreta() => $_has(2);
  @$pb.TagNumber(3)
  void clearRespostaCorreta() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get avaliacao => $_getSZ(3);
  @$pb.TagNumber(4)
  set avaliacao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAvaliacao() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvaliacao() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get comportamentoAplicado => $_getSZ(4);
  @$pb.TagNumber(5)
  set comportamentoAplicado($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasComportamentoAplicado() => $_has(4);
  @$pb.TagNumber(5)
  void clearComportamentoAplicado() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get confiabilidade => $_getN(5);
  @$pb.TagNumber(6)
  set confiabilidade($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasConfiabilidade() => $_has(5);
  @$pb.TagNumber(6)
  void clearConfiabilidade() => $_clearField(6);
}

class RegistrarFeedbackTesteResponse extends $pb.GeneratedMessage {
  factory RegistrarFeedbackTesteResponse({
    $core.int? id,
  }) {
    final result = create();
    if (id != null) result.id = id;
    return result;
  }

  RegistrarFeedbackTesteResponse._();

  factory RegistrarFeedbackTesteResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegistrarFeedbackTesteResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegistrarFeedbackTesteResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'id')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegistrarFeedbackTesteResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegistrarFeedbackTesteResponse copyWith(
          void Function(RegistrarFeedbackTesteResponse) updates) =>
      super.copyWith(
              (message) => updates(message as RegistrarFeedbackTesteResponse))
          as RegistrarFeedbackTesteResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegistrarFeedbackTesteResponse create() =>
      RegistrarFeedbackTesteResponse._();
  @$core.override
  RegistrarFeedbackTesteResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegistrarFeedbackTesteResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegistrarFeedbackTesteResponse>(create);
  static RegistrarFeedbackTesteResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get id => $_getIZ(0);
  @$pb.TagNumber(1)
  set id($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);
}

class AtendimentoIdRequest extends $pb.GeneratedMessage {
  factory AtendimentoIdRequest({
    $core.int? atendimentoId,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    return result;
  }

  AtendimentoIdRequest._();

  factory AtendimentoIdRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AtendimentoIdRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AtendimentoIdRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoIdRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AtendimentoIdRequest copyWith(void Function(AtendimentoIdRequest) updates) =>
      super.copyWith((message) => updates(message as AtendimentoIdRequest))
          as AtendimentoIdRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AtendimentoIdRequest create() => AtendimentoIdRequest._();
  @$core.override
  AtendimentoIdRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AtendimentoIdRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AtendimentoIdRequest>(create);
  static AtendimentoIdRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);
}

class Etiqueta extends $pb.GeneratedMessage {
  factory Etiqueta({
    $fixnum.Int64? id,
    $core.String? nome,
    $core.String? cor,
    $core.String? descricao,
    $core.bool? ativo,
    $core.bool? aplicadaPelaIa,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (nome != null) result.nome = nome;
    if (cor != null) result.cor = cor;
    if (descricao != null) result.descricao = descricao;
    if (ativo != null) result.ativo = ativo;
    if (aplicadaPelaIa != null) result.aplicadaPelaIa = aplicadaPelaIa;
    return result;
  }

  Etiqueta._();

  factory Etiqueta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Etiqueta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Etiqueta',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'nome')
    ..aOS(3, _omitFieldNames ? '' : 'cor')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aOB(5, _omitFieldNames ? '' : 'ativo')
    ..aOB(6, _omitFieldNames ? '' : 'aplicadaPelaIa')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Etiqueta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Etiqueta copyWith(void Function(Etiqueta) updates) =>
      super.copyWith((message) => updates(message as Etiqueta)) as Etiqueta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Etiqueta create() => Etiqueta._();
  @$core.override
  Etiqueta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Etiqueta getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Etiqueta>(create);
  static Etiqueta? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
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

  @$pb.TagNumber(3)
  $core.String get cor => $_getSZ(2);
  @$pb.TagNumber(3)
  set cor($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCor() => $_has(2);
  @$pb.TagNumber(3)
  void clearCor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  /// Do CATALOGO. Uma etiqueta desativada continua aparecendo nas conversas em
  /// que ja estava -- sumir com ela reescreveria o passado.
  @$pb.TagNumber(5)
  $core.bool get ativo => $_getBF(4);
  @$pb.TagNumber(5)
  set ativo($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAtivo() => $_has(4);
  @$pb.TagNumber(5)
  void clearAtivo() => $_clearField(5);

  /// P14 — colocada pela IA a partir da intenção detectada. Só faz sentido nas
  /// etiquetas da conversa, não no catálogo.
  @$pb.TagNumber(6)
  $core.bool get aplicadaPelaIa => $_getBF(5);
  @$pb.TagNumber(6)
  set aplicadaPelaIa($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAplicadaPelaIa() => $_has(5);
  @$pb.TagNumber(6)
  void clearAplicadaPelaIa() => $_clearField(6);
}

class Nota extends $pb.GeneratedMessage {
  factory Nota({
    $fixnum.Int64? id,
    $core.String? texto,
    $fixnum.Int64? criadoEm,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (texto != null) result.texto = texto;
    if (criadoEm != null) result.criadoEm = criadoEm;
    return result;
  }

  Nota._();

  factory Nota.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Nota.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Nota',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'texto')
    ..aInt64(3, _omitFieldNames ? '' : 'criadoEm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Nota clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Nota copyWith(void Function(Nota) updates) =>
      super.copyWith((message) => updates(message as Nota)) as Nota;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Nota create() => Nota._();
  @$core.override
  Nota createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Nota getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Nota>(create);
  static Nota? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Texto livre do operador, interno: o contato nunca ve.
  @$pb.TagNumber(2)
  $core.String get texto => $_getSZ(1);
  @$pb.TagNumber(2)
  set texto($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTexto() => $_has(1);
  @$pb.TagNumber(2)
  void clearTexto() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get criadoEm => $_getI64(2);
  @$pb.TagNumber(3)
  set criadoEm($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCriadoEm() => $_has(2);
  @$pb.TagNumber(3)
  void clearCriadoEm() => $_clearField(3);
}

class DetalheAtendimentoResponse extends $pb.GeneratedMessage {
  factory DetalheAtendimentoResponse({
    $core.Iterable<Etiqueta>? catalogo,
    $core.Iterable<Etiqueta>? etiquetas,
    $core.Iterable<Nota>? notas,
    $core.bool? botPodeAtender,
    $core.Iterable<ValorCampoDoAtendimento>? campos,
  }) {
    final result = create();
    if (catalogo != null) result.catalogo.addAll(catalogo);
    if (etiquetas != null) result.etiquetas.addAll(etiquetas);
    if (notas != null) result.notas.addAll(notas);
    if (botPodeAtender != null) result.botPodeAtender = botPodeAtender;
    if (campos != null) result.campos.addAll(campos);
    return result;
  }

  DetalheAtendimentoResponse._();

  factory DetalheAtendimentoResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DetalheAtendimentoResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DetalheAtendimentoResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..pPM<Etiqueta>(1, _omitFieldNames ? '' : 'catalogo',
        subBuilder: Etiqueta.create)
    ..pPM<Etiqueta>(2, _omitFieldNames ? '' : 'etiquetas',
        subBuilder: Etiqueta.create)
    ..pPM<Nota>(3, _omitFieldNames ? '' : 'notas', subBuilder: Nota.create)
    ..aOB(4, _omitFieldNames ? '' : 'botPodeAtender')
    ..pPM<ValorCampoDoAtendimento>(5, _omitFieldNames ? '' : 'campos',
        subBuilder: ValorCampoDoAtendimento.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheAtendimentoResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DetalheAtendimentoResponse copyWith(
          void Function(DetalheAtendimentoResponse) updates) =>
      super.copyWith(
              (message) => updates(message as DetalheAtendimentoResponse))
          as DetalheAtendimentoResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DetalheAtendimentoResponse create() => DetalheAtendimentoResponse._();
  @$core.override
  DetalheAtendimentoResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DetalheAtendimentoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DetalheAtendimentoResponse>(create);
  static DetalheAtendimentoResponse? _defaultInstance;

  /// O que existe para escolher.
  @$pb.TagNumber(1)
  $pb.PbList<Etiqueta> get catalogo => $_getList(0);

  /// O que esta colado nesta conversa.
  @$pb.TagNumber(2)
  $pb.PbList<Etiqueta> get etiquetas => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<Nota> get notas => $_getList(2);

  /// D3 — a IA responde nesta conversa? Assumir o atendimento desliga; so o
  /// controle da ficha religa. Sem este campo a tela nao teria como saber em
  /// que estado esta o interruptor que ela mesma desenha.
  @$pb.TagNumber(4)
  $core.bool get botPodeAtender => $_getBF(3);
  @$pb.TagNumber(4)
  set botPodeAtender($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBotPodeAtender() => $_has(3);
  @$pb.TagNumber(4)
  void clearBotPodeAtender() => $_clearField(4);

  /// N9 E13 — os campos do cartao aplicaveis a este atendimento, ja com o
  /// valor quando ha. Vem juntos com o resto da ficha porque a tela os desenha
  /// no mesmo painel: buscar em duas chamadas faria metade da ficha aparecer
  /// antes da outra.
  @$pb.TagNumber(5)
  $pb.PbList<ValorCampoDoAtendimento> get campos => $_getList(4);
}

/// Um campo do cartao na ficha de UM atendimento: a definicao mais o valor.
class ValorCampoDoAtendimento extends $pb.GeneratedMessage {
  factory ValorCampoDoAtendimento({
    $fixnum.Int64? campoId,
    $core.String? slug,
    $core.String? nome,
    $core.String? descricao,
    $core.String? tipo,
    $core.Iterable<OpcaoCampo>? opcoes,
    $core.bool? obrigatorio,
    $core.String? valorJson,
    $core.String? origem,
    $core.double? confianca,
    $core.bool? editadoPorHumano,
  }) {
    final result = create();
    if (campoId != null) result.campoId = campoId;
    if (slug != null) result.slug = slug;
    if (nome != null) result.nome = nome;
    if (descricao != null) result.descricao = descricao;
    if (tipo != null) result.tipo = tipo;
    if (opcoes != null) result.opcoes.addAll(opcoes);
    if (obrigatorio != null) result.obrigatorio = obrigatorio;
    if (valorJson != null) result.valorJson = valorJson;
    if (origem != null) result.origem = origem;
    if (confianca != null) result.confianca = confianca;
    if (editadoPorHumano != null) result.editadoPorHumano = editadoPorHumano;
    return result;
  }

  ValorCampoDoAtendimento._();

  factory ValorCampoDoAtendimento.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ValorCampoDoAtendimento.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ValorCampoDoAtendimento',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'campoId')
    ..aOS(2, _omitFieldNames ? '' : 'slug')
    ..aOS(3, _omitFieldNames ? '' : 'nome')
    ..aOS(4, _omitFieldNames ? '' : 'descricao')
    ..aOS(5, _omitFieldNames ? '' : 'tipo')
    ..pPM<OpcaoCampo>(6, _omitFieldNames ? '' : 'opcoes',
        subBuilder: OpcaoCampo.create)
    ..aOB(7, _omitFieldNames ? '' : 'obrigatorio')
    ..aOS(8, _omitFieldNames ? '' : 'valorJson')
    ..aOS(9, _omitFieldNames ? '' : 'origem')
    ..aD(10, _omitFieldNames ? '' : 'confianca')
    ..aOB(11, _omitFieldNames ? '' : 'editadoPorHumano')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ValorCampoDoAtendimento clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ValorCampoDoAtendimento copyWith(
          void Function(ValorCampoDoAtendimento) updates) =>
      super.copyWith((message) => updates(message as ValorCampoDoAtendimento))
          as ValorCampoDoAtendimento;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ValorCampoDoAtendimento create() => ValorCampoDoAtendimento._();
  @$core.override
  ValorCampoDoAtendimento createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ValorCampoDoAtendimento getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ValorCampoDoAtendimento>(create);
  static ValorCampoDoAtendimento? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get campoId => $_getI64(0);
  @$pb.TagNumber(1)
  set campoId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCampoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCampoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get slug => $_getSZ(1);
  @$pb.TagNumber(2)
  set slug($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSlug() => $_has(1);
  @$pb.TagNumber(2)
  void clearSlug() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get nome => $_getSZ(2);
  @$pb.TagNumber(3)
  set nome($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNome() => $_has(2);
  @$pb.TagNumber(3)
  void clearNome() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get descricao => $_getSZ(3);
  @$pb.TagNumber(4)
  set descricao($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescricao() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescricao() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tipo => $_getSZ(4);
  @$pb.TagNumber(5)
  set tipo($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTipo() => $_has(4);
  @$pb.TagNumber(5)
  void clearTipo() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<OpcaoCampo> get opcoes => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get obrigatorio => $_getBF(6);
  @$pb.TagNumber(7)
  set obrigatorio($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasObrigatorio() => $_has(6);
  @$pb.TagNumber(7)
  void clearObrigatorio() => $_clearField(7);

  /// Vazio = nunca preenchido. `"null"` = apagado de proposito, e a IA nao
  /// repreenche o que alguem apagou.
  @$pb.TagNumber(8)
  $core.String get valorJson => $_getSZ(7);
  @$pb.TagNumber(8)
  set valorJson($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasValorJson() => $_has(7);
  @$pb.TagNumber(8)
  void clearValorJson() => $_clearField(8);

  /// MANUAL | IA — a tela mostra de onde veio, e a confianca quando foi a IA.
  @$pb.TagNumber(9)
  $core.String get origem => $_getSZ(8);
  @$pb.TagNumber(9)
  set origem($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOrigem() => $_has(8);
  @$pb.TagNumber(9)
  void clearOrigem() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.double get confianca => $_getN(9);
  @$pb.TagNumber(10)
  set confianca($core.double value) => $_setDouble(9, value);
  @$pb.TagNumber(10)
  $core.bool hasConfianca() => $_has(9);
  @$pb.TagNumber(10)
  void clearConfianca() => $_clearField(10);

  /// TRUE quando uma pessoa escreveu ou apagou: a IA nao sobrescreve.
  @$pb.TagNumber(11)
  $core.bool get editadoPorHumano => $_getBF(10);
  @$pb.TagNumber(11)
  set editadoPorHumano($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasEditadoPorHumano() => $_has(10);
  @$pb.TagNumber(11)
  void clearEditadoPorHumano() => $_clearField(11);
}

class CreateEtiquetaRequest extends $pb.GeneratedMessage {
  factory CreateEtiquetaRequest({
    $core.String? nome,
    $core.String? cor,
  }) {
    final result = create();
    if (nome != null) result.nome = nome;
    if (cor != null) result.cor = cor;
    return result;
  }

  CreateEtiquetaRequest._();

  factory CreateEtiquetaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateEtiquetaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateEtiquetaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nome')
    ..aOS(2, _omitFieldNames ? '' : 'cor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateEtiquetaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateEtiquetaRequest copyWith(
          void Function(CreateEtiquetaRequest) updates) =>
      super.copyWith((message) => updates(message as CreateEtiquetaRequest))
          as CreateEtiquetaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateEtiquetaRequest create() => CreateEtiquetaRequest._();
  @$core.override
  CreateEtiquetaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateEtiquetaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateEtiquetaRequest>(create);
  static CreateEtiquetaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nome => $_getSZ(0);
  @$pb.TagNumber(1)
  set nome($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNome() => $_has(0);
  @$pb.TagNumber(1)
  void clearNome() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get cor => $_getSZ(1);
  @$pb.TagNumber(2)
  set cor($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCor() => $_has(1);
  @$pb.TagNumber(2)
  void clearCor() => $_clearField(2);
}

class EtiquetaResponse extends $pb.GeneratedMessage {
  factory EtiquetaResponse({
    Etiqueta? etiqueta,
  }) {
    final result = create();
    if (etiqueta != null) result.etiqueta = etiqueta;
    return result;
  }

  EtiquetaResponse._();

  factory EtiquetaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EtiquetaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EtiquetaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Etiqueta>(1, _omitFieldNames ? '' : 'etiqueta',
        subBuilder: Etiqueta.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EtiquetaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EtiquetaResponse copyWith(void Function(EtiquetaResponse) updates) =>
      super.copyWith((message) => updates(message as EtiquetaResponse))
          as EtiquetaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EtiquetaResponse create() => EtiquetaResponse._();
  @$core.override
  EtiquetaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EtiquetaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EtiquetaResponse>(create);
  static EtiquetaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Etiqueta get etiqueta => $_getN(0);
  @$pb.TagNumber(1)
  set etiqueta(Etiqueta value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEtiqueta() => $_has(0);
  @$pb.TagNumber(1)
  void clearEtiqueta() => $_clearField(1);
  @$pb.TagNumber(1)
  Etiqueta ensureEtiqueta() => $_ensure(0);
}

class AlternarEtiquetaRequest extends $pb.GeneratedMessage {
  factory AlternarEtiquetaRequest({
    $core.int? atendimentoId,
    $fixnum.Int64? etiquetaId,
    $core.bool? aplicar,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (etiquetaId != null) result.etiquetaId = etiquetaId;
    if (aplicar != null) result.aplicar = aplicar;
    return result;
  }

  AlternarEtiquetaRequest._();

  factory AlternarEtiquetaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AlternarEtiquetaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AlternarEtiquetaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aInt64(2, _omitFieldNames ? '' : 'etiquetaId')
    ..aOB(3, _omitFieldNames ? '' : 'aplicar')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlternarEtiquetaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AlternarEtiquetaRequest copyWith(
          void Function(AlternarEtiquetaRequest) updates) =>
      super.copyWith((message) => updates(message as AlternarEtiquetaRequest))
          as AlternarEtiquetaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AlternarEtiquetaRequest create() => AlternarEtiquetaRequest._();
  @$core.override
  AlternarEtiquetaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AlternarEtiquetaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AlternarEtiquetaRequest>(create);
  static AlternarEtiquetaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get etiquetaId => $_getI64(1);
  @$pb.TagNumber(2)
  set etiquetaId($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEtiquetaId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEtiquetaId() => $_clearField(2);

  /// `false` tira a etiqueta da conversa.
  @$pb.TagNumber(3)
  $core.bool get aplicar => $_getBF(2);
  @$pb.TagNumber(3)
  set aplicar($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAplicar() => $_has(2);
  @$pb.TagNumber(3)
  void clearAplicar() => $_clearField(3);
}

class CreateNotaRequest extends $pb.GeneratedMessage {
  factory CreateNotaRequest({
    $core.int? atendimentoId,
    $core.String? texto,
  }) {
    final result = create();
    if (atendimentoId != null) result.atendimentoId = atendimentoId;
    if (texto != null) result.texto = texto;
    return result;
  }

  CreateNotaRequest._();

  factory CreateNotaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateNotaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateNotaRequest',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'atendimentoId')
    ..aOS(2, _omitFieldNames ? '' : 'texto')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateNotaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateNotaRequest copyWith(void Function(CreateNotaRequest) updates) =>
      super.copyWith((message) => updates(message as CreateNotaRequest))
          as CreateNotaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateNotaRequest create() => CreateNotaRequest._();
  @$core.override
  CreateNotaRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateNotaRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateNotaRequest>(create);
  static CreateNotaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get atendimentoId => $_getIZ(0);
  @$pb.TagNumber(1)
  set atendimentoId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAtendimentoId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAtendimentoId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get texto => $_getSZ(1);
  @$pb.TagNumber(2)
  set texto($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTexto() => $_has(1);
  @$pb.TagNumber(2)
  void clearTexto() => $_clearField(2);
}

class NotaResponse extends $pb.GeneratedMessage {
  factory NotaResponse({
    Nota? nota,
  }) {
    final result = create();
    if (nota != null) result.nota = nota;
    return result;
  }

  NotaResponse._();

  factory NotaResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NotaResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NotaResponse',
      package: const $pb.PackageName(
          _omitMessageNames ? '' : 'smartcore.contracts.queries'),
      createEmptyInstance: create)
    ..aOM<Nota>(1, _omitFieldNames ? '' : 'nota', subBuilder: Nota.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotaResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotaResponse copyWith(void Function(NotaResponse) updates) =>
      super.copyWith((message) => updates(message as NotaResponse))
          as NotaResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NotaResponse create() => NotaResponse._();
  @$core.override
  NotaResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NotaResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NotaResponse>(create);
  static NotaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  Nota get nota => $_getN(0);
  @$pb.TagNumber(1)
  set nota(Nota value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasNota() => $_has(0);
  @$pb.TagNumber(1)
  void clearNota() => $_clearField(1);
  @$pb.TagNumber(1)
  Nota ensureNota() => $_ensure(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
