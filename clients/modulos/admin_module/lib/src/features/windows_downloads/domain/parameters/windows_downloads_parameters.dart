/// Parâmetros para requisição de link de download do Windows.
class GetWindowsDownloadLinkParams {
  /// Canal de release ("beta" ou "stable").
  /// Nesta entrega, apenas "beta" é suportado.
  final String channel;

  /// Versão específica a baixar (vazio = a mais recente do canal).
  final String? version;

  GetWindowsDownloadLinkParams({
    this.channel = 'beta',
    this.version,
  });
}
