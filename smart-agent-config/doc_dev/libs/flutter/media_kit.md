# Media Kit

- **Versão Recomendada:** 1.2.6
- **Status de Atualização:** 🔍 EM_HOMOLOGACAO
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Reprodução de áudio e vídeo no Windows desktop com suporte completo a ogg/opus e mp4; alternativa recomendada a `video_player` e `just_audio` para desktop; API moderna e modular.
- **Documentação Oficial:** [https://pub.dev/packages/media_kit](https://pub.dev/packages/media_kit)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 precisa reproduzir:
- **Áudio:** Mensagens de voz em ogg/opus (do WhatsApp/IA engine)
- **Vídeo:** Clipes de chamada ou mídia (menos crítico, não suportado no desktop atualmente)

`media_kit` é a solução **recomendada para Windows desktop** por:
- Suporte completo a ogg/opus nativo (via libmpv)
- Performance superior (hardware acceleration)
- API moderna e estável
- Compatibilidade com Flutter 3.44+

Alternativas descartadas:
- `video_player`: Não suporta Windows
- `just_audio`: Requer backend extra; mais limitado em vídeo
- `audioplayers`: Menos robusto para desktop

---

## 2. Instalação

### 2.1 Dependências Base

```yaml
dependencies:
  media_kit: ^1.2.6
  media_kit_video: ^2.0.1  # Widget Video/VideoController; série 2.x (não acompanha a versão do media_kit)
  # Binários nativos (libmpv) — escolher UM pacote de libs, no pubspec do APP:
  media_kit_libs_windows_video: ^1.0.11  # só Windows (o que o smart-core-tenant usa)
  # media_kit_libs_video: ^1.0.7         # agregador Android/iOS/macOS/Windows/Linux
```

> Os pacotes `media_kit_libs_*_video` e `media_kit_libs_*_audio` não se misturam (README oficial).
> O pacote de libs vai no app, não no módulo: o `operacional_module` declara só `media_kit` e
> `media_kit_video`.

### 2.2 Setup por Plataforma

#### Windows
O libmpv **não é baixado em runtime**. Ele vem do pacote `media_kit_libs_windows_video` (ou do
agregador `media_kit_libs_video`): o `CMakeLists.txt` desse plugin baixa o
`mpv-dev-x86_64-*.7z` (e o ANGLE) **durante o build CMake** e copia `libmpv-2.dll` para junto do
executável. Consequências:

- o `flutter build windows` precisa de rede nesse passo (CI incluída) — ou de cache do download;
- o instalador cresce (libmpv + ANGLE);
- sem o pacote de libs o app compila, mas `Player()` falha ao abrir a biblioteca nativa.

No código, chamar `MediaKit.ensureInitialized()` no `main` antes do `runApp`.

```powershell
flutter build windows   # o CMake baixa e empacota o libmpv aqui
```

#### Web
Sem libmpv: o `media_kit` usa o elemento HTML `<video>`/`<audio>` do navegador (via
`package:web`/`dart:js_interop`, compatível com `--wasm`). O suporte a formatos é o do navegador —
ogg/opus funciona no Chrome/Firefox/Edge, mas não em todos os Safari. URL de outro domínio (R2)
exige CORS liberado para o domínio do app.

#### macOS/Linux
```bash
# macOS
brew install libmpv

# Linux (Debian/Ubuntu)
sudo apt-get install libmpv1 libmpv-dev
```

---

## 3. Guia de Uso Rápido

### 3.1 Reprodução Simples de Áudio

```dart
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class AudioPlayerService {
  late final Player player;
  
  AudioPlayerService() {
    player = Player();
  }
  
  Future<void> playAudio(String url) async {
    try {
      await player.open(Media(url));
      await player.play();
    } catch (e) {
      print('Erro: $e');
    }
  }
  
  Future<void> stop() async {
    await player.stop();
  }
  
  void dispose() {
    player.dispose();
  }
}
```

### 3.2 Reprodução com Playlist

```dart
Future<void> playPlaylist(List<String> urls) async {
  final player = Player();
  
  final playlist = Playlist([
    Media('https://example.com/audio1.opus'),
    Media('https://example.com/audio2.opus'),
    Media('https://example.com/audio3.ogg'),
  ]);
  
  await player.open(playlist);
  await player.play();
  
  // Próxima/anterior
  await player.next();
  await player.previous();
}
```

### 3.3 Controles de Reprodução

```dart
Future<void> audioControls(Player player) async {
  // Play/Pause/Stop
  await player.play();
  await player.pause();
  await player.stop();
  
  // Seek
  await player.seek(const Duration(seconds: 30));
  
  // Volume (0.0 - 1.0)
  await player.setVolume(0.5);
  
  // Velocidade
  await player.setRate(1.5);
  
  // Loop
  await player.setPlaylistMode(PlaylistMode.loop);
  
  // Shuffle
  await player.setPlaylistMode(PlaylistMode.shuffle);
}
```

### 3.4 Escutar Estado e Duração

```dart
Future<void> listenToState(Player player) async {
  // Estado de reprodução
  player.stream.playing.listen((isPlaying) {
    print('Reproduzindo: $isPlaying');
  });
  
  // Posição atual
  player.stream.position.listen((position) {
    print('Posição: ${position.inSeconds}s');
  });
  
  // Duração total
  player.stream.duration.listen((duration) {
    print('Duração: ${duration.inSeconds}s');
  });
  
  // Buffer
  player.stream.buffering.listen((isBuffering) {
    print('Buffering: $isBuffering');
  });
  
  // Índice da playlist
  player.stream.playlist.listen((playlist) {
    player.stream.index.listen((index) {
      print('Tocando: ${index + 1}/${playlist.medias.length}');
    });
  });
}
```

### 3.5 Reprodução de OGG/Opus com URL Assinada

```dart
Future<void> playSignedUrl(String signedUrl) async {
  final player = Player();
  
  try {
    // Media_kit detecta tipo pelo mime ou extensão
    final media = Media(
      signedUrl,
      extras: {'title': 'Mensagem de Voz'},
    );
    
    await player.open(media);
    await player.play();
    
    // Escutar conclusão
    player.stream.completed.listen((_) {
      print('Reprodução concluída');
      player.dispose();
    });
    
  } catch (e) {
    print('Erro ao reproduzir: $e');
  }
}
```

### 3.6 Widget para Reprodução

```dart
import 'package:media_kit_video/media_kit_video.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  
  const AudioPlayerWidget({required this.audioUrl});
  
  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final Player player;
  late final VideoController controller;
  
  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    
    player.open(Media(widget.audioUrl));
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder(
          stream: player.stream.playing,
          initialData: false,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return ElevatedButton.icon(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(isPlaying ? 'Pausar' : 'Reproduzir'),
              onPressed: () async {
                if (isPlaying) {
                  await player.pause();
                } else {
                  await player.play();
                }
              },
            );
          },
        ),
        StreamBuilder(
          stream: player.stream.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            return Text('Posição: ${position.inSeconds}s');
          },
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
```

---

## 4. APIs Principais

### Player

| API | Descrição |
|-----|-----------|
| `Player()` | Criar nova instância |
| `open(media)` | Carregar mídia (Media ou Playlist) |
| `play()`, `pause()`, `stop()` | Controles básicos |
| `seek(duration)` | Pular para posição |
| `next()`, `previous()` | Próxima/anterior em playlist |
| `setVolume(double)` | Volume 0.0-1.0 |
| `setRate(double)` | Velocidade de reprodução |
| `setPlaylistMode(mode)` | Loop/shuffle |
| `dispose()` | Liberar recursos |
| `stream.playing` | Stream<bool> |
| `stream.position` | Stream<Duration> |
| `stream.duration` | Stream<Duration> |
| `stream.buffering` | Stream<bool> |
| `stream.completed` | Stream<void> |
| `stream.index` | Stream<int> (playlist) |

### Playlist Mode

```dart
enum PlaylistMode {
  single,     // Parar ao fim
  loop,       // Repetir forever
  loopOne,    // Repetir mesma música
  shuffle,    // Aleatório
}
```

---

## 5. Formatos Suportados

| Formato | Windows | macOS | Linux | Notas |
|---------|---------|-------|-------|-------|
| **OGG/Opus** | ✅ | ✅ | ✅ | Recomendado |
| **MP3** | ✅ | ✅ | ✅ | Compatível |
| **MP4/M4A** | ✅ | ✅ | ✅ | Compatível |
| **WAV** | ✅ | ✅ | ✅ | PCM |
| **FLAC** | ✅ | ✅ | ✅ | Sem perda |
| **WebM** | ✅ | ✅ | ✅ | Vorbis/Opus |
| **AAC** | ✅ | ✅ | ✅ | Em MP4 |

**Streaming:** HLS (.m3u8), DASH (.mpd), HTTP progressive

---

## 6. Tratamento de Erros

```dart
Future<void> robustPlayback(String url) async {
  final player = Player();
  
  try {
    await player.open(Media(url));
    
    // Escutar erros
    player.stream.error.listen((error) {
      print('Erro de playback: $error');
    });
    
    await player.play();
    
  } on PlayerException catch (e) {
    print('Erro do player: ${e.message}');
  } catch (e) {
    print('Erro desconhecido: $e');
  } finally {
    await player.dispose();
  }
}
```

---

## 7. Suporte por Plataforma

| Plataforma | Suporte | Requer |
|-----------|---------|--------|
| **Windows** | ✅ Completo | `media_kit_libs_windows_video` (libmpv baixado no build CMake) |
| macOS | ✅ Completo | `media_kit_libs_macos_video` |
| Linux | ✅ Completo | `media_kit_libs_linux` + libmpv do sistema (`libmpv-dev`) |
| Android | ✅ Completo | `media_kit_libs_android_video` |
| iOS | ✅ Completo | `media_kit_libs_ios_video` |
| Web | ✅ Suportado (README oficial) | Nada: usa `<video>` do navegador; formatos limitados ao navegador; compila com `--wasm` (imports condicionais por `dart.library.js_interop`) |

> Correção (P2a, 2026-10-02): a versão anterior desta tabela dizia "Web ❌" e "mpv baixado
> automaticamente" — ambos errados frente ao README oficial e ao `CMakeLists.txt` do pacote de libs.

---

## 8. Comparação com Alternativas

| Lib | Windows | OGG/Opus | Desktop | API Moderna |
|-----|---------|----------|---------|-------------|
| **media_kit** | ✅ | ✅ | ✅ | ✅ |
| just_audio | ⚠️ (backend) | ⚠️ (media_kit) | ✅ | ✅ |
| video_player | ❌ | ❌ | ❌ | ✅ |
| audioplayers | ✅ | ⚠️ | ❌ | ⚠️ |

---

## 9. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 1.2.6 | 2026-10-01 | EM_HOMOLOGACAO para Windows desktop; ogg/opus nativo; performance superior; recomendado para áudio/vídeo em desktop |
| 1.2.6 | 2026-10-02 | P2a (correcoes-app-windows-flutter): adotado na bolha do chat (`operacional_module`) com `media_kit_video` 2.0.1 e `media_kit_libs_windows_video` 1.0.11 no app; corrigidos §2.2 e §7 (libmpv vem do pacote de libs no build; Web suportada) |

---

## 10. Referências

- **Pub.dev:** https://pub.dev/packages/media_kit
- **Repositório:** https://github.com/media-kit/media_kit
- **Documentação:** https://media-kit.js.org/
- **libmpv:** https://github.com/mpv-player/mpv

