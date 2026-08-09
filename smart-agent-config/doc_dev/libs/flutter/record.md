# Record

- **Versão Recomendada:** 5.1.2 (compatível com Flutter 3.12.2/Dart 3.12)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Propósito no Projeto:** Gravação de áudio from microphone (push-to-talk pattern), com suporte a múltiplos codecs/formatos, permissões nativas e obtenção de bytes ao parar a gravação.
- **Documentação Oficial:** [https://github.com/llfbandit/record](https://github.com/llfbandit/record)
- **Source (Context7):** `/llfbandit/record` | Reputation: Medium | Code Snippets: 108

---

## 1. Suporte por Plataforma

| Plataforma | Suporte | Observações |
|------------|---------|-------------|
| **Flutter Web** | ✅ Limitado | Via MediaRecorder API do navegador; formatos dependem do browser |
| **Windows Desktop** | ✅ Completo | Via Windows Media Foundation (wmf_libs: mf.lib, mfplat.lib, mfreadwrite.lib) |
| Android | ✅ Completo | Via Android MediaCodec/AudioRecord |
| iOS | ✅ Completo | Via AVFoundation |
| macOS | ✅ Completo | Via AVFoundation |
| Linux | ⚠️ Limitado | Requer ferramentas externas: parecord, pactl, ffmpeg |

---

## 2. Codecs/Formatos por Plataforma

### Encoders Suportados

| Encoder | Arquivo | Android | iOS | Web | Windows | macOS | Linux |
|---------|---------|---------|-----|-----|---------|-------|-------|
| **aacLc** | .m4a | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **aacEld** | .m4a | ✅ | ⚠️ | ❌ | ⚠️ | ❌ | ❌ |
| **aacHe** | .m4a | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **amrNb** | .amr | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **amrWb** | .amr | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **opus** | .opus/.caf | ✅ | ✅ (CAF) | ✅ | ⚠️ | ✅ (CAF) | ⚠️ |
| **wav** | .wav | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **flac** | .flac | ✅ | ⚠️ | ⚠️ | ✅ | ⚠️ | ✅ |
| **pcm16bits** | .wav | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Nota Web:** O navegador determina quais codecs são suportados (Chrome > Firefox > Safari). WAV e PCM16 são geralmente mais compatíveis.

---

## 3. Guia de Uso Rápido

### 3.1 Instalação

```yaml
dependencies:
  record: ^5.1.2
```

### 3.2 Verificação de Permissões

```dart
import 'package:record/record.dart';

Future<bool> checkPermissions() async {
  final record = AudioRecorder();
  
  if (await record.hasPermission()) {
    print('Permissão concedida');
    return true;
  } else {
    print('Permissão negada');
    return false;
  }
}
```

### 3.3 Gravação em Arquivo (Desktop)

```dart
Future<void> recordToFile() async {
  final record = AudioRecorder();

  if (await record.hasPermission()) {
    // Configurar o encoder (AAC para melhor compatibilidade)
    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );

    // Iniciar gravação
    await record.start(
      config,
      path: '/path/to/recording.m4a',
    );

    print('Gravando...');

    // Parar gravação
    await Future.delayed(const Duration(seconds: 5));
    final path = await record.stop();

    print('Arquivo salvo em: $path');
    record.dispose();
  }
}
```

### 3.4 Gravação em Stream (Para Obter Bytes)

```dart
Future<void> recordToStream() async {
  final record = AudioRecorder();

  if (await record.hasPermission()) {
    final stream = await record.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
      ),
    );

    // Escutar chunks de áudio
    stream.listen(
      (data) {
        print('Recebido chunk: ${data.length} bytes');
        // Processar/enviar dados via gRPC
      },
    );

    // Parar após 5 segundos
    await Future.delayed(const Duration(seconds: 5));
    await record.stop();
    record.dispose();
  }
}
```

### 3.5 Push-to-Talk Pattern (Parar e Obter Bytes)

```dart
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  
  Future<List<int>?> recordAudioBytes({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!await _recorder.hasPermission()) {
      print('Permissão de áudio negada');
      return null;
    }

    try {
      // Iniciar gravação em stream
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000, // Usado por muitos STT engines
        ),
      );

      final audioBytes = <int>[];

      // Coletar dados
      stream.listen((data) {
        audioBytes.addAll(data);
      });

      // Simular push-to-talk (usuário soltar o botão)
      await Future.delayed(Duration(seconds: 5));

      // Parar gravação
      await _recorder.stop();

      print('Áudio coletado: ${audioBytes.length} bytes');
      return audioBytes;
    } catch (e) {
      print('Erro ao gravar: $e');
      return null;
    } finally {
      _recorder.dispose();
    }
  }
}
```

### 3.6 Seleção de Encoder por Plataforma

```dart
Future<void> recordWithPlatformEncoder() async {
  final record = AudioRecorder();

  if (!await record.hasPermission()) return;

  final encoder = switch (defaultTargetPlatform) {
    TargetPlatform.windows => AudioEncoder.wav, // Mais compatível
    TargetPlatform.linux => AudioEncoder.flac,
    TargetPlatform.macOS => AudioEncoder.aacLc,
    _ => AudioEncoder.aacLc, // Default: AAC
  };

  await record.start(
    RecordConfig(encoder: encoder),
    path: 'recording.${encoder.fileExtension}',
  );
}
```

---

## 4. Tratamento de Erros

```dart
Future<void> safeRecording() async {
  final record = AudioRecorder();

  try {
    if (!await record.hasPermission()) {
      throw Exception('Permissão não concedida');
    }

    final config = const RecordConfig(encoder: AudioEncoder.aacLc);
    await record.start(config, path: '/path/to/file.m4a');

    await Future.delayed(const Duration(seconds: 5));

    final path = await record.stop();
    if (path != null) {
      print('Gravação salva: $path');
    }
  } on RecorderException catch (e) {
    print('Erro do recorder: ${e.description}');
  } catch (e) {
    print('Erro inesperado: $e');
  } finally {
    record.dispose();
  }
}
```

---

## 5. APIs Importantes

| API | Descrição |
|-----|-----------|
| `AudioRecorder()` | Cria instância do gravador |
| `hasPermission()` | Verifica permissão de microphone |
| `start(config, path)` | Inicia gravação em arquivo |
| `startStream(config)` | Inicia gravação em stream (bytes) |
| `stop()` | Para gravação e retorna path/dispõe stream |
| `cancel()` | Cancela e descarta arquivo/stream |
| `dispose()` | Libera recursos |
| `isPaused` | Verifica se está pausado |
| `pause()` / `resume()` | Pausa/retoma (algunas plataformas) |

---

## 6. RecordConfig Opções

```dart
const RecordConfig(
  encoder: AudioEncoder.aacLc,      // Codec
  bitRate: 128000,                   // bits/segundo
  sampleRate: 44100,                 // Hz
  numChannels: 1,                    // Mono (1) ou Stereo (2)
  echoCancel: true,                  // Cancelamento de eco (alguns)
  noiseSuppress: true,               // Supressão de ruído (alguns)
);
```

---

## 7. Breaking Changes

### v4.0.0 → v5.0.0

- `startStream()` agora retorna `Stream<List<int>>` diretamente
- `RecorderConfig` renomeado para `RecordConfig`
- Disposição obrigatória via `dispose()` para liberar recursos

---

## 8. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 5.1.2 | 2026-08-09 | Versão estável; suporte robusto a Web (MediaRecorder), Windows (WMF) e desktop; compatível com Flutter 3.12.2 |
