# Video Player

- **Versão Recomendada:** 2.8.5 (compatível com Flutter 3.12.2/Dart 3.12)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Propósito no Projeto:** Reprodução de vídeo por URL com suporte a Web e mobile (Android/iOS). **ATENÇÃO: Não suporta Windows Desktop.**
- **Documentação Oficial:** [https://pub.dev/packages/video_player](https://pub.dev/packages/video_player)
- **Source (Context7):** `/websites/pub_dev_video_player` | Reputation: High | Code Snippets: 397

---

## 1. Suporte por Plataforma

| Plataforma | Suporte | Observações |
|------------|---------|-------------|
| **Flutter Web** | ✅ Completo | Via HTML5 VideoElement; formatos dependem do navegador |
| **Windows Desktop** | ❌ **NÃO SUPORTADO** | Considere alternativas como `better_player`, `media_kit` ou `vlc_player` |
| Android | ✅ Completo | Via ExoPlayer/MediaPlayer |
| iOS | ✅ Completo | Via AVPlayer |
| macOS | ✅ Completo | Via AVPlayer |
| Linux | ❌ Não suportado | |

### Limitações Conhecidas

**Web:**
- `VideoPlayerController.file()` NÃO funciona (dart:io não disponível em Web)
- Use apenas `VideoPlayerController.networkUrl()` para URLs
- `videoPlayerOptions.mixWithOthers` é ignorado em Web
- Suporte a closed captions limitado por browser

---

## 2. Alternativas para Windows Desktop

Como `video_player` não suporta Windows, recomenda-se:

### Opção 1: Media Kit (Recomendado para Windows)
```yaml
dependencies:
  media_kit: ^1.0.0
  media_kit_video: ^1.0.0
```

- Suporte completo a Windows (libmpv)
- API mais moderna e estável
- Melhor performance em desktop

### Opção 2: Better Player
```yaml
dependencies:
  better_player: ^0.0.86
```

- Wrapper sobre video_player + Chewie
- Mais features (playlist, subtítulos, HLS/DASH)
- Mesmas limitações de plataforma que video_player

### Opção 3: VLC Player
```yaml
dependencies:
  flutter_vlc_player: ^7.0.0
```

- Baseado no VLC desktop
- Suporte a Windows, macOS, Linux
- Requer instalação do VLC runtime no sistema

---

## 3. Guia de Uso Rápido (Apenas Web/Mobile)

### 3.1 Instalação

```yaml
dependencies:
  video_player: ^2.8.5
```

### 3.2 Reprodução Básica de URL

```dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoApp extends StatefulWidget {
  const VideoApp({super.key});

  @override
  State<VideoApp> createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    )
      ..initialize().then((_) {
        setState(() {}); // Atualizar UI quando pronto
      });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      home: Scaffold(
        body: Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : const CircularProgressIndicator(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            });
          },
          child: Icon(
            _controller.value.isPlaying
                ? Icons.pause
                : Icons.play_arrow,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 3.3 Reprodução com Headers HTTP

```dart
Future<void> playWithHeaders() async {
  final controller = VideoPlayerController.networkUrl(
    Uri.parse('https://api.example.com/video.mp4'),
    httpHeaders: {
      'Authorization': 'Bearer token',
      'User-Agent': 'Custom-App',
    },
  );

  await controller.initialize();
  await controller.play();
}
```

### 3.4 Controles de Reprodução

```dart
Future<void> videoControls(VideoPlayerController controller) async {
  // Play/Pause
  await controller.play();
  await controller.pause();

  // Seek
  await controller.seekTo(const Duration(seconds: 30));

  // Volume
  await controller.setVolume(0.5); // 0.0 - 1.0

  // Velocidade
  await controller.setPlaybackSpeed(1.5); // 0.25, 0.5, 1.0, 1.5, 2.0

  // Loop
  await controller.setLooping(true);

  // Obter posição/duração
  print('Posição: ${controller.value.position}');
  print('Duração: ${controller.value.duration}');
  print('Progresso: ${controller.value.position.inSeconds}s / ${controller.value.duration.inSeconds}s');
}
```

### 3.5 Stream de Estado

```dart
Widget buildVideoWithStream(VideoPlayerController controller) {
  return StreamBuilder(
    stream: controller.videoEventStreamController.stream,
    builder: (context, snapshot) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Posição: ${controller.value.position.inSeconds}s / '
              '${controller.value.duration.inSeconds}s',
            ),
          ),
        ],
      );
    },
  );
}
```

### 3.6 Closed Captions

```dart
Future<void> playWithClosedCaptions() async {
  final controller = VideoPlayerController.networkUrl(
    Uri.parse('https://example.com/video.mp4'),
    closedCaptionFile: _loadCaptions(), // Retorna Future<ClosedCaptionFile>
  );

  await controller.initialize();
  await controller.play();
}

