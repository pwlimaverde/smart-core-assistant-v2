// This is a generated file - do not edit.
//
// Generated from queries/onboarding.proto.

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

@$core.Deprecated('Use modoConfirmacaoDescriptor instead')
const ModoConfirmacao$json = {
  '1': 'ModoConfirmacao',
  '2': [
    {'1': 'MODO_CONFIRMACAO_UNSPECIFIED', '2': 0},
    {'1': 'MODO_CONFIRMACAO_IMEDIATA', '2': 1},
    {'1': 'MODO_CONFIRMACAO_ASSINCRONA', '2': 2},
  ],
};

/// Descriptor for `ModoConfirmacao`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modoConfirmacaoDescriptor = $convert.base64Decode(
    'Cg9Nb2RvQ29uZmlybWFjYW8SIAocTU9ET19DT05GSVJNQUNBT19VTlNQRUNJRklFRBAAEh0KGU'
    '1PRE9fQ09ORklSTUFDQU9fSU1FRElBVEEQARIfChtNT0RPX0NPTkZJUk1BQ0FPX0FTU0lOQ1JP'
    'TkEQAg==');

@$core.Deprecated('Use checkSlugRequestDescriptor instead')
const CheckSlugRequest$json = {
  '1': 'CheckSlugRequest',
  '2': [
    {'1': 'slug', '3': 1, '4': 1, '5': 9, '10': 'slug'},
  ],
};

/// Descriptor for `CheckSlugRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkSlugRequestDescriptor = $convert
    .base64Decode('ChBDaGVja1NsdWdSZXF1ZXN0EhIKBHNsdWcYASABKAlSBHNsdWc=');

@$core.Deprecated('Use checkSlugResponseDescriptor instead')
const CheckSlugResponse$json = {
  '1': 'CheckSlugResponse',
  '2': [
    {'1': 'disponivel', '3': 1, '4': 1, '5': 8, '10': 'disponivel'},
    {'1': 'motivo', '3': 2, '4': 1, '5': 9, '10': 'motivo'},
    {'1': 'mensagem', '3': 3, '4': 1, '5': 9, '10': 'mensagem'},
  ],
};

/// Descriptor for `CheckSlugResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List checkSlugResponseDescriptor = $convert.base64Decode(
    'ChFDaGVja1NsdWdSZXNwb25zZRIeCgpkaXNwb25pdmVsGAEgASgIUgpkaXNwb25pdmVsEhYKBm'
    '1vdGl2bxgCIAEoCVIGbW90aXZvEhoKCG1lbnNhZ2VtGAMgASgJUghtZW5zYWdlbQ==');

@$core.Deprecated('Use publicPlanDescriptor instead')
const PublicPlan$json = {
  '1': 'PublicPlan',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 5, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'price', '3': 4, '4': 1, '5': 9, '10': 'price'},
    {'1': 'max_instances', '3': 5, '4': 1, '5': 5, '10': 'maxInstances'},
    {'1': 'max_departments', '3': 6, '4': 1, '5': 5, '10': 'maxDepartments'},
    {'1': 'max_fluxos', '3': 7, '4': 1, '5': 5, '10': 'maxFluxos'},
  ],
};

/// Descriptor for `PublicPlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List publicPlanDescriptor = $convert.base64Decode(
    'CgpQdWJsaWNQbGFuEg4KAmlkGAEgASgFUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEiAKC2Rlc2'
    'NyaXB0aW9uGAMgASgJUgtkZXNjcmlwdGlvbhIUCgVwcmljZRgEIAEoCVIFcHJpY2USIwoNbWF4'
    'X2luc3RhbmNlcxgFIAEoBVIMbWF4SW5zdGFuY2VzEicKD21heF9kZXBhcnRtZW50cxgGIAEoBV'
    'IObWF4RGVwYXJ0bWVudHMSHQoKbWF4X2ZsdXhvcxgHIAEoBVIJbWF4Rmx1eG9z');

