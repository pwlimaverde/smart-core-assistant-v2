// Stub temporário para tipos GetWindowsDownloadLink.
// Estes tipos serão sobrescritos por arquivos .pb.dart gerados automaticamente
// quando o protoc executar (no CI ou localmente):
//
//   protoc --dart_out=grpc:lib/ --proto_path=<root> admin.proto
//
// Esta é apenas uma implementação placebo para permitir compilação enquanto
// o protoc não tiver sido executado.

// ignore_for_file: implementation_imports

import 'package:protobuf/protobuf.dart' as $pb;

/// Requisição para obter link de download seguro (stub, será gerado).
class GetWindowsDownloadLinkRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('GetWindowsDownloadLinkRequest')
    ..aOS(1, 'channel')
    ..aOS(2, 'version')
    ..hasRequiredFields = false;

  GetWindowsDownloadLinkRequest._() : super();
  factory GetWindowsDownloadLinkRequest({
    String? channel,
    String? version,
  }) {
    final $result = create();
    if (channel != null) {
      $result.channel = channel;
    }
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }

  static final $pb.PbList<GetWindowsDownloadLinkRequest> _defaultInstance =
      $pb.PbList<GetWindowsDownloadLinkRequest>();
  static GetWindowsDownloadLinkRequest? _defaultInstanceAll;

  factory GetWindowsDownloadLinkRequest.getDefault() =>
      _defaultInstanceAll ??= $pb.GeneratedMessage.$_defaultFor<GetWindowsDownloadLinkRequest>(create);

  static GetWindowsDownloadLinkRequest create() => GetWindowsDownloadLinkRequest._();
  GetWindowsDownloadLinkRequest createEmptyInstance() => create();
  static $pb.PbList<GetWindowsDownloadLinkRequest> createRepeated() =>
      $pb.PbList<GetWindowsDownloadLinkRequest>();
  @$pb.TagNumber(1)
  String get channel => $_getSZ(0);
  @$pb.TagNumber(1)
  set channel(String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  $pb.BuilderInfo get info_ => _i;

  @$pb.TagNumber(2)
  String get version => $_getSZ(1);
  @$pb.TagNumber(2)
  set version(String v) {
    $_setString(1, v);
  }

  bool hasChannel() => $_has(0);
  void clearChannel() => clearField(1);

  bool hasVersion() => $_has(1);
  void clearVersion() => clearField(2);
}

/// Resposta com link de download e informações (stub, será gerado).
class GetWindowsDownloadLinkResponse extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('GetWindowsDownloadLinkResponse')
    ..aOS(1, 'url')
    ..aOS(2, 'version')
    ..aOS(3, 'fileName')
    ..aInt64(4, 'sizeBytes')
    ..aOS(5, 'sha256')
    ..aOS(6, 'releaseNotesMd')
    ..aInt64(7, 'expiresAtMs')
    ..hasRequiredFields = false;

  GetWindowsDownloadLinkResponse._() : super();
  factory GetWindowsDownloadLinkResponse({
    String? url,
    String? version,
    String? fileName,
    int? sizeBytes,
    String? sha256,
    String? releaseNotesMd,
    int? expiresAtMs,
  }) {
    final $result = create();
    if (url != null) {
      $result.url = url;
    }
    if (version != null) {
      $result.version = version;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (sha256 != null) {
      $result.sha256 = sha256;
    }
    if (releaseNotesMd != null) {
      $result.releaseNotesMd = releaseNotesMd;
    }
    if (expiresAtMs != null) {
      $result.expiresAtMs = expiresAtMs;
    }
    return $result;
  }

  static final $pb.PbList<GetWindowsDownloadLinkResponse> _defaultInstance =
      $pb.PbList<GetWindowsDownloadLinkResponse>();

  factory GetWindowsDownloadLinkResponse.getDefault() =>
      $pb.GeneratedMessage.$_defaultFor<GetWindowsDownloadLinkResponse>(create);

  static GetWindowsDownloadLinkResponse create() => GetWindowsDownloadLinkResponse._();

  GetWindowsDownloadLinkResponse createEmptyInstance() => create();

  static $pb.PbList<GetWindowsDownloadLinkResponse> createRepeated() =>
      $pb.PbList<GetWindowsDownloadLinkResponse>();

  @$pb.TagNumber(1)
  String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url(String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(2)
  String get version => $_getSZ(1);
  @$pb.TagNumber(2)
  set version(String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(3)
  String get fileName => $_getSZ(2);
  @$pb.TagNumber(3)
  set fileName(String v) {
    $_setString(2, v);
  }

  @$pb.TagNumber(4)
  int get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes(int v) {
    $_setInt64(3, v);
  }

  @$pb.TagNumber(5)
  String get sha256 => $_getSZ(4);
  @$pb.TagNumber(5)
  set sha256(String v) {
    $_setString(4, v);
  }

  @$pb.TagNumber(6)
  String get releaseNotesMd => $_getSZ(5);
  @$pb.TagNumber(6)
  set releaseNotesMd(String v) {
    $_setString(5, v);
  }

  @$pb.TagNumber(7)
  int get expiresAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set expiresAtMs(int v) {
    $_setInt64(6, v);
  }

  bool hasUrl() => $_has(0);
  void clearUrl() => clearField(1);

  bool hasVersion() => $_has(1);
  void clearVersion() => clearField(2);

  bool hasFileName() => $_has(2);
  void clearFileName() => clearField(3);

  bool hasSizeBytes() => $_has(3);
  void clearSizeBytes() => clearField(4);

  bool hasSha256() => $_has(4);
  void clearSha256() => clearField(5);

  bool hasReleaseNotesMd() => $_has(5);
  void clearReleaseNotesMd() => clearField(6);

  bool hasExpiresAtMs() => $_has(6);
  void clearExpiresAtMs() => clearField(7);

  @$pb.TagNumber(1)
  $pb.BuilderInfo get info_ => _i;
}
