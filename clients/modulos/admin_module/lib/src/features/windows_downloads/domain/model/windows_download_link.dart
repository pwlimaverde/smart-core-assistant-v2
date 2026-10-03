/// Modelo para o link de download seguro do instalador Windows.
class WindowsDownloadLink {
  final String url;
  final String version;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String releaseNotesMd;
  final int expiresAtMs;

  WindowsDownloadLink({
    required this.url,
    required this.version,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.releaseNotesMd,
    required this.expiresAtMs,
  });

  /// Verifica se o link ainda está válido.
  bool get isValid {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now < expiresAtMs;
  }

  /// Formata o tamanho em bytes para uma string legível (KB, MB).
  String get formattedSize {
    if (sizeBytes < 1024) {
      return '${sizeBytes} B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  /// SHA256 truncado para exibição (primeiros 16 caracteres).
  String get sha256Short => sha256.substring(0, 16);
}