@$core.Deprecated('Use listPublicPlansRequestDescriptor instead')
const ListPublicPlansRequest$json = {
  '1': 'ListPublicPlansRequest',
};

/// Descriptor for `ListPublicPlansRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPublicPlansRequestDescriptor =
    $convert.base64Decode('ChZMaXN0UHVibGljUGxhbnNSZXF1ZXN0');

@$core.Deprecated('Use listPublicPlansResponseDescriptor instead')
const ListPublicPlansResponse$json = {
  '1': 'ListPublicPlansResponse',
  '2': [
    {
      '1': 'planos',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.PublicPlan',
      '10': 'planos'
    },
  ],
};

/// Descriptor for `ListPublicPlansResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPublicPlansResponseDescriptor =
    $convert.base64Decode(
        'ChdMaXN0UHVibGljUGxhbnNSZXNwb25zZRI/CgZwbGFub3MYASADKAsyJy5zbWFydGNvcmUuY2'
        '9udHJhY3RzLnF1ZXJpZXMuUHVibGljUGxhblIGcGxhbm9z');

@$core.Deprecated('Use startSignupRequestDescriptor instead')
const StartSignupRequest$json = {
  '1': 'StartSignupRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'slug', '3': 2, '4': 1, '5': 9, '10': 'slug'},
    {'1': 'email', '3': 3, '4': 1, '5': 9, '10': 'email'},
    {'1': 'username', '3': 4, '4': 1, '5': 9, '10': 'username'},
    {'1': 'password', '3': 5, '4': 1, '5': 9, '10': 'password'},
    {'1': 'phone', '3': 6, '4': 1, '5': 9, '10': 'phone'},
  ],
};

/// Descriptor for `StartSignupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startSignupRequestDescriptor = $convert.base64Decode(
    'ChJTdGFydFNpZ251cFJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZRISCgRzbHVnGAIgASgJUg'
    'RzbHVnEhQKBWVtYWlsGAMgASgJUgVlbWFpbBIaCgh1c2VybmFtZRgEIAEoCVIIdXNlcm5hbWUS'
    'GgoIcGFzc3dvcmQYBSABKAlSCHBhc3N3b3JkEhQKBXBob25lGAYgASgJUgVwaG9uZQ==');

@$core.Deprecated('Use startSignupResponseDescriptor instead')
const StartSignupResponse$json = {
  '1': 'StartSignupResponse',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'signup_token', '3': 2, '4': 1, '5': 9, '10': 'signupToken'},
    {'1': 'proximo_passo', '3': 3, '4': 1, '5': 5, '10': 'proximoPasso'},
  ],
};

/// Descriptor for `StartSignupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startSignupResponseDescriptor = $convert.base64Decode(
    'ChNTdGFydFNpZ251cFJlc3BvbnNlEhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQSIQoMc2'
    'lnbnVwX3Rva2VuGAIgASgJUgtzaWdudXBUb2tlbhIjCg1wcm94aW1vX3Bhc3NvGAMgASgFUgxw'
    'cm94aW1vUGFzc28=');

@$core.Deprecated('Use selectPlanRequestDescriptor instead')
const SelectPlanRequest$json = {
  '1': 'SelectPlanRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'signup_token', '3': 2, '4': 1, '5': 9, '10': 'signupToken'},
    {'1': 'plan_id', '3': 3, '4': 1, '5': 5, '10': 'planId'},
  ],
};

/// Descriptor for `SelectPlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List selectPlanRequestDescriptor = $convert.base64Decode(
    'ChFTZWxlY3RQbGFuUmVxdWVzdBIbCgl0ZW5hbnRfaWQYASABKAlSCHRlbmFudElkEiEKDHNpZ2'
    '51cF90b2tlbhgCIAEoCVILc2lnbnVwVG9rZW4SFwoHcGxhbl9pZBgDIAEoBVIGcGxhbklk');

