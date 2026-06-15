# flutter_secure_storage

- **Versão Recomendada:** 9.x (atual 9.2.3+)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Persistência segura do refresh token no smart-core-admin (implementação real do `LocalStorageService`); access token nunca é persistido, fica apenas em memória
- **Documentação Oficial:** https://pub.dev/packages/flutter_secure_storage
- **Library ID Context7:** `/websites/pub_dev_packages_flutter_secure_storage`

---

## API Básica

A classe principal é `FlutterSecureStorage()`. No Flutter Web (WASM), ela utiliza **Web Cryptography API** para criptografia local no browser.

### Inicialização

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final _storage = FlutterSecureStorage(
  // Configurações específicas por plataforma (Android/iOS/macOS/Windows)
  aOptions: const AndroidOptions(
    biometricPromptTitle: 'Smart Core Admin',
    biometricPromptSubtitle: 'Desbloqueie para acessar o token',
  ),
  iOptions: const IOSOptions(
    accountName: 'com.smartcore.admin',
    synchronizable: true,
  ),
  mOptions: const MacOsOptions(
    accountName: 'com.smartcore.admin',
    synchronizable: true,
  ),
  // Web será configurado automaticamente para WASM
);
```

### Escrita (write)

```dart
/// Persiste uma chave-valor de forma criptografada
Future<void> saveRefreshToken(String token) async {
  try {
    await _storage.write(
      key: 'auth_refresh_token',
      value: token,
    );
  } catch (e) {
    // Tratar erro de persistência
  }
}
```

**Assinatura:**
```dart
Future<void> write({
  required String key,
  required String value,
  // Demais parâmetros opcionais dependem da plataforma
})
```

### Leitura (read)

```dart
/// Recupera um valor criptografado; retorna null se a chave não existe
Future<String?> getRefreshToken() async {
  try {
    final token = await _storage.read(key: 'auth_refresh_token');
    return token; // null se não encontrado
  } catch (e) {
    // Tratar erro de leitura (ex: dados corrompidos)
    return null;
  }
}
```

**Assinatura:**
```dart
Future<String?> read({
  required String key,
})
```

### Verificação de Existência (containsKey)

```dart
/// Verifica se uma chave existe sem recuperar o valor
Future<bool> hasRefreshToken() async {
  try {
    return await _storage.containsKey(key: 'auth_refresh_token');
  } catch (e) {
    return false;
  }
}
```

**Assinatura:**
```dart
Future<bool> containsKey({
  required String key,
})
```

### Deleção Individual (delete)

```dart
/// Remove uma chave-valor específica
Future<void> clearRefreshToken() async {
  try {
    await _storage.delete(key: 'auth_refresh_token');
  } catch (e) {
    // Tratar erro
  }
}
```

**Assinatura:**
```dart
Future<void> delete({
  required String key,
})
```

### Deleção Total (deleteAll)

```dart
/// Remove TODAS as chaves armazenadas (cuidado!)
Future<void> clearAllStoredData() async {
  try {
    await _storage.deleteAll();
  } catch (e) {
    // Tratar erro
  }
}
```

**Assinatura:**
```dart
Future<void> deleteAll()
```

---

## Comportamento Específico no Web (WebOptions e WASM)

### Como Funciona no Browser

No Flutter Web compilado para **WebAssembly (WASM)**, o `flutter_secure_storage`:

1. **Armazenamento:** Utiliza `localStorage` do browser como backend
2. **Criptografia:** Usa **Web Cryptography API** (`SubtleCrypto`) para criptografar os valores ANTES de armazená-los
3. **Chave de Criptografia:** A chave é derivada internamente (não é exposta ao JS)

### Configuração WebOptions (v9.2.3+)

```dart
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';

final _storage = FlutterSecureStorage(
  // Deixar webOptions como default para a maioria dos casos
  // Ou personalizar:
);

// Você pode controlar via WebOptions:
// - useSessionStorage: bool (padrão false → usa localStorage)
// - wrapKey: bool (padrão true → habilita key wrapping adicional)
// - wrapKeyIv: String? (IV customizado para key wrapping)
```

**Importante (v10.0.0+):** Web foi migrado para ser **totalmente compatível com WASM** removendo dependências `dart:io`. A opção `useSessionStorage` permite escolher entre:
- `false` (padrão): `localStorage` — persiste entre abas/sessões
- `true`: `sessionStorage` — limpo ao fechar a aba

Para o refresh token no smart-core-admin, recomenda-se **manter `useSessionStorage: false`** (localStorage) para facilitar a persistência entre sessões do navegador.

### Limitações de Segurança Críticas no Web

⚠️ **XSS (Cross-Site Scripting) — Maior Risco**
- Se um atacante injetar JavaScript malicioso via XSS, ele poderá:
  - Acessar o `localStorage` criptografado (pode ler valores brutos)
  - Potencialmente derivar/interceptar a chave de criptografia se conseguir executar código no contexto da página
  - **Mitigação:** Content Security Policy (CSP) rigorosa, sanitização de inputs, não fazer eval()

⚠️ **localStorage vs sessionStorage**
- `localStorage` persiste entre abas — risco aumentado de exposição se o dispositivo for compartilhado
- `sessionStorage` limpa ao fechar — mais seguro, mas perde tokens ao fechar a aba

⚠️ **Sem Biometria no Web**
- Diferente de iOS/Android, **não há suporte a autenticação biométrica** no Web (API Web não oferece)
- O navegador não oferece isolamento de memória como um keychain

⚠️ **HTTPS Obrigatório**
- A biblioteca está **restrita a HTTPS ou localhost**
- Em HTTP, Web Cryptography API não funciona (segurança do browser)
- Certifique-se de que **HSTS headers estão configurados** no servidor

### Verificação no Boot

```dart
/// No initState da app, verificar e recuperar refresh token
@override
void initState() {
  super.initState();
  _initializeAuth();
}

