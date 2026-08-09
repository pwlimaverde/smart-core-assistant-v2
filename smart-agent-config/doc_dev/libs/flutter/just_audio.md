# Just Audio

- **Versão Recomendada:** 0.9.34 (compatível com Flutter 3.12.2/Dart 3.12)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Propósito no Projeto:** Reprodução de áudio de múltiplas fontes (URL/arquivo/asset/stream) com suporte a gapless playback, playlists, duração e controles avançados em Web e Windows.
- **Documentação Oficial:** [https://github.com/ryanheise/just_audio](https://github.com/ryanheise/just_audio)
- **Source (Context7):** `/ryanheise/just_audio` | Reputation: High | Code Snippets: 439

---

## 1. Suporte por Plataforma

| Plataforma | Suporte | Observações |
|------------|---------|-------------|
| **Flutter Web** | ✅ Completo | Via Web Audio API do navegador; CORS headers limitado a cookies |
| **Windows Desktop** | ✅ Completo | Via platform channels; suporte a múltiplos formatos |
| Android | ✅ Completo | Via ExoPlayer |
| iOS | ✅ Completo | Via AVAudioEngine |
| macOS | ✅ Completo | Via AVAudioEngine |
| Linux | ✅ Completo | Via GStreamer |

### Funcionalidades Avançadas por Plataforma

| Funcionalidade | Android | iOS | Web | Windows | macOS | Linux |
|---|---|---|---|---|---|---|
| Playback básico | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Gapless playback | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| Playlists | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| HLS/DASH | ✅ | ✅ | ✅ | ⚠️ | ✅ | ⚠️ |
| Pitch shifting | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Speed control | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Silence skipping | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Audio offloading | ✅ | ⚠️ | ❌ | ❌ | ❌ | ❌ |

---

## 2. Guia de Uso Rápido

### 2.1 Instalação

```yaml
dependencies:
  just_audio: ^0.9.34
```

### 2.2 Reprodução Simples de URL

```dart
import 'package:just_audio/just_audio.dart';

Future<void> playAudio() async {
  final player = AudioPlayer();

  try {
    // Carregar áudio de URL
    final duration = await player.setUrl('https://example.com/audio.mp3');
    print('Duração: $duration');

    // Reproduzir
    await player.play();

    // Escutar estado
    player.playerStateStream.listen((playerState) {
      print('Estado: ${playerState.playing} - ${playerState.processingState}');
    });

    // Parar
    await Future.delayed(const Duration(seconds: 10));
    await player.stop();
  } catch (e) {
    print('Erro: $e');
  } finally {
    await player.dispose();
  }
}
```

### 2.3 Carregar Áudio de Diferentes Fontes

```dart
Future<void> loadFromDifferentSources(AudioPlayer player) async {
  // De URL (HTTP/HTTPS)
  await player.setUrl('https://example.com/audio.mp3');

  // De arquivo local (Desktop)
  await player.setFilePath('/path/to/audio.mp3');

  // De asset
  await player.setAsset('assets/audio/speech.wav');

  // De stream/bytes
  await player.setUrl('data:audio/mp3;base64,SUQzBAAAAAAAI1NT...');
}
```

### 2.4 Reprodução com Playlist

```dart
Future<void> playPlaylist(AudioPlayer player) async {
  final playlist = ConcatenatingAudioSource(
    children: [
      AudioSource.uri(Uri.parse('https://example.com/track1.mp3')),
      AudioSource.uri(Uri.parse('https://example.com/track2.mp3')),
      AudioSource.uri(Uri.parse('https://example.com/track3.mp3')),
    ],
  );

  try {
    await player.setAudioSource(playlist);
    await player.play();

    // Escutar mudanças de música
    player.sequenceStateStream.listen((state) {
      if (state != null) {
        print('Tocando: ${state.currentIndex} de ${state.sequence.length}');
      }
    });

    // Próxima música
    await player.seekToNext();

    // Anterior
    await player.seekToPrevious();
  } catch (e) {
    print('Erro: $e');
  }
}
```

### 2.5 Controles de Reprodução

```dart
Future<void> audioControls(AudioPlayer player) async {
  // Play/Pause
  await player.play();
  await player.pause();
  await player.stop();

  // Seek
  await player.seek(const Duration(seconds: 30));

  // Volume
  await player.setVolume(0.5); // 0.0 - 1.0

  // Velocidade
  await player.setSpeed(1.5); // 1x até ~3x dependendo da plataforma

  // Loop
  await player.setLoopMode(LoopMode.all); // all, one, off

  // Shuffle
  await player.setShuffleModeEnabled(true);
}
```

### 2.6 Ouvir Estado e Duração

```dart
Future<void> listenToState(AudioPlayer player) async {
  await player.setUrl('https://example.com/audio.mp3');

  // Escutar estado do player
  player.playerStateStream.listen((state) {
    print('Reproduzindo: ${state.playing}');
    print('Processamento: ${state.processingState}');
    // Valores: idle, loading, buffering, ready
  });

  // Escutar posição
  player.positionStream.listen((duration) {
    print('Posição: $duration');
  });

  // Escutar duração
  player.durationStream.listen((duration) {
    print('Duração: $duration');
  });

  // Escutar buffer
  player.bufferedPositionStream.listen((buffered) {
    print('Buffer: $buffered');
  });
}
```

### 2.7 Web: Tratamento de CORS

```dart
Future<void> playWithCorsHeaders(AudioPlayer player) async {
  // No Web, headers HTTP são limitados a cookies
  final duration = await player.setUrl(
    'https://api.example.com/audio.mp3',
    headers: {'Authorization': 'Bearer token'}, // Não funciona em Web
  );

  // Alternativa: usar URL com token query param ou cookie
  await player.setUrl('https://api.example.com/audio.mp3?token=xyz');

  // Ou definir CORS mode (se suportado)
  await player.setWebCrossOrigin(WebCrossOrigin.anonymous);
}
```

### 2.8 Seleção de Dispositivo de Saída (Web)

```dart
Future<void> selectAudioOutput(AudioPlayer player) async {
  // Obter dispositivos de áudio disponíveis (Web)
  try {
    final sinkId = 'speaker-device-id'; // ID do dispositivo
    await player.setWebSinkId(sinkId);
    print('Saída alterada para: $sinkId');
  } catch (e) {
    print('Erro ao selecionar saída: $e');
  }
}
```

---

## 3. AudioPlayer Instâncias e Dispose

```dart
// ANTI-PATTERN: Criar nova instância toda vez
for (int i = 0; i < 10; i++) {
  final player = AudioPlayer(); // Vaza memória!
}

// PADRÃO: Reutilizar instância
class AudioService extends ChangeNotifier {
  late final AudioPlayer _player;

  AudioService() {
    _player = AudioPlayer();
  }

  Future<void> play(String url) async {
    await _player.setUrl(url);
    await _player.play();
  }

  @override
  void dispose() {
    _player.dispose(); // Importante!
    super.dispose();
  }
}
```

---

## 4. Tratamento de Erros e Estados

```dart
Future<void> robustPlayback(AudioPlayer player) async {
  try {
    await player.setUrl('https://example.com/audio.mp3');
  } on PlayerException catch (e) {
    print('Erro do player: ${e.message}');
  } on PlayerInterruptedException catch (e) {
    print('Interrupção: ${e.message}');
  } catch (e) {
    print('Erro desconhecido: $e');
  }

  // Escutar erros em stream
  player.processingStateStream.listen((state) {
    if (state == ProcessingState.idle) {
      print('Player ocioso');
    }
  });
}
```

---

## 5. APIs Principais

| API | Descrição |
|-----|-----------|
| `setUrl(url, {headers})` | Carregar de URL |
| `setFilePath(path)` | Carregar arquivo local |
| `setAsset(path)` | Carregar asset |
| `setAudioSource(source)` | Carregar fonte complexa |
| `play()`, `pause()`, `stop()` | Controles básicos |
| `seek(duration)` | Pular para posição |
| `setVolume(double)` | Volume 0.0-1.0 |
| `setSpeed(double)` | Velocidade 0.5-2.0+ |
| `setLoopMode(mode)` | Loop off/one/all |
| `setShuffleModeEnabled(bool)` | Shuffle |
| `dispose()` | Liberar recursos |
| `playerStateStream` | Estado (playing, processingState) |
| `positionStream` | Posição atual |
| `durationStream` | Duração total |
| `bufferedPositionStream` | Quanto foi buffered |
| `sequenceStateStream` | Índice em playlist |

---

## 6. Formatos Suportados

- **Áudio:** MP3, WAV, AAC, FLAC, OGG, M4A, OPUS, WEBM
- **Vídeo (extrair áudio):** MP4, MKV, AVI, MOV, WMV
- **Streaming:** HLS (.m3u8), DASH (.mpd)

---

## 7. Breaking Changes

### v0.8.0 → v0.9.0

- `JustAudioBackground` removido; usar `audio_service` para background playback
- `setUrl()` agora retorna `Future<Duration?>` (duração se disponível)
- Mudanças em `PlayerState` structure

### v0.9.30+

- Compatibilidade melhorada com Dart 3.12+
- Suporte aprimorado a Web Audio API
- Melhorias em buffering e error handling

---

## 8. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 0.9.34 | 2026-08-09 | Versão estável atual; suporte robusto a Web e Windows; compatível com Flutter 3.12.2; gapless playback em desktop |
