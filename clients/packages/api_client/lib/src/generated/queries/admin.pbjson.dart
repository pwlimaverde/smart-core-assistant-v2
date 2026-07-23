// This is a generated file - do not edit.
//
// Generated from queries/admin.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use coreSettingDescriptor instead')
const CoreSetting$json = {
  '1': 'CoreSetting',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
    {'1': 'encrypted', '3': 3, '4': 1, '5': 8, '10': 'encrypted'},
    {'1': 'description', '3': 4, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `CoreSetting`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List coreSettingDescriptor = $convert.base64Decode(
    'CgtDb3JlU2V0dGluZxIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWUSHA'
    'oJZW5jcnlwdGVkGAMgASgIUgllbmNyeXB0ZWQSIAoLZGVzY3JpcHRpb24YBCABKAlSC2Rlc2Ny'
    'aXB0aW9u');

@$core.Deprecated('Use listCoreSettingsRequestDescriptor instead')
const ListCoreSettingsRequest$json = {
  '1': 'ListCoreSettingsRequest',
};

/// Descriptor for `ListCoreSettingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listCoreSettingsRequestDescriptor =
    $convert.base64Decode('ChdMaXN0Q29yZVNldHRpbmdzUmVxdWVzdA==');

@$core.Deprecated('Use listCoreSettingsResponseDescriptor instead')
const ListCoreSettingsResponse$json = {
  '1': 'ListCoreSettingsResponse',
  '2': [
    {
      '1': 'settings',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.CoreSetting',
      '10': 'settings'
    },
  ],
};

/// Descriptor for `ListCoreSettingsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listCoreSettingsResponseDescriptor =
    $convert.base64Decode(
        'ChhMaXN0Q29yZVNldHRpbmdzUmVzcG9uc2USRAoIc2V0dGluZ3MYASADKAsyKC5zbWFydGNvcm'
        'UuY29udHJhY3RzLnF1ZXJpZXMuQ29yZVNldHRpbmdSCHNldHRpbmdz');

@$core.Deprecated('Use upsertCoreSettingRequestDescriptor instead')
const UpsertCoreSettingRequest$json = {
  '1': 'UpsertCoreSettingRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
    {'1': 'encrypted', '3': 3, '4': 1, '5': 8, '10': 'encrypted'},
    {'1': 'description', '3': 4, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `UpsertCoreSettingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List upsertCoreSettingRequestDescriptor = $convert.base64Decode(
    'ChhVcHNlcnRDb3JlU2V0dGluZ1JlcXVlc3QSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAi'
    'ABKAlSBXZhbHVlEhwKCWVuY3J5cHRlZBgDIAEoCFIJZW5jcnlwdGVkEiAKC2Rlc2NyaXB0aW9u'
    'GAQgASgJUgtkZXNjcmlwdGlvbg==');

@$core.Deprecated('Use upsertCoreSettingResponseDescriptor instead')
const UpsertCoreSettingResponse$json = {
  '1': 'UpsertCoreSettingResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpsertCoreSettingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List upsertCoreSettingResponseDescriptor =
    $convert.base64Decode(
        'ChlVcHNlcnRDb3JlU2V0dGluZ1Jlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use deleteCoreSettingRequestDescriptor instead')
const DeleteCoreSettingRequest$json = {
  '1': 'DeleteCoreSettingRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
  ],
};

/// Descriptor for `DeleteCoreSettingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteCoreSettingRequestDescriptor =
    $convert.base64Decode(
        'ChhEZWxldGVDb3JlU2V0dGluZ1JlcXVlc3QSEAoDa2V5GAEgASgJUgNrZXk=');

@$core.Deprecated('Use deleteCoreSettingResponseDescriptor instead')
const DeleteCoreSettingResponse$json = {
  '1': 'DeleteCoreSettingResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `DeleteCoreSettingResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteCoreSettingResponseDescriptor =
    $convert.base64Decode(
        'ChlEZWxldGVDb3JlU2V0dGluZ1Jlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use apiKeyEntryDescriptor instead')
const ApiKeyEntry$json = {
  '1': 'ApiKeyEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
};

/// Descriptor for `ApiKeyEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List apiKeyEntryDescriptor = $convert.base64Decode(
    'CgtBcGlLZXlFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU=');

@$core.Deprecated('Use getTenantConfigRequestDescriptor instead')
const GetTenantConfigRequest$json = {
  '1': 'GetTenantConfigRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
  ],
};

/// Descriptor for `GetTenantConfigRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTenantConfigRequestDescriptor =
    $convert.base64Decode(
        'ChZHZXRUZW5hbnRDb25maWdSZXF1ZXN0EhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQ=');

@$core.Deprecated('Use getTenantConfigResponseDescriptor instead')
const GetTenantConfigResponse$json = {
  '1': 'GetTenantConfigResponse',
  '2': [
    {'1': 'dados_empresa', '3': 1, '4': 1, '5': 9, '10': 'dadosEmpresa'},
    {'1': 'persona_bot', '3': 2, '4': 1, '5': 9, '10': 'personaBot'},
    {'1': 'bot_agent_name', '3': 3, '4': 1, '5': 9, '10': 'botAgentName'},
    {'1': 'msg_fallback', '3': 4, '4': 1, '5': 9, '10': 'msgFallback'},
    {'1': 'msg_sem_info', '3': 5, '4': 1, '5': 9, '10': 'msgSemInfo'},
    {
      '1': 'msg_transferencia',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'msgTransferencia'
    },
    {'1': 'llm_class', '3': 7, '4': 1, '5': 9, '10': 'llmClass'},
    {'1': 'model', '3': 8, '4': 1, '5': 9, '10': 'model'},
    {'1': 'llm_temperature', '3': 9, '4': 1, '5': 9, '10': 'llmTemperature'},
    {
      '1': 'transcription_provider',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'transcriptionProvider'
    },
    {
      '1': 'transcription_model',
      '3': 11,
      '4': 1,
      '5': 9,
      '10': 'transcriptionModel'
    },
    {'1': 'vision_provider', '3': 12, '4': 1, '5': 9, '10': 'visionProvider'},
    {'1': 'vision_model', '3': 13, '4': 1, '5': 9, '10': 'visionModel'},
    {'1': 'embeddings_class', '3': 14, '4': 1, '5': 9, '10': 'embeddingsClass'},
    {'1': 'embeddings_model', '3': 15, '4': 1, '5': 9, '10': 'embeddingsModel'},
    {'1': 'chunk_size', '3': 16, '4': 1, '5': 5, '10': 'chunkSize'},
    {'1': 'chunk_overlap', '3': 17, '4': 1, '5': 5, '10': 'chunkOverlap'},
    {
      '1': 'similarity_threshold',
      '3': 18,
      '4': 1,
      '5': 9,
      '10': 'similarityThreshold'
    },
    {
      '1': 'vector_distance_threshold',
      '3': 19,
      '4': 1,
      '5': 9,
      '10': 'vectorDistanceThreshold'
    },
    {
      '1': 'api_keys',
      '3': 20,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.ApiKeyEntry',
      '10': 'apiKeys'
    },
  ],
};

/// Descriptor for `GetTenantConfigResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTenantConfigResponseDescriptor = $convert.base64Decode(
    'ChdHZXRUZW5hbnRDb25maWdSZXNwb25zZRIjCg1kYWRvc19lbXByZXNhGAEgASgJUgxkYWRvc0'
    'VtcHJlc2ESHwoLcGVyc29uYV9ib3QYAiABKAlSCnBlcnNvbmFCb3QSJAoOYm90X2FnZW50X25h'
    'bWUYAyABKAlSDGJvdEFnZW50TmFtZRIhCgxtc2dfZmFsbGJhY2sYBCABKAlSC21zZ0ZhbGxiYW'
    'NrEiAKDG1zZ19zZW1faW5mbxgFIAEoCVIKbXNnU2VtSW5mbxIrChFtc2dfdHJhbnNmZXJlbmNp'
    'YRgGIAEoCVIQbXNnVHJhbnNmZXJlbmNpYRIbCglsbG1fY2xhc3MYByABKAlSCGxsbUNsYXNzEh'
    'QKBW1vZGVsGAggASgJUgVtb2RlbBInCg9sbG1fdGVtcGVyYXR1cmUYCSABKAlSDmxsbVRlbXBl'
    'cmF0dXJlEjUKFnRyYW5zY3JpcHRpb25fcHJvdmlkZXIYCiABKAlSFXRyYW5zY3JpcHRpb25Qcm'
    '92aWRlchIvChN0cmFuc2NyaXB0aW9uX21vZGVsGAsgASgJUhJ0cmFuc2NyaXB0aW9uTW9kZWwS'
    'JwoPdmlzaW9uX3Byb3ZpZGVyGAwgASgJUg52aXNpb25Qcm92aWRlchIhCgx2aXNpb25fbW9kZW'
    'wYDSABKAlSC3Zpc2lvbk1vZGVsEikKEGVtYmVkZGluZ3NfY2xhc3MYDiABKAlSD2VtYmVkZGlu'
    'Z3NDbGFzcxIpChBlbWJlZGRpbmdzX21vZGVsGA8gASgJUg9lbWJlZGRpbmdzTW9kZWwSHQoKY2'
    'h1bmtfc2l6ZRgQIAEoBVIJY2h1bmtTaXplEiMKDWNodW5rX292ZXJsYXAYESABKAVSDGNodW5r'
    'T3ZlcmxhcBIxChRzaW1pbGFyaXR5X3RocmVzaG9sZBgSIAEoCVITc2ltaWxhcml0eVRocmVzaG'
    '9sZBI6Chl2ZWN0b3JfZGlzdGFuY2VfdGhyZXNob2xkGBMgASgJUhd2ZWN0b3JEaXN0YW5jZVRo'
    'cmVzaG9sZBJDCghhcGlfa2V5cxgUIAMoCzIoLnNtYXJ0Y29yZS5jb250cmFjdHMucXVlcmllcy'
    '5BcGlLZXlFbnRyeVIHYXBpS2V5cw==');

@$core.Deprecated('Use updateTenantConfigRequestDescriptor instead')
const UpdateTenantConfigRequest$json = {
  '1': 'UpdateTenantConfigRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'dados_empresa', '3': 2, '4': 1, '5': 9, '10': 'dadosEmpresa'},
    {'1': 'persona_bot', '3': 3, '4': 1, '5': 9, '10': 'personaBot'},
    {'1': 'bot_agent_name', '3': 4, '4': 1, '5': 9, '10': 'botAgentName'},
    {'1': 'msg_fallback', '3': 5, '4': 1, '5': 9, '10': 'msgFallback'},
    {'1': 'msg_sem_info', '3': 6, '4': 1, '5': 9, '10': 'msgSemInfo'},
    {
      '1': 'msg_transferencia',
      '3': 7,
      '4': 1,
      '5': 9,
      '10': 'msgTransferencia'
    },
    {'1': 'llm_class', '3': 8, '4': 1, '5': 9, '10': 'llmClass'},
    {'1': 'model', '3': 9, '4': 1, '5': 9, '10': 'model'},
    {'1': 'llm_temperature', '3': 10, '4': 1, '5': 9, '10': 'llmTemperature'},
    {
      '1': 'transcription_provider',
      '3': 11,
      '4': 1,
      '5': 9,
      '10': 'transcriptionProvider'
    },
    {
      '1': 'transcription_model',
      '3': 12,
      '4': 1,
      '5': 9,
      '10': 'transcriptionModel'
    },
    {'1': 'vision_provider', '3': 13, '4': 1, '5': 9, '10': 'visionProvider'},
    {'1': 'vision_model', '3': 14, '4': 1, '5': 9, '10': 'visionModel'},
    {'1': 'embeddings_class', '3': 15, '4': 1, '5': 9, '10': 'embeddingsClass'},
    {'1': 'embeddings_model', '3': 16, '4': 1, '5': 9, '10': 'embeddingsModel'},
    {'1': 'chunk_size', '3': 17, '4': 1, '5': 5, '10': 'chunkSize'},
    {'1': 'chunk_overlap', '3': 18, '4': 1, '5': 5, '10': 'chunkOverlap'},
    {
      '1': 'similarity_threshold',
      '3': 19,
      '4': 1,
      '5': 9,
      '10': 'similarityThreshold'
    },
    {
      '1': 'vector_distance_threshold',
      '3': 20,
      '4': 1,
      '5': 9,
      '10': 'vectorDistanceThreshold'
    },
    {
      '1': 'api_keys',
      '3': 21,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.ApiKeyEntry',
      '10': 'apiKeys'
    },
  ],
};

/// Descriptor for `UpdateTenantConfigRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantConfigRequestDescriptor = $convert.base64Decode(
    'ChlVcGRhdGVUZW5hbnRDb25maWdSZXF1ZXN0EhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SW'
    'QSIwoNZGFkb3NfZW1wcmVzYRgCIAEoCVIMZGFkb3NFbXByZXNhEh8KC3BlcnNvbmFfYm90GAMg'
    'ASgJUgpwZXJzb25hQm90EiQKDmJvdF9hZ2VudF9uYW1lGAQgASgJUgxib3RBZ2VudE5hbWUSIQ'
    'oMbXNnX2ZhbGxiYWNrGAUgASgJUgttc2dGYWxsYmFjaxIgCgxtc2dfc2VtX2luZm8YBiABKAlS'
    'Cm1zZ1NlbUluZm8SKwoRbXNnX3RyYW5zZmVyZW5jaWEYByABKAlSEG1zZ1RyYW5zZmVyZW5jaW'
    'ESGwoJbGxtX2NsYXNzGAggASgJUghsbG1DbGFzcxIUCgVtb2RlbBgJIAEoCVIFbW9kZWwSJwoP'
    'bGxtX3RlbXBlcmF0dXJlGAogASgJUg5sbG1UZW1wZXJhdHVyZRI1ChZ0cmFuc2NyaXB0aW9uX3'
    'Byb3ZpZGVyGAsgASgJUhV0cmFuc2NyaXB0aW9uUHJvdmlkZXISLwoTdHJhbnNjcmlwdGlvbl9t'
    'b2RlbBgMIAEoCVISdHJhbnNjcmlwdGlvbk1vZGVsEicKD3Zpc2lvbl9wcm92aWRlchgNIAEoCV'
    'IOdmlzaW9uUHJvdmlkZXISIQoMdmlzaW9uX21vZGVsGA4gASgJUgt2aXNpb25Nb2RlbBIpChBl'
    'bWJlZGRpbmdzX2NsYXNzGA8gASgJUg9lbWJlZGRpbmdzQ2xhc3MSKQoQZW1iZWRkaW5nc19tb2'
    'RlbBgQIAEoCVIPZW1iZWRkaW5nc01vZGVsEh0KCmNodW5rX3NpemUYESABKAVSCWNodW5rU2l6'
    'ZRIjCg1jaHVua19vdmVybGFwGBIgASgFUgxjaHVua092ZXJsYXASMQoUc2ltaWxhcml0eV90aH'
    'Jlc2hvbGQYEyABKAlSE3NpbWlsYXJpdHlUaHJlc2hvbGQSOgoZdmVjdG9yX2Rpc3RhbmNlX3Ro'
    'cmVzaG9sZBgUIAEoCVIXdmVjdG9yRGlzdGFuY2VUaHJlc2hvbGQSQwoIYXBpX2tleXMYFSADKA'
    'syKC5zbWFydGNvcmUuY29udHJhY3RzLnF1ZXJpZXMuQXBpS2V5RW50cnlSB2FwaUtleXM=');

