import 'dart:io';

/// Apaga o arquivo do áudio gravado. Já ter sumido (o `cancel()` do gravador
/// apaga sozinho) não é erro.
Future<void> apagarArquivoTemporario(String caminho) async {
  if (caminho.isEmpty) return;
  final arquivo = File(caminho);
  if (await arquivo.exists()) await arquivo.delete();
}
