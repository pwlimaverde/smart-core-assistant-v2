# Photo View

- **Versão Recomendada:** 0.14.0 (compatível com Flutter 3.12.2/Dart 3.12)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Propósito no Projeto:** Widget interativo para visualização de imagens com zoom, pan, galeria lightbox e hero animations; multiplataforma (Web e Windows).
- **Documentação Oficial:** [https://github.com/bluefireteam/photo_view](https://github.com/bluefireteam/photo_view)
- **Source (Context7):** `/bluefireteam/photo_view` | Reputation: High | Code Snippets: 16

---

## 1. Suporte por Plataforma

| Plataforma | Suporte | Observações |
|------------|---------|-------------|
| **Flutter Web** | ✅ Completo | Zoom pinch, pan, double-tap funcionam nativamente |
| **Windows Desktop** | ✅ Completo | Zoom via scroll, pan via arrastar, double-tap |
| Android | ✅ Completo | Gesto nativo de pinch-zoom |
| iOS | ✅ Completo | Gesto nativo de pinch-zoom |
| macOS | ✅ Completo | Zoom via scroll, pan via arrastar |
| Linux | ✅ Completo | Zoom via scroll, pan via arrastar |

**Nota:** photo_view é agnóstico de plataforma — funciona em qualquer lugar que Flutter roda.

---

## 2. Guia de Uso Rápido

### 2.1 Instalação

```yaml
dependencies:
  photo_view: ^0.14.0
```

### 2.2 Visualizador Simples de Imagem

```dart
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class SimplePhotoView extends StatelessWidget {
  const SimplePhotoView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visualizar Imagem')),
      body: PhotoView(
        imageProvider: AssetImage('assets/large-image.jpg'),
      ),
    );
  }
}
```

### 2.3 PhotoView com Imagem de URL

```dart
class UrlPhotoView extends StatelessWidget {
  const UrlPhotoView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PhotoView(
        imageProvider: NetworkImage(
          'https://example.com/image.jpg',
        ),
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null
                ? 0
                : event.cumulativeBytesLoaded / event.expectedTotalBytes,
          ),
        ),
      ),
    );
  }
}
```

### 2.4 Galeria Lightbox (PhotoViewGallery)

```dart
class PhotoGallery extends StatefulWidget {
  final List<String> imageUrls;

  const PhotoGallery({super.key, required this.imageUrls});

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Imagem ${_currentIndex + 1} de ${widget.imageUrls.length}'),
      ),
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        builder: (BuildContext context, int index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(widget.imageUrls[index]),
            initialScale: PhotoViewComputedScale.contained * 0.8,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2.0,
          );
        },
        itemCount: widget.imageUrls.length,
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null
                ? 0
                : event.cumulativeBytesLoaded / event.expectedTotalBytes,
          ),
        ),
        pageController: _pageController,
        onPageChanged: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundDecoration: const BoxDecoration(
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
```

### 2.5 Customização de Zoom (Min/Max Scale)

```dart
PhotoView(
  imageProvider: AssetImage('assets/image.jpg'),
  minScale: PhotoViewComputedScale.contained,   // Mínimo: cabe na tela
  maxScale: PhotoViewComputedScale.covered * 3.0, // Máximo: 3x zoom
  initialScale: PhotoViewComputedScale.contained * 0.9,
)
```

### 2.6 PhotoViewComputedScale Valores

```dart
// PhotoViewComputedScale é um enum com 2 constantes

// 1. contained: Imagem inteira visível na tela (fit contido)
PhotoViewComputedScale.contained       // 1.0 (tamanho mínimo para caber)
PhotoViewComputedScale.contained * 0.8 // 0.8x zoom

// 2. covered: Imagem preenche a tela inteira (crop se necessário)
PhotoViewComputedScale.covered         // ~1.5 (depende da proportção)
PhotoViewComputedScale.covered * 2.0   // 2.0x zoom

// Multiplicadores funcionam em ambos
PhotoViewComputedScale.contained / 2   // 0.5x zoom
PhotoViewComputedScale.covered * 1.5   // 1.5x zoom
```

### 2.7 Callback de Mudança de Zoom

```dart
class PhotoViewWithZoomCallback extends StatefulWidget {
  const PhotoViewWithZoomCallback({super.key});

  @override
  State<PhotoViewWithZoomCallback> createState() => _PhotoViewWithZoomCallbackState();
}

class _PhotoViewWithZoomCallbackState extends State<PhotoViewWithZoomCallback> {
  String _zoomState = 'normal';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PhotoView(
            imageProvider: AssetImage('assets/image.jpg'),
            scaleStateChangedCallback: (PhotoViewScaleState scaleState) {
              setState(() {
                _zoomState = scaleState.toString();
              });
            },
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Text(
              'Estado: $_zoomState',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
```

### 2.8 Hero Animation (Transição Suave)

```dart
class ImageThumbList extends StatelessWidget {
  final List<String> imageUrls;

  const ImageThumbList({super.key, required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
      ),
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: PhotoViewGallery.builder(
                  builder: (context, idx) {
                    return PhotoViewGalleryPageOptions(
                      imageProvider: NetworkImage(imageUrls[idx]),
                      // Hero animation do thumb para fullscreen
                      heroAttributes: PhotoViewHeroAttributes(
                        tag: 'image-$idx',
                      ),
                    );
                  },
                  itemCount: imageUrls.length,
                  pageController: PageController(initialPage: index),
                ),
              ),
            ),
          ),
          child: Hero(
            tag: 'image-$index',
            child: Image.network(
              imageUrls[index],
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
```

### 2.9 Renderizar Conteúdo Customizado (SVG, Widget)

```dart
PhotoView.customChild(
  child: SvgPicture.asset('assets/diagram.svg'),
  initialScale: PhotoViewComputedScale.contained,
  minScale: PhotoViewComputedScale.contained * 0.8,
  maxScale: PhotoViewComputedScale.covered * 2.0,
)

// Ou com qualquer widget
PhotoView.customChild(
  child: Container(
    color: Colors.blue,
    child: const Center(
      child: Text('Conteúdo customizado'),
    ),
  ),
)
```

### 2.10 Tratamento de Erro ao Carregar Imagem

```dart
PhotoView(
  imageProvider: NetworkImage('https://example.com/image.jpg'),
  loadingBuilder: (context, event) {
    if (event == null) return const SizedBox.shrink();
    return Center(
      child: CircularProgressIndicator(
        value: event.cumulativeBytesLoaded / event.expectedTotalBytes,
      ),
    );
  },
  errorBuilder: (context, error, stackTrace) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported, size: 64),
          const SizedBox(height: 16),
          Text('Erro ao carregar imagem: $error'),
        ],
      ),
    );
  },
)
```

---

## 3. PhotoView vs PhotoViewGallery

| Propriedade | PhotoView | PhotoViewGallery |
|---|---|---|
| Única imagem | ✅ | ❌ |
| Múltiplas imagens | ❌ | ✅ |
| Navegação entre imagens | ❌ | ✅ Swipe |
| Customização de escala | ✅ | ✅ |
| Hero animation | Via código | Via `PhotoViewHeroAttributes` |
| Callback de zoom | ✅ | ✅ `scaleStateChangedCallback` |

---

## 4. APIs Principais

| API | Descrição |
|-----|-----------|
| `PhotoView(imageProvider:)` | Widget para imagem única |
| `PhotoView.customChild(child:)` | Widget customizado com zoom |
| `PhotoViewGallery.builder()` | Galeria com múltiplas imagens |
| `PhotoViewGalleryPageOptions` | Opções por página da galeria |
| `PhotoViewComputedScale.contained` | Zoom: imagem cabe na tela |
| `PhotoViewComputedScale.covered` | Zoom: imagem preenche a tela |
| `minScale`, `maxScale` | Limites de zoom (double ou PhotoViewComputedScale) |
| `initialScale` | Zoom inicial |
| `scaleStateChangedCallback` | Callback quando zoom muda |
| `loadingBuilder` | Widget enquanto carrega |
| `errorBuilder` | Widget em caso de erro |
| `backgroundDecoration` | Background da galeria |
| `pageController` | Controlar posição na galeria |
| `onPageChanged` | Callback de mudança de página |
| `PhotoViewHeroAttributes` | Hero animation para galeria |

---

## 5. Padrão Recomendado para Visualizador de Mensagens

```dart
class MessageImageViewer extends StatelessWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const MessageImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text('${initialIndex + 1} de ${imageUrls.length}'),
      ),
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(imageUrls[index]),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2.5,
          );
        },
        itemCount: imageUrls.length,
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null ? 0 : event.cumulativeBytesLoaded / event.expectedTotalBytes,
          ),
        ),
        pageController: PageController(initialPage: initialIndex),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}
```

---

## 6. Breaking Changes

### v0.12.0 → v0.13.0

- `basePosition` agora é parâmetro nomeado (não posicional)
- Remoção de `PhotoViewImageProvider` deprecado

### v0.14.0+

- Compatibilidade melhorada com Dart 3.12+
- Melhorias em performance de renderização
- Suporte aprimorado a gestos em Web

---

## 7. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 0.14.0 | 2026-08-09 | Versão estável; suporte multiplataforma (Web, Windows, mobile); zoom interativo, galeriatab e hero animations funcionam perfeitamente |