@$core.Deprecated('Use updateTenantConfigResponseDescriptor instead')
const UpdateTenantConfigResponse$json = {
  '1': 'UpdateTenantConfigResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpdateTenantConfigResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantConfigResponseDescriptor =
    $convert.base64Decode(
        'ChpVcGRhdGVUZW5hbnRDb25maWdSZXNwb25zZRIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNz');

@$core.Deprecated('Use tenantDescriptor instead')
const Tenant$json = {
  '1': 'Tenant',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'slug', '3': 3, '4': 1, '5': 9, '10': 'slug'},
    {'1': 'api_key', '3': 4, '4': 1, '5': 9, '10': 'apiKey'},
    {'1': 'owner_id', '3': 5, '4': 1, '5': 5, '10': 'ownerId'},
    {'1': 'email', '3': 6, '4': 1, '5': 9, '10': 'email'},
    {'1': 'phone', '3': 7, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'active', '3': 8, '4': 1, '5': 8, '10': 'active'},
    {'1': 'setup_completed', '3': 9, '4': 1, '5': 8, '10': 'setupCompleted'},
    {'1': 'onboarding_step', '3': 10, '4': 1, '5': 5, '10': 'onboardingStep'},
    {'1': 'access_code', '3': 11, '4': 1, '5': 9, '10': 'accessCode'},
    {'1': 'created_at', '3': 12, '4': 1, '5': 3, '10': 'createdAt'},
    {'1': 'updated_at', '3': 13, '4': 1, '5': 3, '10': 'updatedAt'},
  ],
};

/// Descriptor for `Tenant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tenantDescriptor = $convert.base64Decode(
    'CgZUZW5hbnQSDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWUSEgoEc2x1ZxgDIA'
    'EoCVIEc2x1ZxIXCgdhcGlfa2V5GAQgASgJUgZhcGlLZXkSGQoIb3duZXJfaWQYBSABKAVSB293'
    'bmVySWQSFAoFZW1haWwYBiABKAlSBWVtYWlsEhQKBXBob25lGAcgASgJUgVwaG9uZRIWCgZhY3'
    'RpdmUYCCABKAhSBmFjdGl2ZRInCg9zZXR1cF9jb21wbGV0ZWQYCSABKAhSDnNldHVwQ29tcGxl'
    'dGVkEicKD29uYm9hcmRpbmdfc3RlcBgKIAEoBVIOb25ib2FyZGluZ1N0ZXASHwoLYWNjZXNzX2'
    'NvZGUYCyABKAlSCmFjY2Vzc0NvZGUSHQoKY3JlYXRlZF9hdBgMIAEoA1IJY3JlYXRlZEF0Eh0K'
    'CnVwZGF0ZWRfYXQYDSABKANSCXVwZGF0ZWRBdA==');

@$core.Deprecated('Use planDescriptor instead')
const Plan$json = {
  '1': 'Plan',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'price', '3': 4, '4': 1, '5': 9, '10': 'price'},
    {'1': 'max_instances', '3': 5, '4': 1, '5': 5, '10': 'maxInstances'},
    {'1': 'max_departments', '3': 6, '4': 1, '5': 5, '10': 'maxDepartments'},
    {'1': 'active', '3': 7, '4': 1, '5': 8, '10': 'active'},
    {'1': 'created_at', '3': 8, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `Plan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planDescriptor = $convert.base64Decode(
    'CgRQbGFuEg4KAmlkGAEgASgFUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW'
    '9uGAMgASgJUgtkZXNjcmlwdGlvbhIUCgVwcmljZRgEIAEoCVIFcHJpY2USIwoNbWF4X2luc3Rh'
    'bmNlcxgFIAEoBVIMbWF4SW5zdGFuY2VzEicKD21heF9kZXBhcnRtZW50cxgGIAEoBVIObWF4RG'
    'VwYXJ0bWVudHMSFgoGYWN0aXZlGAcgASgIUgZhY3RpdmUSHQoKY3JlYXRlZF9hdBgIIAEoA1IJ'
    'Y3JlYXRlZEF0');

@$core.Deprecated('Use subscriptionDescriptor instead')
const Subscription$json = {
  '1': 'Subscription',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'tenant_id', '3': 2, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'plan_id', '3': 3, '4': 1, '5': 5, '10': 'planId'},
    {'1': 'status', '3': 4, '4': 1, '5': 9, '10': 'status'},
    {
      '1': 'current_period_start',
      '3': 5,
      '4': 1,
      '5': 3,
      '10': 'currentPeriodStart'
    },
    {
      '1': 'current_period_end',
      '3': 6,
      '4': 1,
      '5': 3,
      '10': 'currentPeriodEnd'
    },
    {'1': 'payment_gateway', '3': 7, '4': 1, '5': 9, '10': 'paymentGateway'},
    {
      '1': 'external_customer_id',
      '3': 8,
      '4': 1,
      '5': 9,
      '10': 'externalCustomerId'
    },
    {
      '1': 'external_subscription_id',
      '3': 9,
      '4': 1,
      '5': 9,
      '10': 'externalSubscriptionId'
    },
    {'1': 'updated_at', '3': 10, '4': 1, '5': 3, '10': 'updatedAt'},
  ],
};

/// Descriptor for `Subscription`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscriptionDescriptor = $convert.base64Decode(
    'CgxTdWJzY3JpcHRpb24SDgoCaWQYASABKAVSAmlkEhsKCXRlbmFudF9pZBgCIAEoCVIIdGVuYW'
    '50SWQSFwoHcGxhbl9pZBgDIAEoBVIGcGxhbklkEhYKBnN0YXR1cxgEIAEoCVIGc3RhdHVzEjAK'
    'FGN1cnJlbnRfcGVyaW9kX3N0YXJ0GAUgASgDUhJjdXJyZW50UGVyaW9kU3RhcnQSLAoSY3Vycm'
    'VudF9wZXJpb2RfZW5kGAYgASgDUhBjdXJyZW50UGVyaW9kRW5kEicKD3BheW1lbnRfZ2F0ZXdh'
    'eRgHIAEoCVIOcGF5bWVudEdhdGV3YXkSMAoUZXh0ZXJuYWxfY3VzdG9tZXJfaWQYCCABKAlSEm'
    'V4dGVybmFsQ3VzdG9tZXJJZBI4ChhleHRlcm5hbF9zdWJzY3JpcHRpb25faWQYCSABKAlSFmV4'
    'dGVybmFsU3Vic2NyaXB0aW9uSWQSHQoKdXBkYXRlZF9hdBgKIAEoA1IJdXBkYXRlZEF0');

@$core.Deprecated('Use paymentRecordDescriptor instead')
const PaymentRecord$json = {
  '1': 'PaymentRecord',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'tenant_id', '3': 2, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'amount', '3': 3, '4': 1, '5': 9, '10': 'amount'},
    {'1': 'payment_date', '3': 4, '4': 1, '5': 9, '10': 'paymentDate'},
    {'1': 'payment_method', '3': 5, '4': 1, '5': 9, '10': 'paymentMethod'},
    {'1': 'period_start', '3': 6, '4': 1, '5': 9, '10': 'periodStart'},
    {'1': 'period_end', '3': 7, '4': 1, '5': 9, '10': 'periodEnd'},
    {'1': 'notes', '3': 8, '4': 1, '5': 9, '10': 'notes'},
    {'1': 'recorded_by_id', '3': 9, '4': 1, '5': 5, '10': 'recordedById'},
    {'1': 'created_at', '3': 10, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `PaymentRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paymentRecordDescriptor = $convert.base64Decode(
    'Cg1QYXltZW50UmVjb3JkEg4KAmlkGAEgASgFUgJpZBIbCgl0ZW5hbnRfaWQYAiABKAlSCHRlbm'
    'FudElkEhYKBmFtb3VudBgDIAEoCVIGYW1vdW50EiEKDHBheW1lbnRfZGF0ZRgEIAEoCVILcGF5'
    'bWVudERhdGUSJQoOcGF5bWVudF9tZXRob2QYBSABKAlSDXBheW1lbnRNZXRob2QSIQoMcGVyaW'
    '9kX3N0YXJ0GAYgASgJUgtwZXJpb2RTdGFydBIdCgpwZXJpb2RfZW5kGAcgASgJUglwZXJpb2RF'
    'bmQSFAoFbm90ZXMYCCABKAlSBW5vdGVzEiQKDnJlY29yZGVkX2J5X2lkGAkgASgFUgxyZWNvcm'
    'RlZEJ5SWQSHQoKY3JlYXRlZF9hdBgKIAEoA1IJY3JlYXRlZEF0');

@$core.Deprecated('Use listTenantsRequestDescriptor instead')
const ListTenantsRequest$json = {
  '1': 'ListTenantsRequest',
};

/// Descriptor for `ListTenantsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTenantsRequestDescriptor =
    $convert.base64Decode('ChJMaXN0VGVuYW50c1JlcXVlc3Q=');

@$core.Deprecated('Use listTenantsResponseDescriptor instead')
const ListTenantsResponse$json = {
  '1': 'ListTenantsResponse',
  '2': [
    {
      '1': 'tenants',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.Tenant',
      '10': 'tenants'
    },
  ],
};

/// Descriptor for `ListTenantsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTenantsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0VGVuYW50c1Jlc3BvbnNlEj0KB3RlbmFudHMYASADKAsyIy5zbWFydGNvcmUuY29udH'
    'JhY3RzLnF1ZXJpZXMuVGVuYW50Ugd0ZW5hbnRz');

