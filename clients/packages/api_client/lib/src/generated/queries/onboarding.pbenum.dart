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

import 'package:protobuf/protobuf.dart' as $pb;

/// Como a confirmação chega para um provedor.
class ModoConfirmacao extends $pb.ProtobufEnum {
  static const ModoConfirmacao MODO_CONFIRMACAO_UNSPECIFIED = ModoConfirmacao._(
      0, _omitEnumNames ? '' : 'MODO_CONFIRMACAO_UNSPECIFIED');

  /// O provedor decide na própria chamada (voucher).
  static const ModoConfirmacao MODO_CONFIRMACAO_IMEDIATA =
      ModoConfirmacao._(1, _omitEnumNames ? '' : 'MODO_CONFIRMACAO_IMEDIATA');

  /// O usuário sai para pagar e a confirmação chega depois (gateway/webhook);
  /// o cliente acompanha por GetSignupStatus.
  static const ModoConfirmacao MODO_CONFIRMACAO_ASSINCRONA =
      ModoConfirmacao._(2, _omitEnumNames ? '' : 'MODO_CONFIRMACAO_ASSINCRONA');

  static const $core.List<ModoConfirmacao> values = <ModoConfirmacao>[
    MODO_CONFIRMACAO_UNSPECIFIED,
    MODO_CONFIRMACAO_IMEDIATA,
    MODO_CONFIRMACAO_ASSINCRONA,
  ];

  static final $core.List<ModoConfirmacao?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ModoConfirmacao? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ModoConfirmacao._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
