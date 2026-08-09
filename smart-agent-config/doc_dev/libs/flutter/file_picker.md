# File Picker

- **Versão Recomendada:** 11.0.2 (compatível com Flutter 3.12.2/Dart 3.12)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Propósito no Projeto:** Seleção nativa de arquivos (imagem, vídeo, áudio, PDF, docx, xlsx) com suporte a múltiplos arquivos, filtragem de extensões e obtenção de bytes em Web e path em Desktop.
- **Documentação Oficial:** [https://pub.dev/packages/file_picker](https://pub.dev/packages/file_picker)
- **Source (Context7):** `/websites/pub_dev_packages_file_picker` | Reputation: High | Code Snippets: 26

---

## 1. Suporte por Plataforma

| Plataforma | Suporte | Observações |
|------------|---------|-------------|
| **Flutter Web** | ✅ Completo | Retorna bytes (Uint8List) via `result.files.first.bytes` |
| **Windows Desktop** | ✅ Completo | Retorna path do arquivo via `result.files.first.path` |
| Android | ✅ Completo | Via Android intent |
| iOS | ✅ Completo | Via UIDocumentPickerViewController |
| macOS | ✅ Completo | Via NSOpenPanel |
| Linux | ✅ Completo | Via GTK file picker |

---

## 2. Guia de Uso Rápido

### 2.1 Instalação

```yaml
dependencies:
  file_picker: ^11.0.2
```

### 2.2 Seleção Simples de Arquivo

```dart
import 'package:file_picker/file_picker.dart';

Future<void> pickSingleFile() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'png', 'pdf', 'doc', 'docx', 'xlsx'],
  );

  if (result != null) {
    PlatformFile file = result.files.first;
    
    print('Nome: ${file.name}');
    print('Tamanho: ${file.size} bytes');
    print('Extensão: ${file.extension}');
    
    // Em Web: bytes disponível
    if (file.bytes != null) {
      print('Bytes: ${file.bytes!.length}');
    }
    
    // Em Desktop: path disponível
    if (file.path != null) {
      print('Path: ${file.path}');
    }
  }
}
```

### 2.3 Seleção Múltipla de Arquivos

```dart
Future<void> pickMultipleFiles() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.video,
    allowMultiple: true,
  );

  if (result != null) {
    for (PlatformFile file in result.files) {
      print('Arquivo: ${file.name}');
    }
  }
}
```

### 2.4 Upload para Firebase Storage (Web)

```dart
Future<void> uploadToFirebase() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.image,
  );

  if (result != null) {
    Uint8List fileBytes = result.files.first.bytes!;
    String fileName = result.files.first.name;
    
    await FirebaseStorage.instance
      .ref('uploads/$fileName')
      .putData(fileBytes);
  }
}
```

### 2.5 Tratamento de Permissões e Cancelamento

```dart
Future<void> pickFileWithErrorHandling() async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result == null) {
      // Usuário cancelou
      print('Seleção cancelada');
      return;
    }

    // Verificar tamanho (ex: máximo 50MB)
    const maxSizeBytes = 50 * 1024 * 1024;
    if (result.files.first.size > maxSizeBytes) {
      print('Arquivo excede limite de 50MB');
      return;
    }

    // Processar arquivo
  } catch (e) {
    print('Erro ao selecionar arquivo: $e');
  }
}
```

### 2.6 Seleção de Diretório

```dart
Future<void> pickDirectory() async {
  String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
  
  if (selectedDirectory != null) {
    print('Diretório selecionado: $selectedDirectory');
  }
}
```

---

## 3. Diferenças Web vs Desktop

### Em Web (Retorna Bytes)
```dart
// Web sempre retorna bytes
Uint8List? bytes = result.files.first.bytes;
// path é null em Web
```

### Em Desktop (Retorna Path)
```dart
// Desktop retorna path do arquivo
String? path = result.files.first.path;
// bytes pode ser null (arquivo grande não é carregado em memória)
```

---

## 4. APIs Importantes

| API | Descrição |
|-----|-----------|
| `FilePicker.platform.pickFiles()` | Abre seletor de arquivo nativo |
| `FilePicker.platform.getDirectoryPath()` | Seleciona diretório (algumas plataformas) |
| `FilePicker.platform.clearTemporaryFiles()` | Limpa arquivos temporários |
| `result.files` | Lista de `PlatformFile` selecionados |
| `file.bytes` | Uint8List (Web) |
| `file.path` | Path (Desktop) |
| `file.name`, `file.size`, `file.extension` | Metadados |

---

## 5. Filtros de Tipo Suportados

```dart
// Tipos pré-definidos
FileType.any       // Todos os arquivos
FileType.audio     // .aac, .m4a, .mp3, .wav, etc
FileType.custom    // Extensões customizadas
FileType.image     // .jpg, .png, .gif, .bmp, .webp
FileType.media     // Áudio + Vídeo
FileType.video     // .mp4, .avi, .mov, .mkv, etc

// Extensões customizadas
allowedExtensions: ['pdf', 'docx', 'xlsx', 'jpg', 'png']
```

---

## 6. Breaking Changes

### v10.0.0 → v11.0.0 (Recente)

- Melhoria em tratamento de permissões em Web
- Suporte expandido para MIME types customizados
- Deprecado: `FilePicker.pickFiles()` (usar `FilePicker.platform.pickFiles()`)

---

## 7. Histórico de Atualizações

| Versão | Data | Motivo |
|--------|------|--------|
| 11.0.2 | 2026-08-09 | Versão estável atual; suporte completo a Web e Windows; compatível com Flutter 3.12.2 |