@$core.Deprecated('Use getTenantRequestDescriptor instead')
const GetTenantRequest$json = {
  '1': 'GetTenantRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `GetTenantRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTenantRequestDescriptor =
    $convert.base64Decode('ChBHZXRUZW5hbnRSZXF1ZXN0Eg4KAmlkGAEgASgJUgJpZA==');

@$core.Deprecated('Use getTenantResponseDescriptor instead')
const GetTenantResponse$json = {
  '1': 'GetTenantResponse',
  '2': [
    {
      '1': 'tenant',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.Tenant',
      '10': 'tenant'
    },
  ],
};

/// Descriptor for `GetTenantResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getTenantResponseDescriptor = $convert.base64Decode(
    'ChFHZXRUZW5hbnRSZXNwb25zZRI7CgZ0ZW5hbnQYASABKAsyIy5zbWFydGNvcmUuY29udHJhY3'
    'RzLnF1ZXJpZXMuVGVuYW50UgZ0ZW5hbnQ=');

@$core.Deprecated('Use createTenantRequestDescriptor instead')
const CreateTenantRequest$json = {
  '1': 'CreateTenantRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'slug', '3': 2, '4': 1, '5': 9, '10': 'slug'},
    {'1': 'owner_id', '3': 3, '4': 1, '5': 5, '10': 'ownerId'},
    {'1': 'email', '3': 4, '4': 1, '5': 9, '10': 'email'},
    {'1': 'phone', '3': 5, '4': 1, '5': 9, '10': 'phone'},
  ],
};

/// Descriptor for `CreateTenantRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createTenantRequestDescriptor = $convert.base64Decode(
    'ChNDcmVhdGVUZW5hbnRSZXF1ZXN0EhIKBG5hbWUYASABKAlSBG5hbWUSEgoEc2x1ZxgCIAEoCV'
    'IEc2x1ZxIZCghvd25lcl9pZBgDIAEoBVIHb3duZXJJZBIUCgVlbWFpbBgEIAEoCVIFZW1haWwS'
    'FAoFcGhvbmUYBSABKAlSBXBob25l');

@$core.Deprecated('Use createTenantResponseDescriptor instead')
const CreateTenantResponse$json = {
  '1': 'CreateTenantResponse',
  '2': [
    {
      '1': 'tenant',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.Tenant',
      '10': 'tenant'
    },
  ],
};

/// Descriptor for `CreateTenantResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createTenantResponseDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVUZW5hbnRSZXNwb25zZRI7CgZ0ZW5hbnQYASABKAsyIy5zbWFydGNvcmUuY29udH'
    'JhY3RzLnF1ZXJpZXMuVGVuYW50UgZ0ZW5hbnQ=');

@$core.Deprecated('Use updateTenantRequestDescriptor instead')
const UpdateTenantRequest$json = {
  '1': 'UpdateTenantRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'slug', '3': 3, '4': 1, '5': 9, '10': 'slug'},
    {'1': 'owner_id', '3': 4, '4': 1, '5': 5, '10': 'ownerId'},
    {'1': 'email', '3': 5, '4': 1, '5': 9, '10': 'email'},
    {'1': 'phone', '3': 6, '4': 1, '5': 9, '10': 'phone'},
  ],
};

/// Descriptor for `UpdateTenantRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantRequestDescriptor = $convert.base64Decode(
    'ChNVcGRhdGVUZW5hbnRSZXF1ZXN0Eg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW'
    '1lEhIKBHNsdWcYAyABKAlSBHNsdWcSGQoIb3duZXJfaWQYBCABKAVSB293bmVySWQSFAoFZW1h'
    'aWwYBSABKAlSBWVtYWlsEhQKBXBob25lGAYgASgJUgVwaG9uZQ==');

@$core.Deprecated('Use updateTenantResponseDescriptor instead')
const UpdateTenantResponse$json = {
  '1': 'UpdateTenantResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpdateTenantResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantResponseDescriptor =
    $convert.base64Decode(
        'ChRVcGRhdGVUZW5hbnRSZXNwb25zZRIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNz');

@$core.Deprecated('Use setTenantActiveRequestDescriptor instead')
const SetTenantActiveRequest$json = {
  '1': 'SetTenantActiveRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'active', '3': 2, '4': 1, '5': 8, '10': 'active'},
  ],
};

/// Descriptor for `SetTenantActiveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setTenantActiveRequestDescriptor =
    $convert.base64Decode(
        'ChZTZXRUZW5hbnRBY3RpdmVSZXF1ZXN0Eg4KAmlkGAEgASgJUgJpZBIWCgZhY3RpdmUYAiABKA'
        'hSBmFjdGl2ZQ==');

@$core.Deprecated('Use setTenantActiveResponseDescriptor instead')
const SetTenantActiveResponse$json = {
  '1': 'SetTenantActiveResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `SetTenantActiveResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setTenantActiveResponseDescriptor =
    $convert.base64Decode(
        'ChdTZXRUZW5hbnRBY3RpdmVSZXNwb25zZRIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNz');

@$core.Deprecated('Use generateAccessCodeRequestDescriptor instead')
const GenerateAccessCodeRequest$json = {
  '1': 'GenerateAccessCodeRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
  ],
};

/// Descriptor for `GenerateAccessCodeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generateAccessCodeRequestDescriptor =
    $convert.base64Decode(
        'ChlHZW5lcmF0ZUFjY2Vzc0NvZGVSZXF1ZXN0Eg4KAmlkGAEgASgJUgJpZA==');

@$core.Deprecated('Use generateAccessCodeResponseDescriptor instead')
const GenerateAccessCodeResponse$json = {
  '1': 'GenerateAccessCodeResponse',
  '2': [
    {'1': 'access_code', '3': 1, '4': 1, '5': 9, '10': 'accessCode'},
  ],
};

/// Descriptor for `GenerateAccessCodeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generateAccessCodeResponseDescriptor =
    $convert.base64Decode(
        'ChpHZW5lcmF0ZUFjY2Vzc0NvZGVSZXNwb25zZRIfCgthY2Nlc3NfY29kZRgBIAEoCVIKYWNjZX'
        'NzQ29kZQ==');

@$core.Deprecated('Use listPlansRequestDescriptor instead')
const ListPlansRequest$json = {
  '1': 'ListPlansRequest',
};

/// Descriptor for `ListPlansRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPlansRequestDescriptor =
    $convert.base64Decode('ChBMaXN0UGxhbnNSZXF1ZXN0');

@$core.Deprecated('Use listPlansResponseDescriptor instead')
const ListPlansResponse$json = {
  '1': 'ListPlansResponse',
  '2': [
    {
      '1': 'plans',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.Plan',
      '10': 'plans'
    },
  ],
};

/// Descriptor for `ListPlansResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPlansResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0UGxhbnNSZXNwb25zZRI3CgVwbGFucxgBIAMoCzIhLnNtYXJ0Y29yZS5jb250cmFjdH'
    'MucXVlcmllcy5QbGFuUgVwbGFucw==');

@$core.Deprecated('Use createPlanRequestDescriptor instead')
const CreatePlanRequest$json = {
  '1': 'CreatePlanRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'price', '3': 3, '4': 1, '5': 9, '10': 'price'},
    {'1': 'max_instances', '3': 4, '4': 1, '5': 5, '10': 'maxInstances'},
    {'1': 'max_departments', '3': 5, '4': 1, '5': 5, '10': 'maxDepartments'},
  ],
};

/// Descriptor for `CreatePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createPlanRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVQbGFuUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGA'
    'IgASgJUgtkZXNjcmlwdGlvbhIUCgVwcmljZRgDIAEoCVIFcHJpY2USIwoNbWF4X2luc3RhbmNl'
    'cxgEIAEoBVIMbWF4SW5zdGFuY2VzEicKD21heF9kZXBhcnRtZW50cxgFIAEoBVIObWF4RGVwYX'
    'J0bWVudHM=');

@$core.Deprecated('Use createPlanResponseDescriptor instead')
const CreatePlanResponse$json = {
  '1': 'CreatePlanResponse',
  '2': [
    {
      '1': 'plan',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.Plan',
      '10': 'plan'
    },
  ],
};

/// Descriptor for `CreatePlanResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createPlanResponseDescriptor = $convert.base64Decode(
    'ChJDcmVhdGVQbGFuUmVzcG9uc2USNQoEcGxhbhgBIAEoCzIhLnNtYXJ0Y29yZS5jb250cmFjdH'
    'MucXVlcmllcy5QbGFuUgRwbGFu');

