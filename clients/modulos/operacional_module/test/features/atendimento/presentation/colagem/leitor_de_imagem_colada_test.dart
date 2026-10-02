import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/presentation/colagem/leitor_de_imagem_colada.dart';

/// P3 — leitura da imagem colada, sem o plugin nativo.
void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
  final bmp = Uint8List.fromList([0x42, 0x4D, 9, 9, 9, 9]);

  group('formatoDaImagem', () {
    test('reconhece as assinaturas comuns', () {
      expect(formatoDaImagem(png), 'png');
      expect(formatoDaImagem(bmp), 'bmp');
      expect(formatoDaImagem(const [0xFF, 0xD8, 0xFF, 0xE0]), 'jpeg');
      expect(formatoDaImagem(const [0x47, 0x49, 0x46, 0x38]), 'gif');
      expect(formatoDaImagem(const [0x52, 0x49, 0x46, 0x46, 0]), 'webp');
    });

    test('curto ou estranho é desconhecido', () {
      expect(formatoDaImagem(const [0x89]), 'desconhecido');
      expect(formatoDaImagem(const [1, 2, 3, 4]), 'desconhecido');
    });
  });

  test('nome da imagem colada leva o instante', () {
    expect(
      nomeDaImagemColada(DateTime.fromMillisecondsSinceEpoch(1234)),
      'colado_1234.png',
    );
  });

  group('LeitorDeImagemPasteboard', () {
    test('PNG passa direto, sem conversão', () async {
      var conversoes = 0;
      final leitor = LeitorDeImagemPasteboard(
        lerBytes: () async => png,
        converterParaPng: (_) async {
          conversoes++;
          return null;
        },
      );

      final imagem = await leitor.lerImagem();

      expect(imagem?.bytesPng, png);
      expect(imagem?.formatoOriginal, 'png');
      expect(conversoes, 0);
    });

    test('BMP do Windows é convertido em PNG', () async {
      final leitor = LeitorDeImagemPasteboard(
        lerBytes: () async => bmp,
        converterParaPng: (bytes) async {
          expect(bytes, bmp);
          return png;
        },
      );

      final imagem = await leitor.lerImagem();

      expect(imagem?.bytesPng, png);
      expect(imagem?.formatoOriginal, 'bmp');
    });

    test('sem imagem devolve nulo', () async {
      expect(
        await LeitorDeImagemPasteboard(lerBytes: () async => null).lerImagem(),
        isNull,
      );
      expect(
        await LeitorDeImagemPasteboard(
          lerBytes: () async => Uint8List(0),
        ).lerImagem(),
        isNull,
      );
    });

    test('conversão que não produz bytes devolve nulo', () async {
      final leitor = LeitorDeImagemPasteboard(
        lerBytes: () async => bmp,
        converterParaPng: (_) async => null,
      );

      expect(await leitor.lerImagem(), isNull);
    });

    test('falha de leitura vira nulo, sem lançar', () async {
      final leitor = LeitorDeImagemPasteboard(
        lerBytes: () async => throw Exception('clipboard ocupado'),
      );

      expect(await leitor.lerImagem(), isNull);
    });

    test('temTexto repassa a resposta e, na falha, assume texto', () async {
      expect(
        await LeitorDeImagemPasteboard(temTexto: () async => false).temTexto(),
        isFalse,
      );
      expect(
        await LeitorDeImagemPasteboard(
          temTexto: () async => throw Exception('canal'),
        ).temTexto(),
        isTrue,
      );
    });
  });
}
