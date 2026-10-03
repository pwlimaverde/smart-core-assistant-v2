/// Link de download do instalador Windows, já assinado pelo servidor.
final class WindowsDownloadLink {
  /// URL completa com o ticket (`?t=`). Vale até [expiresAtMs].
  final String url;
  final String version;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String releaseNotesMd;
  final int expiresAtMs;

  const WindowsDownloadLink({
    required this.url,
    required this.version,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.releaseNotesMd,
    required this.expiresAtMs,
  });

  /// O ticket ainda vale em [agora] (padrão: o relógio local).
  bool validoEm([DateTime? agora]) =>
      (agora ?? DateTime.now()).millisecondsSinceEpoch < expiresAtMs;

  /// Tamanho legível (B, KB, MB).
  String get tamanhoFormatado {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Começo do SHA-256 para exibição (o valor inteiro vai para a área de
  /// transferência).
  String get sha256Curto =>
      sha256.length > 16 ? '${sha256.substring(0, 16)}…' : sha256;
}