@$core.Deprecated('Use updatePlanRequestDescriptor instead')
const UpdatePlanRequest$json = {
  '1': 'UpdatePlanRequest',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'price', '3': 4, '4': 1, '5': 9, '10': 'price'},
    {'1': 'max_instances', '3': 5, '4': 1, '5': 5, '10': 'maxInstances'},
    {'1': 'max_departments', '3': 6, '4': 1, '5': 5, '10': 'maxDepartments'},
    {'1': 'active', '3': 7, '4': 1, '5': 8, '10': 'active'},
  ],
};

/// Descriptor for `UpdatePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updatePlanRequestDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVQbGFuUmVxdWVzdBIOCgJpZBgBIAEoBVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZR'
    'IgCgtkZXNjcmlwdGlvbhgDIAEoCVILZGVzY3JpcHRpb24SFAoFcHJpY2UYBCABKAlSBXByaWNl'
    'EiMKDW1heF9pbnN0YW5jZXMYBSABKAVSDG1heEluc3RhbmNlcxInCg9tYXhfZGVwYXJ0bWVudH'
    'MYBiABKAVSDm1heERlcGFydG1lbnRzEhYKBmFjdGl2ZRgHIAEoCFIGYWN0aXZl');

@$core.Deprecated('Use updatePlanResponseDescriptor instead')
const UpdatePlanResponse$json = {
  '1': 'UpdatePlanResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpdatePlanResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updatePlanResponseDescriptor =
    $convert.base64Decode(
        'ChJVcGRhdGVQbGFuUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2Vzcw==');

@$core.Deprecated('Use listSubscriptionsRequestDescriptor instead')
const ListSubscriptionsRequest$json = {
  '1': 'ListSubscriptionsRequest',
};

/// Descriptor for `ListSubscriptionsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSubscriptionsRequestDescriptor =
    $convert.base64Decode('ChhMaXN0U3Vic2NyaXB0aW9uc1JlcXVlc3Q=');

@$core.Deprecated('Use listSubscriptionsResponseDescriptor instead')
const ListSubscriptionsResponse$json = {
  '1': 'ListSubscriptionsResponse',
  '2': [
    {
      '1': 'subscriptions',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.Subscription',
      '10': 'subscriptions'
    },
  ],
};

/// Descriptor for `ListSubscriptionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listSubscriptionsResponseDescriptor =
    $convert.base64Decode(
        'ChlMaXN0U3Vic2NyaXB0aW9uc1Jlc3BvbnNlEk8KDXN1YnNjcmlwdGlvbnMYASADKAsyKS5zbW'
        'FydGNvcmUuY29udHJhY3RzLnF1ZXJpZXMuU3Vic2NyaXB0aW9uUg1zdWJzY3JpcHRpb25z');

@$core.Deprecated('Use registerPaymentRequestDescriptor instead')
const RegisterPaymentRequest$json = {
  '1': 'RegisterPaymentRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'amount', '3': 2, '4': 1, '5': 9, '10': 'amount'},
    {'1': 'payment_method', '3': 3, '4': 1, '5': 9, '10': 'paymentMethod'},
    {'1': 'payment_date', '3': 4, '4': 1, '5': 9, '10': 'paymentDate'},
    {'1': 'period_start', '3': 5, '4': 1, '5': 9, '10': 'periodStart'},
    {'1': 'period_end', '3': 6, '4': 1, '5': 9, '10': 'periodEnd'},
    {'1': 'notes', '3': 7, '4': 1, '5': 9, '10': 'notes'},
  ],
};

/// Descriptor for `RegisterPaymentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerPaymentRequestDescriptor = $convert.base64Decode(
    'ChZSZWdpc3RlclBheW1lbnRSZXF1ZXN0EhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQSFg'
    'oGYW1vdW50GAIgASgJUgZhbW91bnQSJQoOcGF5bWVudF9tZXRob2QYAyABKAlSDXBheW1lbnRN'
    'ZXRob2QSIQoMcGF5bWVudF9kYXRlGAQgASgJUgtwYXltZW50RGF0ZRIhCgxwZXJpb2Rfc3Rhcn'
    'QYBSABKAlSC3BlcmlvZFN0YXJ0Eh0KCnBlcmlvZF9lbmQYBiABKAlSCXBlcmlvZEVuZBIUCgVu'
    'b3RlcxgHIAEoCVIFbm90ZXM=');

@$core.Deprecated('Use registerPaymentResponseDescriptor instead')
const RegisterPaymentResponse$json = {
  '1': 'RegisterPaymentResponse',
  '2': [
    {
      '1': 'payment',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.PaymentRecord',
      '10': 'payment'
    },
  ],
};

/// Descriptor for `RegisterPaymentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerPaymentResponseDescriptor =
    $convert.base64Decode(
        'ChdSZWdpc3RlclBheW1lbnRSZXNwb25zZRJECgdwYXltZW50GAEgASgLMiouc21hcnRjb3JlLm'
        'NvbnRyYWN0cy5xdWVyaWVzLlBheW1lbnRSZWNvcmRSB3BheW1lbnQ=');

@$core.Deprecated('Use listPaymentsRequestDescriptor instead')
const ListPaymentsRequest$json = {
  '1': 'ListPaymentsRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
  ],
};

/// Descriptor for `ListPaymentsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPaymentsRequestDescriptor =
    $convert.base64Decode(
        'ChNMaXN0UGF5bWVudHNSZXF1ZXN0EhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQ=');

@$core.Deprecated('Use listPaymentsResponseDescriptor instead')
const ListPaymentsResponse$json = {
  '1': 'ListPaymentsResponse',
  '2': [
    {
      '1': 'payments',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.PaymentRecord',
      '10': 'payments'
    },
  ],
};

/// Descriptor for `ListPaymentsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPaymentsResponseDescriptor = $convert.base64Decode(
    'ChRMaXN0UGF5bWVudHNSZXNwb25zZRJGCghwYXltZW50cxgBIAMoCzIqLnNtYXJ0Y29yZS5jb2'
    '50cmFjdHMucXVlcmllcy5QYXltZW50UmVjb3JkUghwYXltZW50cw==');

@$core.Deprecated('Use testEvolutionConnectionRequestDescriptor instead')
const TestEvolutionConnectionRequest$json = {
  '1': 'TestEvolutionConnectionRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
  ],
};

/// Descriptor for `TestEvolutionConnectionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List testEvolutionConnectionRequestDescriptor =
    $convert.base64Decode(
        'Ch5UZXN0RXZvbHV0aW9uQ29ubmVjdGlvblJlcXVlc3QSGwoJdGVuYW50X2lkGAEgASgJUgh0ZW'
        '5hbnRJZA==');

@$core.Deprecated('Use testEvolutionConnectionResponseDescriptor instead')
const TestEvolutionConnectionResponse$json = {
  '1': 'TestEvolutionConnectionResponse',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
    {'1': 'error_message', '3': 2, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `TestEvolutionConnectionResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List testEvolutionConnectionResponseDescriptor =
    $convert.base64Decode(
        'Ch9UZXN0RXZvbHV0aW9uQ29ubmVjdGlvblJlc3BvbnNlEhYKBnN0YXR1cxgBIAEoCVIGc3RhdH'
        'VzEiMKDWVycm9yX21lc3NhZ2UYAiABKAlSDGVycm9yTWVzc2FnZQ==');

@$core.Deprecated('Use featureFlagOverrideDescriptor instead')
const FeatureFlagOverride$json = {
  '1': 'FeatureFlagOverride',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'enabled', '3': 2, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `FeatureFlagOverride`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List featureFlagOverrideDescriptor = $convert.base64Decode(
    'ChNGZWF0dXJlRmxhZ092ZXJyaWRlEhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQSGAoHZW'
    '5hYmxlZBgCIAEoCFIHZW5hYmxlZA==');

@$core.Deprecated('Use featureFlagDescriptor instead')
const FeatureFlag$json = {
  '1': 'FeatureFlag',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'enabled_globally', '3': 3, '4': 1, '5': 8, '10': 'enabledGlobally'},
    {
      '1': 'overrides',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.FeatureFlagOverride',
      '10': 'overrides'
    },
  ],
};

/// Descriptor for `FeatureFlag`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List featureFlagDescriptor = $convert.base64Decode(
    'CgtGZWF0dXJlRmxhZxIQCgNrZXkYASABKAlSA2tleRIgCgtkZXNjcmlwdGlvbhgCIAEoCVILZG'
    'VzY3JpcHRpb24SKQoQZW5hYmxlZF9nbG9iYWxseRgDIAEoCFIPZW5hYmxlZEdsb2JhbGx5Ek4K'
    'CW92ZXJyaWRlcxgEIAMoCzIwLnNtYXJ0Y29yZS5jb250cmFjdHMucXVlcmllcy5GZWF0dXJlRm'
    'xhZ092ZXJyaWRlUglvdmVycmlkZXM=');

@$core.Deprecated('Use listFeatureFlagsRequestDescriptor instead')
const ListFeatureFlagsRequest$json = {
  '1': 'ListFeatureFlagsRequest',
};

/// Descriptor for `ListFeatureFlagsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listFeatureFlagsRequestDescriptor =
    $convert.base64Decode('ChdMaXN0RmVhdHVyZUZsYWdzUmVxdWVzdA==');

@$core.Deprecated('Use listFeatureFlagsResponseDescriptor instead')
const ListFeatureFlagsResponse$json = {
  '1': 'ListFeatureFlagsResponse',
  '2': [
    {
      '1': 'flags',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.FeatureFlag',
      '10': 'flags'
    },
  ],
};

/// Descriptor for `ListFeatureFlagsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listFeatureFlagsResponseDescriptor =
    $convert.base64Decode(
        'ChhMaXN0RmVhdHVyZUZsYWdzUmVzcG9uc2USPgoFZmxhZ3MYASADKAsyKC5zbWFydGNvcmUuY2'
        '9udHJhY3RzLnF1ZXJpZXMuRmVhdHVyZUZsYWdSBWZsYWdz');

@$core.Deprecated('Use setFeatureFlagRequestDescriptor instead')
const SetFeatureFlagRequest$json = {
  '1': 'SetFeatureFlagRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'enabled_globally', '3': 2, '4': 1, '5': 8, '10': 'enabledGlobally'},
  ],
};

/// Descriptor for `SetFeatureFlagRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFeatureFlagRequestDescriptor = $convert.base64Decode(
    'ChVTZXRGZWF0dXJlRmxhZ1JlcXVlc3QSEAoDa2V5GAEgASgJUgNrZXkSKQoQZW5hYmxlZF9nbG'
    '9iYWxseRgCIAEoCFIPZW5hYmxlZEdsb2JhbGx5');

@$core.Deprecated('Use setFeatureFlagResponseDescriptor instead')
const SetFeatureFlagResponse$json = {
  '1': 'SetFeatureFlagResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `SetFeatureFlagResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFeatureFlagResponseDescriptor =
    $convert.base64Decode(
        'ChZTZXRGZWF0dXJlRmxhZ1Jlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use setFeatureFlagOverrideRequestDescriptor instead')
const SetFeatureFlagOverrideRequest$json = {
  '1': 'SetFeatureFlagOverrideRequest',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'tenant_id', '3': 2, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'enabled', '3': 3, '4': 1, '5': 8, '10': 'enabled'},
    {'1': 'remove_override', '3': 4, '4': 1, '5': 8, '10': 'removeOverride'},
  ],
};