Future<void> _initializeAuth() async {
  try {
    // Tentar recuperar refresh token persistido
    final refreshToken = await _storage.read(key: 'auth_refresh_token');
    
    if (refreshToken != null && refreshToken.isNotEmpty) {
      // Usar o token para fazer refresh automático
      await _authService.refreshAccessToken(refreshToken);
    } else {
      // Nenhum token persistido — redirecionar para login
      _navigateToLogin();
    }
  } on PlatformException catch (e) {
    // Erro ao ler storage — pode indicar dados corrompidos
    logger.e('Erro ao ler refresh token: ${e.message}');
    _navigateToLogin();
  } catch (e) {
    logger.e('Erro inesperado na inicialização de auth: $e');
    _navigateToLogin();
  }
}
```

---

## Boas Práticas para Guardar Tokens

### 1. Namespacing de Chaves

Use namespaces descritivos e evite conflitos:

```dart
// ✅ BOM: específico e namespaceado
const String REFRESH_TOKEN_KEY = 'smartcore_admin_auth_refresh_token';
const String ACCESS_TOKEN_KEY = 'smartcore_admin_auth_access_token'; // NUNCA PERSISTIR

// ❌ RUIM: muito genérico
const String TOKEN_KEY = 'token';
```

### 2. Access Token vs Refresh Token

```dart
class AuthTokenStorage {
  static const _refreshTokenKey = 'smartcore_admin_auth_refresh_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Persiste APENAS o refresh token
  Future<void> saveRefreshToken(String refreshToken) async {
    await _storage.write(
      key: _refreshTokenKey,
      value: refreshToken,
    );
  }

  /// Recupera o refresh token para fazer refresh do access token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// Limpa o refresh token no logout
  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Access token NUNCA é persistido — fica em memória na classe AuthService
}
```

### 3. Tratamento de Null na Leitura

```dart
/// Sempre verificar null no boot
Future<bool> tryRestoreSession() async {
  final refreshToken = await _storage.read(key: 'smartcore_admin_auth_refresh_token');
  
  // Null = não há sessão persistida
  if (refreshToken == null || refreshToken.isEmpty) {
    return false;
  }
  
  // Tentar fazer refresh com o token existente
  try {
    await _authService.refreshAccessToken(refreshToken);
    return true;
  } catch (e) {
    // Token expirou ou inválido — limpar e fazer logout
    await _storage.delete(key: 'smartcore_admin_auth_refresh_token');
    return false;
  }
}
```

### 4. Sincronização com Logout

```dart
/// Logout limpa TUDO, inclusive refresh token
Future<void> logout() async {
  try {
    // Invalidar sessão no servidor (se necessário)
    await _authService.revokeRefreshToken();
    
    // Limpar storage local
    await _storage.deleteAll();
    
    // Limpar memória (access token em memória)
    _authService.clearAccessToken();
  } catch (e) {
    logger.e('Erro no logout: $e');
    // Mesmo com erro, limpar storage local (falha aberta)
    await _storage.deleteAll();
  }
}
```

### 5. Tratamento de Erros de Corrupção

```dart
/// Se os dados no storage forem corrompidos (chave expirada, etc)
Future<String?> getRefreshTokenSafe() async {
  try {
    return await _storage.read(key: 'smartcore_admin_auth_refresh_token');
  } on PlatformException catch (e) {
    // Dados corrompidos — limpar e deslogar
    logger.e('Storage corrompido: ${e.message}');
    await _storage.delete(key: 'smartcore_admin_auth_refresh_token');
    return null;
  }
}
```

---

## AndroidOptions e IOSOptions (Referência)

Embora o foco seja Web (WASM), o mesmo código roda no Windows/desktop futuramente. Configurações opcionais:

```dart
// Android: biometria opcional
AndroidOptions(
  biometricPromptTitle: 'Smart Core Admin',
  biometricPromptSubtitle: 'Autentique-se para acessar',
  encryptedSharedPreferences: true, // AES em SharedPreferences
)

// iOS: sincronização iCloud Keychain (opcional)
IOSOptions(
  accountName: 'com.smartcore.admin',
  synchronizable: true, // Sincroniza entre dispositivos Apple
  accessibility: KeychainAccessibility.first_this_device_this_device_only,
)
```

---

## Histórico de Atualizações

### 2026-06-14 — Criação da Documentação
- Coleta via Context7 da documentação oficial (versão 9.2.3+, v10.0.0 preview)
- Foco em **Web + WASM** (localStorage criptografado via Web Cryptography API)
- Documentação de limitações de segurança (XSS, HTTPS obrigatório)
- Exemplos práticos de namespacing, verificação de null e tratamento de erros
- Escopo: persistência do refresh token no smart-core-admin (access token em memória)

---

## Referências Externas

| Recurso | Link |
|---------|------|
| Pub.dev Package | https://pub.dev/packages/flutter_secure_storage |
| Documentação Oficial | https://pub.dev/documentation/flutter_secure_storage/latest/ |
| GitHub (flutter-secure-storage) | https://github.com/mogol/flutter_secure_storage |
| Web Cryptography API (MDN) | https://developer.mozilla.org/en-US/docs/Web/API/Web_Crypto_API |
| localStorage (MDN) | https://developer.mozilla.org/en-US/docs/Web/API/Window/localStorage |
| CSP (Content Security Policy) | https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP |
