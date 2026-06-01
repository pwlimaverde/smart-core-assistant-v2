# Path Provider (path_provider)

- **Versão Recomendada:** 2.1.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Localização multiplataforma de diretórios de arquivos no sistema operacional (Windows) para armazenamento persistente de mídias baixadas (cache de imagem, áudio) e índice do banco local.
- **Documentação Oficial:** [https://pub.dev/packages/path_provider](https://pub.dev/packages/path_provider)

---

## 1. Contexto e Uso no Projeto

Conforme a estratégia de mídia local (§9 do planejamento), o binário nativo em Rust (`local_engine`) persiste arquivos de mídia no disco rígido do atendente para evitar download recorrente. O aplicativo Flutter deve obter o caminho de armazenamento correto fornecido pelo sistema operacional Windows e fornecê-lo ao inicializar o motor Rust via FFI.

O pacote **`path_provider`** resolve essas localizações de forma segura respeitando as permissões de Sandbox e diretórios de dados de usuário do Windows.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Localização do Diretório de Dados do Aplicativo
No Windows, os dados do cache local e arquivos persistentes nunca devem ser salvos na pasta temporária ou de instalação do executável (que pode exigir permissões de administrador). Sempre utilize `getApplicationSupportDirectory()`, que aponta para a pasta `AppData\Local\<empresa>\<app>` do usuário corrente.

```dart
import 'package:path_provider/path_provider.dart';
import 'dart:io';

Future<Directory> getLocalMediaCacheDirectory() async {
  // Retorna ex: C:\Users\Nome\AppData\Local\SmartCore\SupportApp
  final Directory supportDir = await getApplicationSupportDirectory();
  
  // Cria uma subpasta dedicada para mídias
  final mediaDir = Directory("${supportDir.path}/media_cache");
  if (!await mediaDir.exists()) {
    await mediaDir.create(recursive: true);
  }
  
  return mediaDir;
}
```

### 2.2 Compartilhamento com o Motor FFI
O caminho obtido pelo `path_provider` em Dart deve ser passado como string para a FFI em Rust durante o bootstrap da aplicação. O Rust utilizará esse diretório para ler/escrever o arquivo SQLite e armazenar os bytes das fotos/áudios.

```dart
Future<void> bootstrapLocalEngine() async {
  final supportDir = await getApplicationSupportDirectory();
  
  final dbPath = "${supportDir.path}/local_index.db";
  final mediaFolder = "${supportDir.path}/media_cache";

  // Inicia a FFI passando os caminhos corretos do Windows
  await LocalEngineFFI.init(
    databasePath: dbPath,
    mediaStoragePath: mediaFolder,
  );
}
```

### 2.3 Resiliência de I/O de Arquivos
Operações de leitura e gravação física em disco do Windows podem falhar caso o usuário fique sem espaço de disco ou o antivírus bloqueie a pasta local. Sempre trate erros de I/O em bloco try-catch do Dart/Rust e execute limpezas periódicas de mídias antigas (cache LRU) para respeitar limites de armazenamento em disco.