/// Descriptor for `SetFeatureFlagOverrideRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFeatureFlagOverrideRequestDescriptor =
    $convert.base64Decode(
        'Ch1TZXRGZWF0dXJlRmxhZ092ZXJyaWRlUmVxdWVzdBIQCgNrZXkYASABKAlSA2tleRIbCgl0ZW'
        '5hbnRfaWQYAiABKAlSCHRlbmFudElkEhgKB2VuYWJsZWQYAyABKAhSB2VuYWJsZWQSJwoPcmVt'
        'b3ZlX292ZXJyaWRlGAQgASgIUg5yZW1vdmVPdmVycmlkZQ==');

@$core.Deprecated('Use setFeatureFlagOverrideResponseDescriptor instead')
const SetFeatureFlagOverrideResponse$json = {
  '1': 'SetFeatureFlagOverrideResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `SetFeatureFlagOverrideResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFeatureFlagOverrideResponseDescriptor =
    $convert.base64Decode(
        'Ch5TZXRGZWF0dXJlRmxhZ092ZXJyaWRlUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2'
        'Vzcw==');

@$core.Deprecated('Use auditLogEntryDescriptor instead')
const AuditLogEntry$json = {
  '1': 'AuditLogEntry',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'event_type', '3': 2, '4': 1, '5': 9, '10': 'eventType'},
    {'1': 'actor', '3': 3, '4': 1, '5': 9, '10': 'actor'},
    {'1': 'tenant_id', '3': 4, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
    {'1': 'ip_address', '3': 6, '4': 1, '5': 9, '10': 'ipAddress'},
    {'1': 'user_agent', '3': 7, '4': 1, '5': 9, '10': 'userAgent'},
    {'1': 'created_at', '3': 8, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `AuditLogEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List auditLogEntryDescriptor = $convert.base64Decode(
    'Cg1BdWRpdExvZ0VudHJ5Eg4KAmlkGAEgASgFUgJpZBIdCgpldmVudF90eXBlGAIgASgJUglldm'
    'VudFR5cGUSFAoFYWN0b3IYAyABKAlSBWFjdG9yEhsKCXRlbmFudF9pZBgEIAEoCVIIdGVuYW50'
    'SWQSIAoLZGVzY3JpcHRpb24YBSABKAlSC2Rlc2NyaXB0aW9uEh0KCmlwX2FkZHJlc3MYBiABKA'
    'lSCWlwQWRkcmVzcxIdCgp1c2VyX2FnZW50GAcgASgJUgl1c2VyQWdlbnQSHQoKY3JlYXRlZF9h'
    'dBgIIAEoA1IJY3JlYXRlZEF0');

@$core.Deprecated('Use queryAuditLogRequestDescriptor instead')
const QueryAuditLogRequest$json = {
  '1': 'QueryAuditLogRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'event_type', '3': 2, '4': 1, '5': 9, '10': 'eventType'},
    {'1': 'limit', '3': 3, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 4, '4': 1, '5': 5, '10': 'offset'},
  ],
};

/// Descriptor for `QueryAuditLogRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List queryAuditLogRequestDescriptor = $convert.base64Decode(
    'ChRRdWVyeUF1ZGl0TG9nUmVxdWVzdBIbCgl0ZW5hbnRfaWQYASABKAlSCHRlbmFudElkEh0KCm'
    'V2ZW50X3R5cGUYAiABKAlSCWV2ZW50VHlwZRIUCgVsaW1pdBgDIAEoBVIFbGltaXQSFgoGb2Zm'
    'c2V0GAQgASgFUgZvZmZzZXQ=');

@$core.Deprecated('Use queryAuditLogResponseDescriptor instead')
const QueryAuditLogResponse$json = {
  '1': 'QueryAuditLogResponse',
  '2': [
    {
      '1': 'entries',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.AuditLogEntry',
      '10': 'entries'
    },
    {'1': 'total_count', '3': 2, '4': 1, '5': 5, '10': 'totalCount'},
  ],
};

/// Descriptor for `QueryAuditLogResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List queryAuditLogResponseDescriptor = $convert.base64Decode(
    'ChVRdWVyeUF1ZGl0TG9nUmVzcG9uc2USRAoHZW50cmllcxgBIAMoCzIqLnNtYXJ0Y29yZS5jb2'
    '50cmFjdHMucXVlcmllcy5BdWRpdExvZ0VudHJ5UgdlbnRyaWVzEh8KC3RvdGFsX2NvdW50GAIg'
    'ASgFUgp0b3RhbENvdW50');

@$core.Deprecated('Use serviceHealthDescriptor instead')
const ServiceHealth$json = {
  '1': 'ServiceHealth',
  '2': [
    {'1': 'service_name', '3': 1, '4': 1, '5': 9, '10': 'serviceName'},
    {'1': 'status', '3': 2, '4': 1, '5': 9, '10': 'status'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
    {'1': 'response_time_ms', '3': 4, '4': 1, '5': 3, '10': 'responseTimeMs'},
  ],
};

/// Descriptor for `ServiceHealth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serviceHealthDescriptor = $convert.base64Decode(
    'Cg1TZXJ2aWNlSGVhbHRoEiEKDHNlcnZpY2VfbmFtZRgBIAEoCVILc2VydmljZU5hbWUSFgoGc3'
    'RhdHVzGAIgASgJUgZzdGF0dXMSGAoHbWVzc2FnZRgDIAEoCVIHbWVzc2FnZRIoChByZXNwb25z'
    'ZV90aW1lX21zGAQgASgDUg5yZXNwb25zZVRpbWVNcw==');

@$core.Deprecated('Use getServiceHealthRequestDescriptor instead')
const GetServiceHealthRequest$json = {
  '1': 'GetServiceHealthRequest',
};

/// Descriptor for `GetServiceHealthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getServiceHealthRequestDescriptor =
    $convert.base64Decode('ChdHZXRTZXJ2aWNlSGVhbHRoUmVxdWVzdA==');

@$core.Deprecated('Use getServiceHealthResponseDescriptor instead')
const GetServiceHealthResponse$json = {
  '1': 'GetServiceHealthResponse',
  '2': [
    {
      '1': 'services',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.ServiceHealth',
      '10': 'services'
    },
  ],
};

/// Descriptor for `GetServiceHealthResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getServiceHealthResponseDescriptor =
    $convert.base64Decode(
        'ChhHZXRTZXJ2aWNlSGVhbHRoUmVzcG9uc2USRgoIc2VydmljZXMYASADKAsyKi5zbWFydGNvcm'
        'UuY29udHJhY3RzLnF1ZXJpZXMuU2VydmljZUhlYWx0aFIIc2VydmljZXM=');

@$core.Deprecated('Use getDashboardSummaryRequestDescriptor instead')
const GetDashboardSummaryRequest$json = {
  '1': 'GetDashboardSummaryRequest',
};

/// Descriptor for `GetDashboardSummaryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDashboardSummaryRequestDescriptor =
    $convert.base64Decode('ChpHZXREYXNoYm9hcmRTdW1tYXJ5UmVxdWVzdA==');

@$core.Deprecated('Use getDashboardSummaryResponseDescriptor instead')
const GetDashboardSummaryResponse$json = {
  '1': 'GetDashboardSummaryResponse',
  '2': [
    {'1': 'total_tenants', '3': 1, '4': 1, '5': 5, '10': 'totalTenants'},
    {'1': 'active_tenants', '3': 2, '4': 1, '5': 5, '10': 'activeTenants'},
    {
      '1': 'total_subscriptions',
      '3': 3,
      '4': 1,
      '5': 5,
      '10': 'totalSubscriptions'
    },
    {
      '1': 'monthly_recurring_revenue',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'monthlyRecurringRevenue'
    },
    {
      '1': 'health',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.ServiceHealth',
      '10': 'health'
    },
  ],
};

/// Descriptor for `GetDashboardSummaryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getDashboardSummaryResponseDescriptor = $convert.base64Decode(
    'ChtHZXREYXNoYm9hcmRTdW1tYXJ5UmVzcG9uc2USIwoNdG90YWxfdGVuYW50cxgBIAEoBVIMdG'
    '90YWxUZW5hbnRzEiUKDmFjdGl2ZV90ZW5hbnRzGAIgASgFUg1hY3RpdmVUZW5hbnRzEi8KE3Rv'
    'dGFsX3N1YnNjcmlwdGlvbnMYAyABKAVSEnRvdGFsU3Vic2NyaXB0aW9ucxI6Chltb250aGx5X3'
    'JlY3VycmluZ19yZXZlbnVlGAQgASgJUhdtb250aGx5UmVjdXJyaW5nUmV2ZW51ZRJCCgZoZWFs'
    'dGgYBSADKAsyKi5zbWFydGNvcmUuY29udHJhY3RzLnF1ZXJpZXMuU2VydmljZUhlYWx0aFIGaG'
    'VhbHRo');

@$core.Deprecated('Use exportTenantsCsvRequestDescriptor instead')
const ExportTenantsCsvRequest$json = {
  '1': 'ExportTenantsCsvRequest',
};

/// Descriptor for `ExportTenantsCsvRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List exportTenantsCsvRequestDescriptor =
    $convert.base64Decode('ChdFeHBvcnRUZW5hbnRzQ3N2UmVxdWVzdA==');

@$core.Deprecated('Use exportTenantsCsvResponseDescriptor instead')
const ExportTenantsCsvResponse$json = {
  '1': 'ExportTenantsCsvResponse',
  '2': [
    {'1': 'chunk', '3': 1, '4': 1, '5': 12, '10': 'chunk'},
  ],
};

/// Descriptor for `ExportTenantsCsvResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List exportTenantsCsvResponseDescriptor =
    $convert.base64Decode(
        'ChhFeHBvcnRUZW5hbnRzQ3N2UmVzcG9uc2USFAoFY2h1bmsYASABKAxSBWNodW5r');

@$core.Deprecated('Use atendimentoResumoDescriptor instead')
const AtendimentoResumo$json = {
  '1': 'AtendimentoResumo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'contato_id', '3': 2, '4': 1, '5': 5, '10': 'contatoId'},
    {'1': 'status', '3': 3, '4': 1, '5': 9, '10': 'status'},
    {'1': 'departamento_id', '3': 4, '4': 1, '5': 5, '10': 'departamentoId'},
    {
      '1': 'fluxo_atendimento_id',
      '3': 5,
      '4': 1,
      '5': 5,
      '10': 'fluxoAtendimentoId'
    },
    {'1': 'etapa_atual_id', '3': 6, '4': 1, '5': 5, '10': 'etapaAtualId'},
    {'1': 'assunto', '3': 7, '4': 1, '5': 9, '10': 'assunto'},
    {'1': 'prioridade', '3': 8, '4': 1, '5': 9, '10': 'prioridade'},
    {
      '1': 'atendente_humano_id',
      '3': 9,
      '4': 1,
      '5': 5,
      '10': 'atendenteHumanoId'
    },
    {'1': 'data_inicio', '3': 10, '4': 1, '5': 3, '10': 'dataInicio'},
    {
      '1': 'data_ultima_mensagem',
      '3': 11,
      '4': 1,
      '5': 3,
      '10': 'dataUltimaMensagem'
    },
    {
      '1': 'sentimento_nota',
      '3': 12,
      '4': 1,
      '5': 5,
      '9': 0,
      '10': 'sentimentoNota',
      '17': true
    },
    {
      '1': 'sentimento_label',
      '3': 13,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'sentimentoLabel',
      '17': true
    },
  ],
  '8': [
    {'1': '_sentimento_nota'},
    {'1': '_sentimento_label'},
  ],
};