@$core.Deprecated('Use selectPlanResponseDescriptor instead')
const SelectPlanResponse$json = {
  '1': 'SelectPlanResponse',
  '2': [
    {'1': 'proximo_passo', '3': 1, '4': 1, '5': 5, '10': 'proximoPasso'},
  ],
};

/// Descriptor for `SelectPlanResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List selectPlanResponseDescriptor = $convert.base64Decode(
    'ChJTZWxlY3RQbGFuUmVzcG9uc2USIwoNcHJveGltb19wYXNzbxgBIAEoBVIMcHJveGltb1Bhc3'
    'Nv');

@$core.Deprecated('Use paymentProviderDescriptor instead')
const PaymentProvider$json = {
  '1': 'PaymentProvider',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'rotulo', '3': 2, '4': 1, '5': 9, '10': 'rotulo'},
    {'1': 'instrucao', '3': 3, '4': 1, '5': 9, '10': 'instrucao'},
    {
      '1': 'requer_credencial',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'requerCredencial'
    },
    {
      '1': 'rotulo_credencial',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'rotuloCredencial'
    },
    {
      '1': 'modo',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.smartcore.contracts.queries.ModoConfirmacao',
      '10': 'modo'
    },
  ],
};

/// Descriptor for `PaymentProvider`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paymentProviderDescriptor = $convert.base64Decode(
    'Cg9QYXltZW50UHJvdmlkZXISDgoCaWQYASABKAlSAmlkEhYKBnJvdHVsbxgCIAEoCVIGcm90dW'
    'xvEhwKCWluc3RydWNhbxgDIAEoCVIJaW5zdHJ1Y2FvEisKEXJlcXVlcl9jcmVkZW5jaWFsGAQg'
    'ASgIUhByZXF1ZXJDcmVkZW5jaWFsEisKEXJvdHVsb19jcmVkZW5jaWFsGAUgASgJUhByb3R1bG'
    '9DcmVkZW5jaWFsEkAKBG1vZG8YBiABKA4yLC5zbWFydGNvcmUuY29udHJhY3RzLnF1ZXJpZXMu'
    'TW9kb0NvbmZpcm1hY2FvUgRtb2Rv');

@$core.Deprecated('Use listPaymentProvidersRequestDescriptor instead')
const ListPaymentProvidersRequest$json = {
  '1': 'ListPaymentProvidersRequest',
};

/// Descriptor for `ListPaymentProvidersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPaymentProvidersRequestDescriptor =
    $convert.base64Decode('ChtMaXN0UGF5bWVudFByb3ZpZGVyc1JlcXVlc3Q=');

@$core.Deprecated('Use listPaymentProvidersResponseDescriptor instead')
const ListPaymentProvidersResponse$json = {
  '1': 'ListPaymentProvidersResponse',
  '2': [
    {
      '1': 'provedores',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.smartcore.contracts.queries.PaymentProvider',
      '10': 'provedores'
    },
  ],
};

/// Descriptor for `ListPaymentProvidersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPaymentProvidersResponseDescriptor =
    $convert.base64Decode(
        'ChxMaXN0UGF5bWVudFByb3ZpZGVyc1Jlc3BvbnNlEkwKCnByb3ZlZG9yZXMYASADKAsyLC5zbW'
        'FydGNvcmUuY29udHJhY3RzLnF1ZXJpZXMuUGF5bWVudFByb3ZpZGVyUgpwcm92ZWRvcmVz');

@$core.Deprecated('Use confirmPaymentRequestDescriptor instead')
const ConfirmPaymentRequest$json = {
  '1': 'ConfirmPaymentRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'signup_token', '3': 2, '4': 1, '5': 9, '10': 'signupToken'},
    {'1': 'provedor', '3': 3, '4': 1, '5': 9, '10': 'provedor'},
    {'1': 'credencial', '3': 4, '4': 1, '5': 9, '10': 'credencial'},
  ],
};

