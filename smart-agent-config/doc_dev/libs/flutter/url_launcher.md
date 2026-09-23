# url_launcher

- **Versão Recomendada:** 6.3.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-19
- **Propósito no Projeto:** Abrir links de download da versão nova do app Windows (P11) e links externos em navegador do sistema ou in-app browser
- **Documentação Oficial:** https://pub.dev/packages/url_launcher

---

## Histórico de Atualizações

- **2026-09-19** — Documentação inicial. Versão 6.3.2 com foco em `launchUrl()`, `canLaunchUrl()`, suporte Windows desktop, Flutter Web/WASM, tratamento de erros e testes via mock da plataforma.

---

## 1. Instalação

```yaml
# pubspec.yaml
dependencies:
  url_launcher: ^6.3.2
```

**Requisitos Mínimos:**
- Flutter: 3.27+
- Dart: 3.6+
- Android: SDK 21+
- iOS: 12.0+
- macOS: 10.14+
- Windows: 10+
- Linux: qualquer versão
- Web: qualquer navegador moderno

---

## 2. API Central

### 2.1 Lançar URL com `launchUrl()`

```dart
import 'package:url_launcher/url_launcher.dart';

Future<void> abrirLink(String urlString) async {
  final Uri url = Uri.parse(urlString);
  
  if (await canLaunchUrl(url)) {
    // Abrir no aplicativo padrão do sistema
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    // Tratar erro: scheme não suportado ou URL inválida
    throw 'Não foi possível abrir a URL: $url';
  }
}
```

**Parâmetros principais:**
- `url` (**Uri**): URL a ser aberta (prefira `Uri.parse()` para encoding correto).
- `mode` (**LaunchMode**): Define onde abrir o link:
  - `LaunchMode.externalApplication` ⭐ **Recomendado para links externos**: abre no navegador do sistema ou aplicativo padrão.
  - `LaunchMode.inAppBrowserView`: abre em um navegador customizado dentro do app (uso: documentação interna, PDFs).
  - `LaunchMode.inAppWebView` (depreciado): substitua por `inAppBrowserView`.

### 2.2 Verificar suporte prévio com `canLaunchUrl()`

```dart
import 'package:url_launcher/url_launcher.dart';

final Uri urlTel = Uri(scheme: 'tel', path: '5511999999999');

// Verificar se o dispositivo pode fazer chamadas
if (await canLaunchUrl(urlTel)) {
  // Seguro disparar launchUrl()
} else {
  // Plano B: exibir campo de input para copiar ou fallback
}
```

⚠️ **Caveat:** `canLaunchUrl()` pode retornar `false` mesmo que `launchUrl()` funcionasse em cenários raros (ex: URLs genéricas em Web). Use como **guia heurístico**, não garantia absoluta.

### 2.3 Esquemas de URL suportados

| Esquema | Exemplo | Comportamento |
|---------|---------|---------------|
| `https://` | `https://example.com` | Abre navegador padrão |
| `mailto:` | `mailto:user@example.com?subject=Teste` | Abre app de email |
| `tel:` | `tel:+5511999999999` | Inicia chamada telefônica (mobile) |
| `sms:` | `sms:+5511999999999?body=Olá` | Abre app de SMS (mobile) |
| `file://` | `file:///path/to/file.pdf` | Abre gestor de arquivos (desktop) |

---

## 3. Comportamento em Windows Desktop

**Plataforma Primária para P11 (Aviso de Versão Nova):**

```dart
// Exemplo: abrir download da versão nova do app Windows
Future<void> baixarNovaVersao(String downloadUrl) async {
  final Uri url = Uri.parse(downloadUrl);
  
  try {
    final bool launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    
    if (!launched) {
      // Fallback: copiar URL para clipboard ou exibir diálogo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir. URL: $url')),
      );
    }
  } catch (e) {
    // Logging e tratamento de exceção
    print('Erro ao abrir URL: $e');
  }
}
```

**Comportamento específico:**
- ✅ Abre no navegador padrão (Edge, Chrome, Firefox conforme configuração).
- ✅ `LaunchMode.externalApplication` é a **opção preferida** para Desktop.
- ✅ Suporte a `file://` para abrir exploradores de arquivos ou documentos locais.
- ⚠️ **UDS vs TCP**: se usar `url_launcher` em contexto com isolates ou serviços de background, verificar configuração de endpoints (memória de projeto: "Transport em Windows usa TCP").

---

## 4. Comportamento em Flutter Web (Incluindo WASM)

**Limitações e Recomendações:**

```dart
// Padrão web-safe para launchUrl() em Flutter Web
Future<void> abrirLinkWeb(String urlString) async {
  final Uri url = Uri.parse(urlString);
  
  // Web requer ação do usuário (clique de botão)
  // Já estamos dentro de um onPressed/onTap? ✓
  // Fora de um handler? Navegador pode bloquear.
  
  try {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } on PlatformException catch (e) {
    print('Web blocking: $e');
  }
}
```

**Plataforma Details:**
- **HTTPS/HTTP:** ✅ suportado (abre nova aba/janela).
- **WASM build (`flutter build web --wasm`):** ✅ compatível (sem restrições extras).
- **Contexto obrigatório:** Link deve ser acionado por interação do usuário (clique de botão, toque em card). Lançamentos não-iniciados pelo usuário (ex: no `initState`) podem ser bloqueados pelo navegador.
- **Cross-origin:** navegadores modernos respeitam `rel="noopener"` automaticamente para `launchUrl()` com `externalApplication`.
- **`canLaunchUrl()` em Web:** sempre retorna `true` para esquemas `https` (navegadores aceitam tudo), mas pode falhar se chamado fora de um handler (async gap).