/// Descriptor for `AtendimentoResumo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List atendimentoResumoDescriptor = $convert.base64Decode(
    'ChFBdGVuZGltZW50b1Jlc3VtbxIOCgJpZBgBIAEoBVICaWQSHQoKY29udGF0b19pZBgCIAEoBV'
    'IJY29udGF0b0lkEhYKBnN0YXR1cxgDIAEoCVIGc3RhdHVzEicKD2RlcGFydGFtZW50b19pZBgE'
    'IAEoBVIOZGVwYXJ0YW1lbnRvSWQSMAoUZmx1eG9fYXRlbmRpbWVudG9faWQYBSABKAVSEmZsdX'
    'hvQXRlbmRpbWVudG9JZBIkCg5ldGFwYV9hdHVhbF9pZBgGIAEoBVIMZXRhcGFBdHVhbElkEhgK'
    'B2Fzc3VudG8YByABKAlSB2Fzc3VudG8SHgoKcHJpb3JpZGFkZRgIIAEoCVIKcHJpb3JpZGFkZR'
    'IuChNhdGVuZGVudGVfaHVtYW5vX2lkGAkgASgFUhFhdGVuZGVudGVIdW1hbm9JZBIfCgtkYXRh'
    'X2luaWNpbxgKIAEoA1IKZGF0YUluaWNpbxIwChRkYXRhX3VsdGltYV9tZW5zYWdlbRgLIAEoA1'
    'ISZGF0YVVsdGltYU1lbnNhZ2VtEiwKD3NlbnRpbWVudG9fbm90YRgMIAEoBUgAUg5zZW50aW1l'
    'bnRvTm90YYgBARIuChBzZW50aW1lbnRvX2xhYmVsGA0gASgJSAFSD3NlbnRpbWVudG9MYWJlbI'
    'gBAUISChBfc2VudGltZW50b19ub3RhQhMKEV9zZW50aW1lbnRvX2xhYmVs');

@$core.Deprecated('Use listAtendimentosRequestDescriptor instead')
const ListAtendimentosRequest$json = {
  '1': 'ListAtendimentosRequest',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 9, '10': 'status'},
    {'1': 'departamento_id', '3': 2, '4': 1, '5': 5, '10': 'departamentoId'},
    {'1': 'limit', '3': 3, '4': 1, '5': 5, '10': 'limit'},
  ],
};

/// Descriptor for `ListAtendimentosRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAtendimentosRequestDescriptor = $convert.base64Decode(
    'ChdMaXN0QXRlbmRpbWVudG9zUmVxdWVzdBIWCgZzdGF0dXMYASABKAlSBnN0YXR1cxInCg9kZX'
    'BhcnRhbWVudG9faWQYAiABKAVSDmRlcGFydGFtZW50b0lkEhQKBWxpbWl0GAMgASgFUgVsaW1p'
    'dA==');

@$core.Deprecated('Use listAtendimentosResponseDescriptor instead')
const ListAtendimentosResponse$json = {
  '1': 'ListAtendimentosResponse',
  '2': [
    {
      '1': 'atendimentos',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.AtendimentoResumo',
      '10': 'atendimentos'
    },
  ],
};

/// Descriptor for `ListAtendimentosResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAtendimentosResponseDescriptor = $convert.base64Decode(
    'ChhMaXN0QXRlbmRpbWVudG9zUmVzcG9uc2USUgoMYXRlbmRpbWVudG9zGAEgAygLMi4uc21hcn'
    'Rjb3JlLmNvbnRyYWN0cy5xdWVyaWVzLkF0ZW5kaW1lbnRvUmVzdW1vUgxhdGVuZGltZW50b3M=');

@$core.Deprecated('Use mensagemThreadDescriptor instead')
const MensagemThread$json = {
  '1': 'MensagemThread',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'atendimento_id', '3': 2, '4': 1, '5': 5, '10': 'atendimentoId'},
    {'1': 'tipo', '3': 3, '4': 1, '5': 9, '10': 'tipo'},
    {'1': 'conteudo', '3': 4, '4': 1, '5': 9, '10': 'conteudo'},
    {'1': 'remetente', '3': 5, '4': 1, '5': 9, '10': 'remetente'},
    {'1': 'timestamp', '3': 6, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'status_envio', '3': 7, '4': 1, '5': 9, '10': 'statusEnvio'},
    {'1': 'gerado_por_ia', '3': 8, '4': 1, '5': 8, '10': 'geradoPorIa'},
    {
      '1': 'resumo_midia',
      '3': 9,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'resumoMidia',
      '17': true
    },
  ],
  '8': [
    {'1': '_resumo_midia'},
  ],
};

/// Descriptor for `MensagemThread`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mensagemThreadDescriptor = $convert.base64Decode(
    'Cg5NZW5zYWdlbVRocmVhZBIOCgJpZBgBIAEoBVICaWQSJQoOYXRlbmRpbWVudG9faWQYAiABKA'
    'VSDWF0ZW5kaW1lbnRvSWQSEgoEdGlwbxgDIAEoCVIEdGlwbxIaCghjb250ZXVkbxgEIAEoCVII'
    'Y29udGV1ZG8SHAoJcmVtZXRlbnRlGAUgASgJUglyZW1ldGVudGUSHAoJdGltZXN0YW1wGAYgAS'
    'gDUgl0aW1lc3RhbXASIQoMc3RhdHVzX2VudmlvGAcgASgJUgtzdGF0dXNFbnZpbxIiCg1nZXJh'
    'ZG9fcG9yX2lhGAggASgIUgtnZXJhZG9Qb3JJYRImCgxyZXN1bW9fbWlkaWEYCSABKAlIAFILcm'
    'VzdW1vTWlkaWGIAQFCDwoNX3Jlc3Vtb19taWRpYQ==');

@$core.Deprecated('Use getThreadRequestDescriptor instead')
const GetThreadRequest$json = {
  '1': 'GetThreadRequest',
  '2': [
    {'1': 'atendimento_id', '3': 1, '4': 1, '5': 5, '10': 'atendimentoId'},
    {'1': 'limit', '3': 2, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 3, '4': 1, '5': 5, '10': 'offset'},
  ],
};

/// Descriptor for `GetThreadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getThreadRequestDescriptor = $convert.base64Decode(
    'ChBHZXRUaHJlYWRSZXF1ZXN0EiUKDmF0ZW5kaW1lbnRvX2lkGAEgASgFUg1hdGVuZGltZW50b0'
    'lkEhQKBWxpbWl0GAIgASgFUgVsaW1pdBIWCgZvZmZzZXQYAyABKAVSBm9mZnNldA==');

@$core.Deprecated('Use getThreadResponseDescriptor instead')
const GetThreadResponse$json = {
  '1': 'GetThreadResponse',
  '2': [
    {
      '1': 'mensagens',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.MensagemThread',
      '10': 'mensagens'
    },
  ],
};

/// Descriptor for `GetThreadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getThreadResponseDescriptor = $convert.base64Decode(
    'ChFHZXRUaHJlYWRSZXNwb25zZRJJCgltZW5zYWdlbnMYASADKAsyKy5zbWFydGNvcmUuY29udH'
    'JhY3RzLnF1ZXJpZXMuTWVuc2FnZW1UaHJlYWRSCW1lbnNhZ2Vucw==');

@$core.Deprecated('Use moveAtendimentoEtapaRequestDescriptor instead')
const MoveAtendimentoEtapaRequest$json = {
  '1': 'MoveAtendimentoEtapaRequest',
  '2': [
    {'1': 'atendimento_id', '3': 1, '4': 1, '5': 5, '10': 'atendimentoId'},
    {'1': 'etapa_destino_id', '3': 2, '4': 1, '5': 5, '10': 'etapaDestinoId'},
    {'1': 'motivo', '3': 3, '4': 1, '5': 9, '10': 'motivo'},
    {
      '1': 'action_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'actionId',
      '17': true
    },
  ],
  '8': [
    {'1': '_action_id'},
  ],
};

/// Descriptor for `MoveAtendimentoEtapaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moveAtendimentoEtapaRequestDescriptor = $convert.base64Decode(
    'ChtNb3ZlQXRlbmRpbWVudG9FdGFwYVJlcXVlc3QSJQoOYXRlbmRpbWVudG9faWQYASABKAVSDW'
    'F0ZW5kaW1lbnRvSWQSKAoQZXRhcGFfZGVzdGlub19pZBgCIAEoBVIOZXRhcGFEZXN0aW5vSWQS'
    'FgoGbW90aXZvGAMgASgJUgZtb3Rpdm8SIAoJYWN0aW9uX2lkGAQgASgJSABSCGFjdGlvbklkiA'
    'EBQgwKCl9hY3Rpb25faWQ=');

@$core.Deprecated('Use moveAtendimentoEtapaResponseDescriptor instead')
const MoveAtendimentoEtapaResponse$json = {
  '1': 'MoveAtendimentoEtapaResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `MoveAtendimentoEtapaResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moveAtendimentoEtapaResponseDescriptor =
    $convert.base64Decode(
        'ChxNb3ZlQXRlbmRpbWVudG9FdGFwYVJlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3'
        'M=');

@$core.Deprecated('Use sendOutboundMessageRequestDescriptor instead')
const SendOutboundMessageRequest$json = {
  '1': 'SendOutboundMessageRequest',
  '2': [
    {'1': 'atendimento_id', '3': 1, '4': 1, '5': 5, '10': 'atendimentoId'},
    {'1': 'conteudo', '3': 2, '4': 1, '5': 9, '10': 'conteudo'},
    {'1': 'tipo', '3': 3, '4': 1, '5': 9, '10': 'tipo'},
    {
      '1': 'action_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'actionId',
      '17': true
    },
  ],
  '8': [
    {'1': '_action_id'},
  ],
};

/// Descriptor for `SendOutboundMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendOutboundMessageRequestDescriptor = $convert.base64Decode(
    'ChpTZW5kT3V0Ym91bmRNZXNzYWdlUmVxdWVzdBIlCg5hdGVuZGltZW50b19pZBgBIAEoBVINYX'
    'RlbmRpbWVudG9JZBIaCghjb250ZXVkbxgCIAEoCVIIY29udGV1ZG8SEgoEdGlwbxgDIAEoCVIE'
    'dGlwbxIgCglhY3Rpb25faWQYBCABKAlIAFIIYWN0aW9uSWSIAQFCDAoKX2FjdGlvbl9pZA==');

@$core.Deprecated('Use sendOutboundMessageResponseDescriptor instead')
const SendOutboundMessageResponse$json = {
  '1': 'SendOutboundMessageResponse',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 5, '10': 'messageId'},
  ],
};

