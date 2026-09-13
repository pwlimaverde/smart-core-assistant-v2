// This is a generated file - do not edit.
//
// Generated from queries/auth.proto.

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

@$core.Deprecated('Use registerRequestDescriptor instead')
const RegisterRequest$json = {
  '1': 'RegisterRequest',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
    {'1': 'email', '3': 2, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 3, '4': 1, '5': 9, '10': 'password'},
    {'1': 'full_name', '3': 4, '4': 1, '5': 9, '10': 'fullName'},
    {'1': 'tenant_name', '3': 5, '4': 1, '5': 9, '10': 'tenantName'},
    {'1': 'tenant_slug', '3': 6, '4': 1, '5': 9, '10': 'tenantSlug'},
  ],
};

/// Descriptor for `RegisterRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerRequestDescriptor = $convert.base64Decode(
    'Cg9SZWdpc3RlclJlcXVlc3QSGgoIdXNlcm5hbWUYASABKAlSCHVzZXJuYW1lEhQKBWVtYWlsGA'
    'IgASgJUgVlbWFpbBIaCghwYXNzd29yZBgDIAEoCVIIcGFzc3dvcmQSGwoJZnVsbF9uYW1lGAQg'
    'ASgJUghmdWxsTmFtZRIfCgt0ZW5hbnRfbmFtZRgFIAEoCVIKdGVuYW50TmFtZRIfCgt0ZW5hbn'
    'Rfc2x1ZxgGIAEoCVIKdGVuYW50U2x1Zw==');

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'password', '3': 2, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSFAoFZW1haWwYASABKAlSBWVtYWlsEhoKCHBhc3N3b3JkGAIgASgJUg'
    'hwYXNzd29yZA==');

@$core.Deprecated('Use authResponseDescriptor instead')
const AuthResponse$json = {
  '1': 'AuthResponse',
  '2': [
    {'1': 'access_token', '3': 1, '4': 1, '5': 9, '10': 'accessToken'},
    {'1': 'refresh_token', '3': 2, '4': 1, '5': 9, '10': 'refreshToken'},
  ],
};

/// Descriptor for `AuthResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authResponseDescriptor = $convert.base64Decode(
    'CgxBdXRoUmVzcG9uc2USIQoMYWNjZXNzX3Rva2VuGAEgASgJUgthY2Nlc3NUb2tlbhIjCg1yZW'
    'ZyZXNoX3Rva2VuGAIgASgJUgxyZWZyZXNoVG9rZW4=');

@$core.Deprecated('Use refreshRequestDescriptor instead')
const RefreshRequest$json = {
  '1': 'RefreshRequest',
  '2': [
    {'1': 'refresh_token', '3': 1, '4': 1, '5': 9, '10': 'refreshToken'},
  ],
};

/// Descriptor for `RefreshRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List refreshRequestDescriptor = $convert.base64Decode(
    'Cg5SZWZyZXNoUmVxdWVzdBIjCg1yZWZyZXNoX3Rva2VuGAEgASgJUgxyZWZyZXNoVG9rZW4=');

@$core.Deprecated('Use logoutRequestDescriptor instead')
const LogoutRequest$json = {
  '1': 'LogoutRequest',
  '2': [
    {'1': 'refresh_token', '3': 1, '4': 1, '5': 9, '10': 'refreshToken'},
  ],
};

/// Descriptor for `LogoutRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logoutRequestDescriptor = $convert.base64Decode(
    'Cg1Mb2dvdXRSZXF1ZXN0EiMKDXJlZnJlc2hfdG9rZW4YASABKAlSDHJlZnJlc2hUb2tlbg==');

@$core.Deprecated('Use logoutResponseDescriptor instead')
const LogoutResponse$json = {
  '1': 'LogoutResponse',
  '2': [
    {'1': 'revoked', '3': 1, '4': 1, '5': 8, '10': 'revoked'},
  ],
};

/// Descriptor for `LogoutResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List logoutResponseDescriptor = $convert
    .base64Decode('Cg5Mb2dvdXRSZXNwb25zZRIYCgdyZXZva2VkGAEgASgIUgdyZXZva2Vk');

@$core.Deprecated('Use solicitarRedefinicaoSenhaRequestDescriptor instead')
const SolicitarRedefinicaoSenhaRequest$json = {
  '1': 'SolicitarRedefinicaoSenhaRequest',
  '2': [
    {'1': 'login', '3': 1, '4': 1, '5': 9, '10': 'login'},
  ],
};

/// Descriptor for `SolicitarRedefinicaoSenhaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List solicitarRedefinicaoSenhaRequestDescriptor =
    $convert.base64Decode(
        'CiBTb2xpY2l0YXJSZWRlZmluaWNhb1NlbmhhUmVxdWVzdBIUCgVsb2dpbhgBIAEoCVIFbG9naW'
        '4=');

@$core.Deprecated('Use solicitarRedefinicaoSenhaResponseDescriptor instead')
const SolicitarRedefinicaoSenhaResponse$json = {
  '1': 'SolicitarRedefinicaoSenhaResponse',
  '2': [
    {'1': 'aceito', '3': 1, '4': 1, '5': 8, '10': 'aceito'},
  ],
};

/// Descriptor for `SolicitarRedefinicaoSenhaResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List solicitarRedefinicaoSenhaResponseDescriptor =
    $convert.base64Decode(
        'CiFTb2xpY2l0YXJSZWRlZmluaWNhb1NlbmhhUmVzcG9uc2USFgoGYWNlaXRvGAEgASgIUgZhY2'
        'VpdG8=');

@$core.Deprecated('Use redefinirSenhaRequestDescriptor instead')
const RedefinirSenhaRequest$json = {
  '1': 'RedefinirSenhaRequest',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {'1': 'nova_senha', '3': 2, '4': 1, '5': 9, '10': 'novaSenha'},
  ],
};

/// Descriptor for `RedefinirSenhaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List redefinirSenhaRequestDescriptor = $convert.base64Decode(
    'ChVSZWRlZmluaXJTZW5oYVJlcXVlc3QSFAoFdG9rZW4YASABKAlSBXRva2VuEh0KCm5vdmFfc2'
    'VuaGEYAiABKAlSCW5vdmFTZW5oYQ==');

@$core.Deprecated('Use redefinirSenhaResponseDescriptor instead')
const RedefinirSenhaResponse$json = {
  '1': 'RedefinirSenhaResponse',
  '2': [
    {'1': 'sucesso', '3': 1, '4': 1, '5': 8, '10': 'sucesso'},
  ],
};

/// Descriptor for `RedefinirSenhaResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List redefinirSenhaResponseDescriptor =
    $convert.base64Decode(
        'ChZSZWRlZmluaXJTZW5oYVJlc3BvbnNlEhgKB3N1Y2Vzc28YASABKAhSB3N1Y2Vzc28=');