---

## 5. Tratamento de Erros e Retorno Falso

### 5.1 Padrão de Tratamento Recomendado

```dart
import 'package:url_launcher/url_launcher.dart';

Future<bool> abrirURLComTratamento(Uri url) async {
  try {
    // Verificar suporte (heurístico)
    if (!await canLaunchUrl(url)) {
      print('Esquema não suportado: $url');
      return false;
    }
    
    // Tentar lançar
    final bool launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    
    if (!launched) {
      // launchUrl() retornou false = falha na plataforma
      print('launchUrl() falhou para: $url');
      return false;
    }
    
    return true;
  } on PlatformException catch (e) {
    // Exceção da plataforma (ex: URL inválida, permissão negada)
    print('PlatformException em url_launcher: ${e.code} — ${e.message}');
    return false;
  } catch (e) {
    print('Erro inesperado: $e');
    return false;
  }
}
```

### 5.2 Semântica do Retorno `false`

- `launchUrl()` **retorna `true`** → URL foi passada ao sistema com sucesso.
- `launchUrl()` **retorna `false`** → Sistema não conseguiu processar (app não encontrado, esquema inválido, permissão negada).
- **Exceção `PlatformException`** → Erro na plataforma nativa (raro; ex: argumento malformado em Android).

⚠️ **Nota para P11:** se o download URL falhar, exibir diálogo com fallback (copiar URL, link alternativo, instruções manuais).

---

## 6. Configuração Obrigatória por Plataforma

### Android (SDK 30+)

```xml
<!-- AndroidManifest.xml -->
<manifest>
  <queries>
    <intent>
      <action android:name="android.intent.action.VIEW" />
      <data android:scheme="https" />
    </intent>
  </queries>
</manifest>
```

### iOS

```xml
<!-- ios/Runner/Info.plist -->
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>https</string>
  <string>http</string>
</array>
```

Windows e macOS não requerem configuração extra.

---

## 7. Testes com Mock da Plataforma

### 7.1 Fake Implementation para Widget Tests

```dart
// test/fakes/fake_url_launcher.dart
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class FakeUrlLauncher extends UrlLauncherPlatform {
  bool shouldSucceed = true;
  bool canLaunchResult = true;
  List<String> launchedUrls = [];

  @override
  Future<bool> canLaunchUrl(String url) async {
    return canLaunchResult;
  }

  @override
  Future<bool> launchUrl(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return shouldSucceed;
  }

  // Métodos obrigatórios da interface (podem retornar valores padrão)
  @override
  Future<bool> closeWebView() async => true;
}
```

### 7.2 Uso em Testes

```dart
// test/widgets/new_version_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../fakes/fake_url_launcher.dart';

void main() {
  group('Diálogo de Versão Nova', () {
    late FakeUrlLauncher fakeUrlLauncher;

    setUp(() {
      fakeUrlLauncher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = fakeUrlLauncher;
    });

    testWidgets('Ao clicar em "Baixar", abre o link', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () => launchUrl(
                Uri.parse('https://example.com/download/app.exe'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Baixar Versão Nova'),
            ),
          ),
        ),
      );

      // Simular clique
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // Verificar que o fake foi chamado
      expect(fakeUrlLauncher.launchedUrls, contains('https://example.com/download/app.exe'));
    });

    testWidgets('Se launch falhar, exibe mensagem de erro', (WidgetTester tester) async {
      fakeUrlLauncher.shouldSucceed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final success = await launchUrl(
                  Uri.parse('https://example.com/download/app.exe'),
                  mode: LaunchMode.externalApplication,
                );
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Erro ao abrir link')),
                  );
                }
              },
              child: const Text('Baixar'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Erro ao abrir link'), findsOneWidget);
    });
  });
}
```

### 7.3 Testes de Integração (Opcional)

Para testes E2E ou integração real:

```dart
// test/integration_test/url_launcher_test.dart
// Executar com: flutter drive --driver=test_driver/integration_test.dart ...

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Real URL launch (integration)', (WidgetTester tester) async {
    final Uri url = Uri.parse('https://example.com');
    
    // Verificar que canLaunchUrl não falha
    final canLaunch = await canLaunchUrl(url);
    expect(canLaunch, isTrue);

    // Não vamos realmente abrir (evita popup), mas verificamos que a chamada não gera exceção
    try {
      // Em CI/CD ou desktop sem navegador, isso pode falhar —esperado
      await launchUrl(url);
    } on Exception catch (e) {
      print('Esperado em ambiente headless: $e');
    }
  });
}
```

---

## 8. Breaking Changes desde v6.3

| Versão | Mudança | Impacto |
|--------|---------|--------|
| **6.3.0+** | Parâmetro `forceSafariVC` + `forceWebView` com não-web schemes lança `PlatformException` | Evitar combinações inválidas; validar modo antes de lançar |
| **6.3.1** | Aumento de mínimo Dart SDK para 3.3 | Atualizar ambiente se necessário |
| **6.3.2** | Aumento de mínimo Flutter para 3.27 e Dart 3.6 | Atualizar projeto (já vigente em 2026) |

**Nenhuma breaking change de API** entre 6.3.0 e 6.3.2 — apenas tightening de requisitos.

---

## 9. Referências

| Recurso | Link |
|---------|------|
| Pub.dev | https://pub.dev/packages/url_launcher |
| Repositório | https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher |
| API Docs | https://pub.dev/documentation/url_launcher/latest/ |
| Platform Interface | https://pub.dev/packages/url_launcher_platform_interface |
| Changelog | https://pub.dev/packages/url_launcher/changelog |