/// Descriptor for `SendOutboundMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendOutboundMessageResponseDescriptor =
    $convert.base64Decode(
        'ChtTZW5kT3V0Ym91bmRNZXNzYWdlUmVzcG9uc2USHQoKbWVzc2FnZV9pZBgBIAEoBVIJbWVzc2'
        'FnZUlk');

@$core.Deprecated('Use createInviteRequestDescriptor instead')
const CreateInviteRequest$json = {
  '1': 'CreateInviteRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {
      '1': 'module_permissions',
      '3': 4,
      '4': 3,
      '5': 9,
      '10': 'modulePermissions'
    },
    {'1': 'flow_permissions', '3': 5, '4': 3, '5': 5, '10': 'flowPermissions'},
  ],
};

/// Descriptor for `CreateInviteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createInviteRequestDescriptor = $convert.base64Decode(
    'ChNDcmVhdGVJbnZpdGVSZXF1ZXN0EhQKBWVtYWlsGAEgASgJUgVlbWFpbBISCgRuYW1lGAIgAS'
    'gJUgRuYW1lEhIKBHJvbGUYAyABKAlSBHJvbGUSLQoSbW9kdWxlX3Blcm1pc3Npb25zGAQgAygJ'
    'UhFtb2R1bGVQZXJtaXNzaW9ucxIpChBmbG93X3Blcm1pc3Npb25zGAUgAygFUg9mbG93UGVybW'
    'lzc2lvbnM=');

@$core.Deprecated('Use tenantInviteCreatedDescriptor instead')
const TenantInviteCreated$json = {
  '1': 'TenantInviteCreated',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'tenant_id', '3': 2, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'email', '3': 3, '4': 1, '5': 9, '10': 'email'},
    {'1': 'name', '3': 4, '4': 1, '5': 9, '10': 'name'},
    {'1': 'role', '3': 5, '4': 1, '5': 9, '10': 'role'},
    {'1': 'token', '3': 6, '4': 1, '5': 9, '10': 'token'},
    {'1': 'expires_at', '3': 7, '4': 1, '5': 3, '10': 'expiresAt'},
    {'1': 'used', '3': 8, '4': 1, '5': 8, '10': 'used'},
    {'1': 'created_at', '3': 9, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `TenantInviteCreated`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tenantInviteCreatedDescriptor = $convert.base64Decode(
    'ChNUZW5hbnRJbnZpdGVDcmVhdGVkEg4KAmlkGAEgASgJUgJpZBIbCgl0ZW5hbnRfaWQYAiABKA'
    'lSCHRlbmFudElkEhQKBWVtYWlsGAMgASgJUgVlbWFpbBISCgRuYW1lGAQgASgJUgRuYW1lEhIK'
    'BHJvbGUYBSABKAlSBHJvbGUSFAoFdG9rZW4YBiABKAlSBXRva2VuEh0KCmV4cGlyZXNfYXQYBy'
    'ABKANSCWV4cGlyZXNBdBISCgR1c2VkGAggASgIUgR1c2VkEh0KCmNyZWF0ZWRfYXQYCSABKANS'
    'CWNyZWF0ZWRBdA==');

@$core.Deprecated('Use createInviteResponseDescriptor instead')
const CreateInviteResponse$json = {
  '1': 'CreateInviteResponse',
  '2': [
    {
      '1': 'invite',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.TenantInviteCreated',
      '10': 'invite'
    },
  ],
};

/// Descriptor for `CreateInviteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createInviteResponseDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVJbnZpdGVSZXNwb25zZRJICgZpbnZpdGUYASABKAsyMC5zbWFydGNvcmUuY29udH'
    'JhY3RzLnF1ZXJpZXMuVGVuYW50SW52aXRlQ3JlYXRlZFIGaW52aXRl');