/// Descriptor for `ConfirmPaymentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPaymentRequestDescriptor = $convert.base64Decode(
    'ChVDb25maXJtUGF5bWVudFJlcXVlc3QSGwoJdGVuYW50X2lkGAEgASgJUgh0ZW5hbnRJZBIhCg'
    'xzaWdudXBfdG9rZW4YAiABKAlSC3NpZ251cFRva2VuEhoKCHByb3ZlZG9yGAMgASgJUghwcm92'
    'ZWRvchIeCgpjcmVkZW5jaWFsGAQgASgJUgpjcmVkZW5jaWFs');

@$core.Deprecated('Use confirmPaymentResponseDescriptor instead')
const ConfirmPaymentResponse$json = {
  '1': 'ConfirmPaymentResponse',
  '2': [
    {'1': 'confirmado', '3': 1, '4': 1, '5': 8, '10': 'confirmado'},
    {
      '1': 'url_redirecionamento',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'urlRedirecionamento'
    },
    {'1': 'motivo', '3': 3, '4': 1, '5': 9, '10': 'motivo'},
    {'1': 'mensagem', '3': 4, '4': 1, '5': 9, '10': 'mensagem'},
  ],
};

/// Descriptor for `ConfirmPaymentResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List confirmPaymentResponseDescriptor = $convert.base64Decode(
    'ChZDb25maXJtUGF5bWVudFJlc3BvbnNlEh4KCmNvbmZpcm1hZG8YASABKAhSCmNvbmZpcm1hZG'
    '8SMQoUdXJsX3JlZGlyZWNpb25hbWVudG8YAiABKAlSE3VybFJlZGlyZWNpb25hbWVudG8SFgoG'
    'bW90aXZvGAMgASgJUgZtb3Rpdm8SGgoIbWVuc2FnZW0YBCABKAlSCG1lbnNhZ2Vt');

@$core.Deprecated('Use getSignupStatusRequestDescriptor instead')
const GetSignupStatusRequest$json = {
  '1': 'GetSignupStatusRequest',
  '2': [
    {'1': 'tenant_id', '3': 1, '4': 1, '5': 9, '10': 'tenantId'},
    {'1': 'signup_token', '3': 2, '4': 1, '5': 9, '10': 'signupToken'},
  ],
};

/// Descriptor for `GetSignupStatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSignupStatusRequestDescriptor =
    $convert.base64Decode(
        'ChZHZXRTaWdudXBTdGF0dXNSZXF1ZXN0EhsKCXRlbmFudF9pZBgBIAEoCVIIdGVuYW50SWQSIQ'
        'oMc2lnbnVwX3Rva2VuGAIgASgJUgtzaWdudXBUb2tlbg==');

@$core.Deprecated('Use getSignupStatusResponseDescriptor instead')
const GetSignupStatusResponse$json = {
  '1': 'GetSignupStatusResponse',
  '2': [
    {'1': 'passo', '3': 1, '4': 1, '5': 5, '10': 'passo'},
    {'1': 'plan_id', '3': 2, '4': 1, '5': 5, '10': 'planId'},
    {
      '1': 'status_assinatura',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'statusAssinatura'
    },
    {'1': 'tenant_ativo', '3': 4, '4': 1, '5': 8, '10': 'tenantAtivo'},
    {'1': 'periodo_fim', '3': 5, '4': 1, '5': 3, '10': 'periodoFim'},
  ],
};

/// Descriptor for `GetSignupStatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getSignupStatusResponseDescriptor = $convert.base64Decode(
    'ChdHZXRTaWdudXBTdGF0dXNSZXNwb25zZRIUCgVwYXNzbxgBIAEoBVIFcGFzc28SFwoHcGxhbl'
    '9pZBgCIAEoBVIGcGxhbklkEisKEXN0YXR1c19hc3NpbmF0dXJhGAMgASgJUhBzdGF0dXNBc3Np'
    'bmF0dXJhEiEKDHRlbmFudF9hdGl2bxgEIAEoCFILdGVuYW50QXRpdm8SHwoLcGVyaW9kb19maW'
    '0YBSABKANSCnBlcmlvZG9GaW0=');
