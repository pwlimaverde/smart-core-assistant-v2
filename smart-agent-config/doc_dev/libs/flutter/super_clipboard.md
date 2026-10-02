# Super Clipboard

- **Versão Recomendada:** 0.9.1
- **Status de Atualização:** 🔍 EM_HOMOLOGACAO
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Leitura de imagens do clipboard (Ctrl+V) no Windows desktop; suporte multiplataforma completo (macOS, iOS, Android, Windows, Linux, Web); alternativa mais robusta que `pasteboard` para desktops.
- **Documentação Oficial:** [https://pub.dev/packages/super_clipboard](https://pub.dev/packages/super_clipboard)
- **Dependência Base:** `super_native_extensions` (native bindings multiplataforma)

---

## 1. Contexto e Uso no Projeto

Na interface do Smart Core Assistant v2, atendentes podem colar imagens via Ctrl+V. O widget `Clipboard` padrão do Flutter **só suporta texto**. O `super_clipboard` permite:
- Ler imagens do clipboard (PNG, DIB nativo no Windows)
- Escrever imagens para clipboard
- Suporte a múltiplos formatos (via `ClipboardReader.canProvide()`)
- Cross-platform com fallback gracioso por plataforma

No Windows, imagens copiadas geralmente estão em formato DIB (Device-Independent Bitmap). O `super_clipboard` converte automaticamente para PNG, facilitando o processamento.

---

## 2. Guia de Uso Rápido

### 2.1 Instalação

```yaml
dependencies:
  super_clipboard: ^0.9.1
  super_native_extensions: ^0.8.x # Dependência automática
```

### 2.2 Ler Imagem do Clipboard

```dart
import 'package:super_clipboard/super_clipboard.dart';

Future<Uint8List?> getImageFromClipboard() async {
  final reader = await ClipboardReader.instance();
  
  // Verificar se há imagem PNG disponível
  if (reader.canProvide(Formats.png)) {
    final file = await reader.getFile(Formats.png);
    if (file != null) {
      final stream = file.getStream();
      final bytes = await stream.readAsBytes();
      return bytes;
    }
  }
  
  return null;
}
```

### 2.3 Widget para Colar Imagem (Desktop)

```dart
import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';

class ImagePasteWidget extends StatefulWidget {
  @override
  State<ImagePasteWidget> createState() => _ImagePasteWidgetState();
}

class _ImagePasteWidgetState extends State<ImagePasteWidget> {
  Uint8List? _imageBytes;
  
  Future<void> _pasteImage() async {
    final reader = await ClipboardReader.instance();
    
    if (reader.canProvide(Formats.png)) {
      final file = await reader.getFile(Formats.png);
      if (file != null) {
        final stream = file.getStream();
        final bytes = await stream.readAsBytes();
        
        setState(() {
          _imageBytes = bytes;
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma imagem no clipboard')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _pasteImage,
          child: const Text('Colar Imagem (Ctrl+V)'),
        ),
        if (_imageBytes != null)
          Image.memory(_imageBytes!, width: 200, height: 200),
      ],
    );
  }
}
```

### 2.4 Verificar Formatos Disponíveis

```dart
Future<void> checkAvailableFormats() async {
  final reader = await ClipboardReader.instance();
  
  final hasPng = reader.canProvide(Formats.png);
  final hasJpeg = reader.canProvide(Formats.jpeg);
  final hasHtml = reader.canProvide(Formats.html);
  final hasText = reader.canProvide(Formats.plainText);
  
  print('PNG: $hasPng, JPEG: $hasJpeg, HTML: $hasHtml, Texto: $hasText');
}
```

### 2.5 Escrever Imagem para Clipboard

```dart
Future<void> copyImageToClipboard(Uint8List imageBytes) async {
  final writer = await ClipboardWriter.instance();
  
  writer.setData({
    Formats.png: DataWriterValue(imageBytes),
  });
  
  await writer.done();
  print('Imagem copiada para clipboard');
}
```

### 2.6 Suporte Multiplataforma com Fallback

```dart
Future<Uint8List?> getImageCrossPlatform() async {
  try {
    final reader = await ClipboardReader.instance();
    
    // Prioridade: PNG > JPEG > DIB (Windows)
    for (final format in [Formats.png, Formats.jpeg]) {
      if (reader.canProvide(format)) {
        final file = await reader.getFile(format);
        if (file != null) {
          final stream = file.getStream();
          return await stream.readAsBytes();
        }
      }
    }
  } on UnsupportedError {
    print('Clipboard não suportado nesta plataforma');
  } catch (e) {
    print('Erro ao acessar clipboard: $e');
  }
  
  return null;
}
```

---

## 3. APIs Principais

### ClipboardReader

| API | Descrição |
|-----|-----------|
| `ClipboardReader.instance()` | Obter instância do leitor |
| `canProvide(format)` | Verificar se formato está disponível |
| `getFile(format)` | Obter arquivo do clipboard para formato |
| `getImageFile()` | Helper: obter primeira imagem disponível |

### ClipboardWriter

| API | Descrição |
|-----|-----------|
| `ClipboardWriter.instance()` | Obter instância do escritor |
| `setData(map)` | Escrever dados (format -> value) |
| `done()` | Finalizar e gravar no clipboard |

### Formats

| Constante | Tipo | Windows | macOS | Linux | Web |
|-----------|------|---------|-------|-------|-----|
| `Formats.png` | Imagem | ✅ | ✅ | ✅ | ✅ |
| `Formats.jpeg` | Imagem | ✅ | ✅ | ✅ | ❌ |
| `Formats.plainText` | Texto | ✅ | ✅ | ✅ | ✅ |
| `Formats.html` | HTML | ✅ | ✅ | ⚠️ | ✅ |
| `Formats.uri` | URI/URL | ✅ | ✅ | ✅ | ✅ |

---

## 4. Suporte por Plataforma

| Plataforma | Suporte | Notas |
|-----------|---------|-------|
| **Windows** | ✅ Completo | Converte DIB/DIBv5 para PNG automaticamente |
| macOS | ✅ Completo | NSPasteboard nativo |
| iOS | ✅ Completo | UIPasteboard |
| Android | ✅ Completo | ClipboardManager |
| Linux | ✅ Completo | XClipboard/Wayland |
| Web | ✅ Limitado | Clipboard API (apenas texto/PNG) |

---

## 5. Tratamento de Erros

```dart
Future<Uint8List?> safeClipboardRead() async {
  try {
    final reader = await ClipboardReader.instance();
    
    if (!reader.canProvide(Formats.png)) {
      return null; // Sem imagem
    }
    
    final file = await reader.getFile(Formats.png);
    if (file == null) {
      return null; // Falha ao obter arquivo
    }
    
    final stream = file.getStream();
    return await stream.readAsBytes();
    
  } on UnsupportedError {
    print('Clipboard não suportado');
    return null;
  } on Exception catch (e) {
    print('Erro ao acessar clipboard: $e');
    return null;
  }
}
```

---

## 6. Comparação com super_native_extensions

`super_clipboard` é construído sobre `super_native_extensions`, que fornece:
- Bindings nativos cross-platform para clipboard
- Acesso direto a streams e formatos

**Diferença:** Use `super_clipboard` para API de alto nível simplificada; use `super_native_extensions` apenas se precisar controle extra sobre formatos ou performance em casos especializados.

---

## 7. Caveat: Thread Safety e Lifespan

- **Android/iOS:** Clipboard é thread-safe; pode ser acessado a qualquer momento
- **Windows/macOS:** Clipboard é bloqueante; considere usar `compute()` para leitura em background
- **Streams:** Finalizador automático; não necessário chamar `close()` explicito

---

## 8. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 0.9.1 | 2026-10-01 | EM_HOMOLOGACAO para Windows desktop image paste; conversão automática DIB→PNG; multiplataforma estável |

---

## 9. Referências

- **Pub.dev:** https://pub.dev/packages/super_clipboard
- **Repositório:** https://github.com/fzyzcjy/super_native_extensions
- **super_native_extensions:** https://pub.dev/packages/super_native_extensions