@$core.Deprecated('Use acceptInviteRequestDescriptor instead')
const AcceptInviteRequest$json = {
  '1': 'AcceptInviteRequest',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'email', '3': 3, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 4, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `AcceptInviteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceptInviteRequestDescriptor = $convert.base64Decode(
    'ChNBY2NlcHRJbnZpdGVSZXF1ZXN0EhQKBXRva2VuGAEgASgJUgV0b2tlbhIaCgh1c2VybmFtZR'
    'gCIAEoCVIIdXNlcm5hbWUSFAoFZW1haWwYAyABKAlSBWVtYWlsEhoKCHBhc3N3b3JkGAQgASgJ'
    'UghwYXNzd29yZA==');

@$core.Deprecated('Use acceptedTenantUserDescriptor instead')
const AcceptedTenantUser$json = {
  '1': 'AcceptedTenantUser',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'tenant_id', '3': 3, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'role', '3': 4, '4': 1, '5': 9, '10': 'role'},
    {
      '1': 'module_permissions',
      '3': 5,
      '4': 3,
      '5': 9,
      '10': 'modulePermissions'
    },
    {'1': 'flow_permissions', '3': 6, '4': 3, '5': 5, '10': 'flowPermissions'},
    {'1': 'is_active', '3': 7, '4': 1, '5': 8, '10': 'isActive'},
  ],
};

/// Descriptor for `AcceptedTenantUser`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceptedTenantUserDescriptor = $convert.base64Decode(
    'ChJBY2NlcHRlZFRlbmFudFVzZXISDgoCaWQYASABKAVSAmlkEhcKB3VzZXJfaWQYAiABKAVSBn'
    'VzZXJJZBIbCgl0ZW5hbnRfaWQYAyABKAlSCHRlbmFudElkEhIKBHJvbGUYBCABKAlSBHJvbGUS'
    'LQoSbW9kdWxlX3Blcm1pc3Npb25zGAUgAygJUhFtb2R1bGVQZXJtaXNzaW9ucxIpChBmbG93X3'
    'Blcm1pc3Npb25zGAYgAygFUg9mbG93UGVybWlzc2lvbnMSGwoJaXNfYWN0aXZlGAcgASgIUghp'
    'c0FjdGl2ZQ==');

@$core.Deprecated('Use acceptInviteResponseDescriptor instead')
const AcceptInviteResponse$json = {
  '1': 'AcceptInviteResponse',
  '2': [
    {
      '1': 'tenant_user',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.smartcore.contracts.queries.AcceptedTenantUser',
      '10': 'tenantUser'
    },
  ],
};

/// Descriptor for `AcceptInviteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceptInviteResponseDescriptor = $convert.base64Decode(
    'ChRBY2NlcHRJbnZpdGVSZXNwb25zZRJQCgt0ZW5hbnRfdXNlchgBIAEoCzIvLnNtYXJ0Y29yZS'
    '5jb250cmFjdHMucXVlcmllcy5BY2NlcHRlZFRlbmFudFVzZXJSCnRlbmFudFVzZXI=');

@$core.Deprecated('Use listInvitesRequestDescriptor instead')
const ListInvitesRequest$json = {
  '1': 'ListInvitesRequest',
};

/// Descriptor for `ListInvitesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listInvitesRequestDescriptor =
    $convert.base64Decode('ChJMaXN0SW52aXRlc1JlcXVlc3Q=');

@$core.Deprecated('Use tenantInviteItemDescriptor instead')
const TenantInviteItem$json = {
  '1': 'TenantInviteItem',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'email', '3': 2, '4': 1, '5': 9, '10': 'email'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'role', '3': 4, '4': 1, '5': 9, '10': 'role'},
    {
      '1': 'module_permissions',
      '3': 5,
      '4': 3,
      '5': 9,
      '10': 'modulePermissions'
    },
    {'1': 'flow_permissions', '3': 6, '4': 3, '5': 5, '10': 'flowPermissions'},
    {'1': 'expires_at', '3': 7, '4': 1, '5': 3, '10': 'expiresAt'},
    {'1': 'used', '3': 8, '4': 1, '5': 8, '10': 'used'},
    {'1': 'revoked', '3': 9, '4': 1, '5': 8, '10': 'revoked'},
    {'1': 'created_at', '3': 10, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `TenantInviteItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tenantInviteItemDescriptor = $convert.base64Decode(
    'ChBUZW5hbnRJbnZpdGVJdGVtEg4KAmlkGAEgASgJUgJpZBIUCgVlbWFpbBgCIAEoCVIFZW1haW'
    'wSEgoEbmFtZRgDIAEoCVIEbmFtZRISCgRyb2xlGAQgASgJUgRyb2xlEi0KEm1vZHVsZV9wZXJt'
    'aXNzaW9ucxgFIAMoCVIRbW9kdWxlUGVybWlzc2lvbnMSKQoQZmxvd19wZXJtaXNzaW9ucxgGIA'
    'MoBVIPZmxvd1Blcm1pc3Npb25zEh0KCmV4cGlyZXNfYXQYByABKANSCWV4cGlyZXNBdBISCgR1'
    'c2VkGAggASgIUgR1c2VkEhgKB3Jldm9rZWQYCSABKAhSB3Jldm9rZWQSHQoKY3JlYXRlZF9hdB'
    'gKIAEoA1IJY3JlYXRlZEF0');

@$core.Deprecated('Use listInvitesResponseDescriptor instead')
const ListInvitesResponse$json = {
  '1': 'ListInvitesResponse',
  '2': [
    {
      '1': 'invites',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.TenantInviteItem',
      '10': 'invites'
    },
  ],
};

/// Descriptor for `ListInvitesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listInvitesResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0SW52aXRlc1Jlc3BvbnNlEkcKB2ludml0ZXMYASADKAsyLS5zbWFydGNvcmUuY29udH'
    'JhY3RzLnF1ZXJpZXMuVGVuYW50SW52aXRlSXRlbVIHaW52aXRlcw==');

@$core.Deprecated('Use revokeInviteRequestDescriptor instead')
const RevokeInviteRequest$json = {
  '1': 'RevokeInviteRequest',
  '2': [
    {'1': 'invite_id', '3': 1, '4': 1, '5': 9, '10': 'inviteId'},
  ],
};

/// Descriptor for `RevokeInviteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeInviteRequestDescriptor =
    $convert.base64Decode(
        'ChNSZXZva2VJbnZpdGVSZXF1ZXN0EhsKCWludml0ZV9pZBgBIAEoCVIIaW52aXRlSWQ=');

@$core.Deprecated('Use revokeInviteResponseDescriptor instead')
const RevokeInviteResponse$json = {
  '1': 'RevokeInviteResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `RevokeInviteResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revokeInviteResponseDescriptor =
    $convert.base64Decode(
        'ChRSZXZva2VJbnZpdGVSZXNwb25zZRIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNz');

@$core.Deprecated('Use listTenantUsersRequestDescriptor instead')
const ListTenantUsersRequest$json = {
  '1': 'ListTenantUsersRequest',
};

/// Descriptor for `ListTenantUsersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTenantUsersRequestDescriptor =
    $convert.base64Decode('ChZMaXN0VGVuYW50VXNlcnNSZXF1ZXN0');

@$core.Deprecated('Use tenantUserItemDescriptor instead')
const TenantUserItem$json = {
  '1': 'TenantUserItem',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {
      '1': 'module_permissions',
      '3': 4,
      '4': 3,
      '5': 9,
      '10': 'modulePermissions'
    },
    {'1': 'flow_permissions', '3': 5, '4': 3, '5': 5, '10': 'flowPermissions'},
    {'1': 'is_active', '3': 6, '4': 1, '5': 8, '10': 'isActive'},
    {'1': 'created_at', '3': 7, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `TenantUserItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tenantUserItemDescriptor = $convert.base64Decode(
    'Cg5UZW5hbnRVc2VySXRlbRIOCgJpZBgBIAEoBVICaWQSFwoHdXNlcl9pZBgCIAEoBVIGdXNlck'
    'lkEhIKBHJvbGUYAyABKAlSBHJvbGUSLQoSbW9kdWxlX3Blcm1pc3Npb25zGAQgAygJUhFtb2R1'
    'bGVQZXJtaXNzaW9ucxIpChBmbG93X3Blcm1pc3Npb25zGAUgAygFUg9mbG93UGVybWlzc2lvbn'
    'MSGwoJaXNfYWN0aXZlGAYgASgIUghpc0FjdGl2ZRIdCgpjcmVhdGVkX2F0GAcgASgDUgljcmVh'
    'dGVkQXQ=');

@$core.Deprecated('Use listTenantUsersResponseDescriptor instead')
const ListTenantUsersResponse$json = {
  '1': 'ListTenantUsersResponse',
  '2': [
    {
      '1': 'users',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.TenantUserItem',
      '10': 'users'
    },
  ],
};

/// Descriptor for `ListTenantUsersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTenantUsersResponseDescriptor =
    $convert.base64Decode(
        'ChdMaXN0VGVuYW50VXNlcnNSZXNwb25zZRJBCgV1c2VycxgBIAMoCzIrLnNtYXJ0Y29yZS5jb2'
        '50cmFjdHMucXVlcmllcy5UZW5hbnRVc2VySXRlbVIFdXNlcnM=');

@$core.Deprecated('Use updateTenantUserRequestDescriptor instead')
const UpdateTenantUserRequest$json = {
  '1': 'UpdateTenantUserRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 5, '10': 'userId'},
    {'1': 'set_role', '3': 2, '4': 1, '5': 8, '10': 'setRole'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {
      '1': 'set_module_permissions',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'setModulePermissions'
    },
    {
      '1': 'module_permissions',
      '3': 5,
      '4': 3,
      '5': 9,
      '10': 'modulePermissions'
    },
    {
      '1': 'set_flow_permissions',
      '3': 6,
      '4': 1,
      '5': 8,
      '10': 'setFlowPermissions'
    },
    {'1': 'flow_permissions', '3': 7, '4': 3, '5': 5, '10': 'flowPermissions'},
  ],
};

/// Descriptor for `UpdateTenantUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantUserRequestDescriptor = $convert.base64Decode(
    'ChdVcGRhdGVUZW5hbnRVc2VyUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgFUgZ1c2VySWQSGQoIc2'
    'V0X3JvbGUYAiABKAhSB3NldFJvbGUSEgoEcm9sZRgDIAEoCVIEcm9sZRI0ChZzZXRfbW9kdWxl'
    'X3Blcm1pc3Npb25zGAQgASgIUhRzZXRNb2R1bGVQZXJtaXNzaW9ucxItChJtb2R1bGVfcGVybW'
    'lzc2lvbnMYBSADKAlSEW1vZHVsZVBlcm1pc3Npb25zEjAKFHNldF9mbG93X3Blcm1pc3Npb25z'
    'GAYgASgIUhJzZXRGbG93UGVybWlzc2lvbnMSKQoQZmxvd19wZXJtaXNzaW9ucxgHIAMoBVIPZm'
    'xvd1Blcm1pc3Npb25z');

@$core.Deprecated('Use updateTenantUserResponseDescriptor instead')
const UpdateTenantUserResponse$json = {
  '1': 'UpdateTenantUserResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `UpdateTenantUserResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTenantUserResponseDescriptor =
    $convert.base64Decode(
        'ChhVcGRhdGVUZW5hbnRVc2VyUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2Vzcw==');

@$core.Deprecated('Use getMyTenantConfigRequestDescriptor instead')
const GetMyTenantConfigRequest$json = {
  '1': 'GetMyTenantConfigRequest',
};

/// Descriptor for `GetMyTenantConfigRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMyTenantConfigRequestDescriptor =
    $convert.base64Decode('ChhHZXRNeVRlbmFudENvbmZpZ1JlcXVlc3Q=');

@$core.Deprecated('Use updateMyTenantConfigRequestDescriptor instead')
const UpdateMyTenantConfigRequest$json = {
  '1': 'UpdateMyTenantConfigRequest',
  '2': [
    {'1': 'dados_empresa', '3': 1, '4': 1, '5': 9, '10': 'dadosEmpresa'},
    {'1': 'persona_bot', '3': 2, '4': 1, '5': 9, '10': 'personaBot'},
    {'1': 'bot_agent_name', '3': 3, '4': 1, '5': 9, '10': 'botAgentName'},
    {'1': 'msg_fallback', '3': 4, '4': 1, '5': 9, '10': 'msgFallback'},
    {'1': 'msg_sem_info', '3': 5, '4': 1, '5': 9, '10': 'msgSemInfo'},
    {
      '1': 'msg_transferencia',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'msgTransferencia'
    },
    {'1': 'llm_class', '3': 7, '4': 1, '5': 9, '10': 'llmClass'},
    {'1': 'model', '3': 8, '4': 1, '5': 9, '10': 'model'},
    {'1': 'llm_temperature', '3': 9, '4': 1, '5': 9, '10': 'llmTemperature'},
    {
      '1': 'transcription_provider',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'transcriptionProvider'
    },
    {
      '1': 'transcription_model',
      '3': 11,
      '4': 1,
      '5': 9,
      '10': 'transcriptionModel'
    },
    {'1': 'vision_provider', '3': 12, '4': 1, '5': 9, '10': 'visionProvider'},
    {'1': 'vision_model', '3': 13, '4': 1, '5': 9, '10': 'visionModel'},
    {'1': 'embeddings_class', '3': 14, '4': 1, '5': 9, '10': 'embeddingsClass'},
    {'1': 'embeddings_model', '3': 15, '4': 1, '5': 9, '10': 'embeddingsModel'},
    {'1': 'chunk_size', '3': 16, '4': 1, '5': 5, '10': 'chunkSize'},
    {'1': 'chunk_overlap', '3': 17, '4': 1, '5': 5, '10': 'chunkOverlap'},
    {
      '1': 'similarity_threshold',
      '3': 18,
      '4': 1,
      '5': 9,
      '10': 'similarityThreshold'
    },
    {
      '1': 'vector_distance_threshold',
      '3': 19,
      '4': 1,
      '5': 9,
      '10': 'vectorDistanceThreshold'
    },
    {
      '1': 'api_keys',
      '3': 20,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.ApiKeyEntry',
      '10': 'apiKeys'
    },
  ],
};

/// Descriptor for `UpdateMyTenantConfigRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateMyTenantConfigRequestDescriptor = $convert.base64Decode(
    'ChtVcGRhdGVNeVRlbmFudENvbmZpZ1JlcXVlc3QSIwoNZGFkb3NfZW1wcmVzYRgBIAEoCVIMZG'
    'Fkb3NFbXByZXNhEh8KC3BlcnNvbmFfYm90GAIgASgJUgpwZXJzb25hQm90EiQKDmJvdF9hZ2Vu'
    'dF9uYW1lGAMgASgJUgxib3RBZ2VudE5hbWUSIQoMbXNnX2ZhbGxiYWNrGAQgASgJUgttc2dGYW'
    'xsYmFjaxIgCgxtc2dfc2VtX2luZm8YBSABKAlSCm1zZ1NlbUluZm8SKwoRbXNnX3RyYW5zZmVy'
    'ZW5jaWEYBiABKAlSEG1zZ1RyYW5zZmVyZW5jaWESGwoJbGxtX2NsYXNzGAcgASgJUghsbG1DbG'
    'FzcxIUCgVtb2RlbBgIIAEoCVIFbW9kZWwSJwoPbGxtX3RlbXBlcmF0dXJlGAkgASgJUg5sbG1U'
    'ZW1wZXJhdHVyZRI1ChZ0cmFuc2NyaXB0aW9uX3Byb3ZpZGVyGAogASgJUhV0cmFuc2NyaXB0aW'
    '9uUHJvdmlkZXISLwoTdHJhbnNjcmlwdGlvbl9tb2RlbBgLIAEoCVISdHJhbnNjcmlwdGlvbk1v'
    'ZGVsEicKD3Zpc2lvbl9wcm92aWRlchgMIAEoCVIOdmlzaW9uUHJvdmlkZXISIQoMdmlzaW9uX2'
    '1vZGVsGA0gASgJUgt2aXNpb25Nb2RlbBIpChBlbWJlZGRpbmdzX2NsYXNzGA4gASgJUg9lbWJl'
    'ZGRpbmdzQ2xhc3MSKQoQZW1iZWRkaW5nc19tb2RlbBgPIAEoCVIPZW1iZWRkaW5nc01vZGVsEh'
    '0KCmNodW5rX3NpemUYECABKAVSCWNodW5rU2l6ZRIjCg1jaHVua19vdmVybGFwGBEgASgFUgxj'
    'aHVua092ZXJsYXASMQoUc2ltaWxhcml0eV90aHJlc2hvbGQYEiABKAlSE3NpbWlsYXJpdHlUaH'
    'Jlc2hvbGQSOgoZdmVjdG9yX2Rpc3RhbmNlX3RocmVzaG9sZBgTIAEoCVIXdmVjdG9yRGlzdGFu'
    'Y2VUaHJlc2hvbGQSQwoIYXBpX2tleXMYFCADKAsyKC5zbWFydGNvcmUuY29udHJhY3RzLnF1ZX'
    'JpZXMuQXBpS2V5RW50cnlSB2FwaUtleXM=');

@$core.Deprecated('Use streamAtendimentosRequestDescriptor instead')
const StreamAtendimentosRequest$json = {
  '1': 'StreamAtendimentosRequest',
};

/// Descriptor for `StreamAtendimentosRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamAtendimentosRequestDescriptor =
    $convert.base64Decode('ChlTdHJlYW1BdGVuZGltZW50b3NSZXF1ZXN0');

@$core.Deprecated('Use atendimentoEventDescriptor instead')
const AtendimentoEvent$json = {
  '1': 'AtendimentoEvent',
  '2': [
    {'1': 'event_type', '3': 1, '4': 1, '5': 9, '10': 'eventType'},
    {'1': 'tenant_id', '3': 2, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'payload', '3': 3, '4': 1, '5': 9, '10': 'payload'},
  ],
};

/// Descriptor for `AtendimentoEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List atendimentoEventDescriptor = $convert.base64Decode(
    'ChBBdGVuZGltZW50b0V2ZW50Eh0KCmV2ZW50X3R5cGUYASABKAlSCWV2ZW50VHlwZRIbCgl0ZW'
    '5hbnRfaWQYAiABKAlSCHRlbmFudElkEhgKB3BheWxvYWQYAyABKAlSB3BheWxvYWQ=');
