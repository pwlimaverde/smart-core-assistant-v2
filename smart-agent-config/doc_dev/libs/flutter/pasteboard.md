# Pasteboard

- **Versão Recomendada:** 0.5.0
- **Status de Atualização:** 🔍 EM_HOMOLOGACAO — aguardando build Windows da CI (P3 do plano `correcoes-app-windows-flutter`)
- **Última Verificação:** 2026-10-02
- **Propósito no Projeto:** Ler imagem da área de transferência no Ctrl+V do compositor da conversa (`operacional_module`), no app Windows; compila no painel admin Web/WASM.
- **Documentação Oficial:** [https://pub.dev/packages/pasteboard](https://pub.dev/packages/pasteboard)
- **Publicador:** mixin.dev (verificado) — repositório `MixinNetwork/flutter-plugins`

---

## 1. Contexto e Uso no Projeto

O `Clipboard` do Flutter só lê texto. Para colar print (Win+Shift+S) direto na conversa, o
`operacional_module` usa `Pasteboard.image`, sempre atrás da abstração `LeitorDeImagemColada`
(`presentation/colagem/leitor_de_imagem_colada.dart`) — a tela nunca chama o plugin direto e os
testes injetam um leitor falso.

**Por que `pasteboard` e não `super_clipboard`** (decisão da P3, 2026-10-02):

| Critério | `pasteboard` 0.5.0 | `super_clipboard` 0.9.1 |
|---|---|---|
| WASM (pub.dev) | ✅ WASM-ready | ❌ não compatível (`super_native_extensions` → `pixel_snap` → `dart:io`) |
| Build nativo | C++ do plugin, sem Rust | Rust via cargokit (`super_native_extensions`) |
| Imagem no Windows | BMP (CF_DIB em arquivo temporário) | PNG (converte DIB/DIBv5) |

O painel admin (`smart-core-admin`) depende do `operacional_module` e a CI roda
`flutter build web --wasm`: um pacote não compatível com WASM na árvore é risco concreto de
quebrar esse build. O custo do `pasteboard` é a conversão BMP → PNG, feita no cliente com o
próprio motor do Flutter (seção 3).

---

## 2. Instalação

```yaml
dependencies:
  pasteboard: ^0.5.0
```

Sem configuração extra no Windows, Linux, macOS, iOS e Web. Android exige `FileProvider`
(não usado no projeto).

---

## 3. Uso no Projeto

```dart
import 'dart:ui' as ui;
import 'package:pasteboard/pasteboard.dart';

/// Imagem da área de transferência em PNG, ou nulo.
Future<Uint8List?> lerImagemPng() async {
  final bytes = await Pasteboard.image; // Windows: BMP; Web: blob image/*
  if (bytes == null || bytes.isEmpty) return null;
  if (formatoDaImagem(bytes) == 'png') return bytes;
  // BMP (Windows) → PNG pelo motor do Flutter: decodifica e recodifica.
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final quadro = await codec.getNextFrame();
    try {
      final dados =
          await quadro.image.toByteData(format: ui.ImageByteFormat.png);
      return dados?.buffer.asUint8List();
    } finally {
      quadro.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
```

Interceptação do Ctrl+V sem quebrar a colagem de texto: `Focus(onKeyEvent:)` em volta do
`TextField`, devolvendo **sempre** `KeyEventResult.ignored` — o evento segue até o `Shortcuts` do
app e o `EditableText` cola o texto; em paralelo a tela lê a imagem. Sobrescrever o
`PasteTextIntent` num ancestral não funciona (o `EditableText` registra as próprias `Actions`).

---

## 4. APIs Principais

| API | Retorno | Plataformas |
|-----|---------|-------------|
| `Pasteboard.image` | `Future<Uint8List?>` — bytes da imagem | iOS, desktop, Web, Android |
| `Pasteboard.text` | `Future<String?>` | todas |
| `Pasteboard.html` | `Future<String?>` | Windows, Web |
| `Pasteboard.files()` | `Future<List<String>>` — caminhos | desktop, Android |
| `Pasteboard.writeImage(bytes)` | `Future<void>` | iOS, Android, Web |
| `Pasteboard.writeFiles(paths)` | `Future<bool>` | desktop |

---

## 5. Comportamento por Plataforma

| Plataforma | `Pasteboard.image` | Notas |
|-----------|---------------------|-------|
| **Windows** | BMP | Lê `CF_DIB`, grava BMP em `%TEMP%` e o plugin apaga após ler. Sem `CF_DIB` (só texto) → `null`. Excel/Word podem pôr bitmap junto do texto. |
| **Web** | blob `image/*` do navegador (geralmente PNG) | `navigator.clipboard.read()`: pede permissão; alguns navegadores mostram um popup **a cada leitura**. Erros viram `null` com `debugPrint`. |
| macOS/Linux/iOS | bytes da imagem | Não usado no projeto. |

---

## 6. Armadilhas

- **BMP é grande:** um print 1920×1080 em BMP de 32 bits passa de 8 MB — sempre converter para
  PNG antes de checar o teto de 5 MB do servidor (`infrastructure_storage/src/midia.rs`) e antes
  de enviar (o servidor não aceita `image/bmp`).
- **Texto + bitmap:** planilha e editor de texto põem bitmap junto do texto. No Ctrl+V, só
  oferecer imagem quando `Clipboard.hasStrings()` for falso.
- **Web:** não ler a imagem a cada Ctrl+V — dispara pedido de permissão do navegador mesmo quando
  a pessoa só quer colar texto. No projeto o Ctrl+V de imagem fica desligado na Web (`kIsWeb`).
- **Logs:** nunca registrar o conteúdo nem a mensagem do erro (pode conter o caminho do
  temporário, com o usuário do Windows) — só formato, tamanho e `runtimeType`.
- **Testes:** `flutter test` não carrega o plugin nativo; manter a leitura atrás de abstração
  injetável.

---

## 7. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 0.5.0 | 2026-10-02 | Adotada na P3 (`correcoes-app-windows-flutter`) no lugar do `super_clipboard`: WASM-ready e sem Rust no build. EM_HOMOLOGACAO até o build Windows da CI e o aceite do Ctrl+V em dev. |

---

## 8. Referências

- **Pub.dev:** https://pub.dev/packages/pasteboard
- **Repositório:** https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/pasteboard