Future<ClosedCaptionFile> _loadCaptions() async {
  // Opção 1: Carregar de URL
  // return SubRipCaptionFile(await rootBundle.loadString('assets/captions.srt'));

  // Opção 2: De URL remoto
  final response = await http.get(Uri.parse('https://example.com/captions.srt'));
  return SubRipCaptionFile(response.body);
}
```

### 3.7 Verificar Suporte de Recursos (Web)

```dart
Future<void> checkWebFeatures(VideoPlayerController controller) async {
  // Verificar suporte a track de áudio (limitado em Web)
  if (controller.value.isAudioTrackSupportAvailable) {
    final tracks = await controller.getAudioTracks();
    print('Tracks de áudio: ${tracks.length}');
  } else {
    print('Seleção de áudio não suportada nesta plataforma');
  }

  // Verificar suporte a video tracks
  if (controller.value.isVideoTrackSupportAvailable) {
    final tracks = await controller.getVideoTracks();
    print('Tracks de vídeo: ${tracks.length}');
  }
}
```

---

## 4. Formatação e Compatibilidade

### Formatos Recomendados para Web

| Formato | Navegador | Codec |
|---------|-----------|-------|
| **.mp4** | Chrome ✅, Safari ✅, Firefox ✅ | H.264 + AAC |
| **.webm** | Chrome ✅, Firefox ✅, Safari ❌ | VP9 + Opus |
| **.ogv** | Firefox ✅, Chrome ✅, Safari ❌ | Theora + Vorbis |

**Recomendação:** MP4 é o formato mais compatível com Web.

---

## 5. APIs Principais

| API | Descrição |
|-----|-----------|
| `VideoPlayerController.networkUrl(uri)` | Criar controller para URL |
| `initialize()` | Inicializar (obter duração/aspectRatio) |
| `play()`, `pause()` | Controles de reprodução |
| `seek(duration)` | Pular para posição |
| `setVolume(double)` | Volume 0.0-1.0 |
| `setPlaybackSpeed(double)` | Velocidade de reprodução |
| `setLooping(bool)` | Loop ativo/inativo |
| `dispose()` | Liberar recursos |
| `value.isInitialized` | Controller pronto? |
| `value.isPlaying` | Está reproduzindo? |
| `value.position` | Posição atual |
| `value.duration` | Duração total |
| `value.aspectRatio` | Proporção da imagem |
| `getAudioTracks()` | Listar tracks de áudio (alguns) |
| `getVideoTracks()` | Listar tracks de vídeo (alguns) |
| `setClosedCaptionFile()` | Definir legendas |

---

## 6. Tratamento de Erros

```dart
Future<void> safeVideoPlayback(String url) async {
  final controller = VideoPlayerController.networkUrl(
    Uri.parse(url),
  );

  try {
    await controller.initialize();
    if (controller.value.hasError) {
      print('Erro ao carregar vídeo: ${controller.value.errorDescription}');
      return;
    }
    await controller.play();
  } catch (e) {
    print('Erro: $e');
  }
}
```

---

## 7. Breaking Changes

### v1.0.0 → v2.0.0

- `VideoPlayer` widget passou a estar em `video_player_platform_interface`
- `TextureView` vs `SurfaceView` em Android agora é configurável
- Remobvido suporte a `startAt`; usar `seekTo()` após initialize

### v2.8.0+

- Compatibilidade melhorada com Dart 3.12+
- Suporte a múltiplos video/audio tracks
- Melhorias em handling de errors

---

## 8. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 2.8.5 | 2026-08-09 | Versão estável; Web (HTML5) e mobile (Android/iOS) suportados; **Windows NÃO suportado** — usar media_kit ou better_player para desktop |
