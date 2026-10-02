import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show Clipboard;
import 'package:pasteboard/pasteboard.dart';

/// Teto de imagem do servidor (`infrastructure_storage/src/midia.rs`,
/// `CategoriaMidia::Imagem`). Recusar aqui poupa um upload que o servidor
/// recusaria e dá à pessoa uma mensagem clara.
const tetoDeImagemEmBytes = 5 * 1024 * 1024;

/// Mimetype com que a imagem colada sobe: o leitor sempre entrega PNG.
const mimetypeDaImagemColada = 'image/png';

/// Nome do arquivo da imagem colada — não há nome de origem na área de
/// transferência; o instante evita dois anexos com o mesmo nome.
String nomeDaImagemColada(DateTime instante) =>
    'colado_${instante.millisecondsSinceEpoch}.png';

/// Formato da imagem pela assinatura dos primeiros bytes. Só para log e para
/// decidir se precisa converter: o servidor confere a assinatura de novo.
String formatoDaImagem(List<int> bytes) {
  bool comeca(List<int> assinatura) {
    if (bytes.length < assinatura.length) return false;
    for (var i = 0; i < assinatura.length; i++) {
      if (bytes[i] != assinatura[i]) return false;
    }
    return true;
  }

  if (comeca(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (comeca(const [0xFF, 0xD8, 0xFF])) return 'jpeg';
  if (comeca(const [0x42, 0x4D])) return 'bmp';
  if (comeca(const [0x47, 0x49, 0x46])) return 'gif';
  if (comeca(const [0x52, 0x49, 0x46, 0x46])) return 'webp';
  return 'desconhecido';
}

/// P3 — a imagem que estava na área de transferência, já em PNG.
final class ImagemColada {
  final Uint8List bytesPng;

  /// O formato em que ela estava antes da conversão (`bmp` no Windows).
  final String formatoOriginal;

  const ImagemColada({required this.bytesPng, required this.formatoOriginal});
}

/// P3 — o que a tela precisa da área de transferência para colar imagem.
///
/// Abstração para a conversa não depender do plugin: os testes injetam um
/// leitor falso e nunca tocam o canal nativo.
abstract interface class LeitorDeImagemColada {
  /// Se há texto na área de transferência. Com texto, o Ctrl+V é colagem de
  /// texto — planilha e editor de texto também põem um bitmap junto, e
  /// oferecer imagem nesse caso atrapalharia.
  Future<bool> temTexto();

  /// A imagem da área de transferência em PNG, ou nulo quando não há imagem
  /// ou a leitura falhou (a falha é registrada, nunca o conteúdo).
  Future<ImagemColada?> lerImagem();
}

/// Implementação com o plugin `pasteboard`.
///
/// No Windows o plugin devolve BMP (DIB convertido em arquivo temporário) —
/// grande e fora do que o servidor aceita —, então tudo que não for PNG é
/// decodificado e recodificado em PNG pelo próprio motor do Flutter. Na Web
/// vem o blob `image/*` do navegador, normalmente já PNG.
class LeitorDeImagemPasteboard implements LeitorDeImagemColada {
  LeitorDeImagemPasteboard({
    Future<Uint8List?> Function()? lerBytes,
    Future<Uint8List?> Function(Uint8List bytes)? converterParaPng,
    Future<bool> Function()? temTexto,
  }) : _lerBytes = lerBytes ?? (() => Pasteboard.image),
       _converterParaPng = converterParaPng ?? _converterComOMotor,
       _temTexto = temTexto ?? Clipboard.hasStrings;

  final Future<Uint8List?> Function() _lerBytes;
  final Future<Uint8List?> Function(Uint8List bytes) _converterParaPng;
  final Future<bool> Function() _temTexto;

  @override
  Future<bool> temTexto() async {
    try {
      return await _temTexto();
    } catch (e) {
      _avisarFalha('falha ao consultar texto da área de transferência', e);
      // Na dúvida, trata como texto: o Ctrl+V segue só colando texto.
      return true;
    }
  }

  @override
  Future<ImagemColada?> lerImagem() async {
    try {
      final bytes = await _lerBytes();
      if (bytes == null || bytes.isEmpty) return null;
      final formato = formatoDaImagem(bytes);
      final png = formato == 'png' ? bytes : await _converterParaPng(bytes);
      if (png == null || png.isEmpty) return null;
      developer.log(
        'imagem lida da área de transferência',
        name: 'operacional_module.colagem',
        level: 500,
        error:
            'formato=$formato bytes_originais=${bytes.length} '
            'bytes_png=${png.length}',
      );
      return ImagemColada(bytesPng: png, formatoOriginal: formato);
    } catch (e) {
      _avisarFalha('falha ao ler imagem da área de transferência', e);
      return null;
    }
  }

  static void _avisarFalha(String mensagem, Object erro) => developer.log(
    mensagem,
    name: 'operacional_module.colagem',
    level: 900,
    // Só o tipo: a mensagem do erro pode trazer caminho de arquivo temporário.
    error: erro.runtimeType,
  );

  static Future<Uint8List?> _converterComOMotor(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final quadro = await codec.getNextFrame();
      try {
        final dados = await quadro.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return dados?.buffer.asUint8List();
      } finally {
        quadro.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
