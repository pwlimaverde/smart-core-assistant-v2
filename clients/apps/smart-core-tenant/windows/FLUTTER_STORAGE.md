# Flutter Secure Storage - Migração Windows

## Problema (E1)

O `flutter_secure_storage_windows` monta o caminho de armazenamento em:

```
%APPDATA%\[CompanyName]\[ProductName]\
```

No `Runner.rc`, foi alterado:
- **Antes:** CompanyName = "com.example" / ProductName = "smart_core_tenant"
- **Depois:** CompanyName = "Smart Core" / ProductName = "Smart Core Tenant"

Caminho **antigo:**
```
C:\Users\[User]\AppData\Roaming\com.example\smart_core_tenant\
```

Caminho **novo:**
```
C:\Users\[User]\AppData\Roaming\Smart Core\Smart Core Tenant\
```

## Impacto na Autenticação

Os tokens OAuth (access_token, refresh_token) são armazenados em `credenciais_seguras` usando a chave padrão do plugin. Se o caminho mudar:

- ✅ **Novo usuário:** Autentica normalmente (caminho novo criado)
- ⚠️ **Usuário existente:** Perde credenciais (caminho antigo não é migrado)

## Opções de Resolução

### Opção 1: Aceitar novo login (recomendado)

Simples, sem complexidade. O usuário faz login novamente de uma única vez.

**Passo-a-passo:**
1. Instale a versão com Runner.rc alterado
2. Aplicação detecta credenciais ausentes → abre tela de login
3. Usuário autentica → nova pasta em `Smart Core\Smart Core Tenant\`
4. Aplicação funciona normalmente

### Opção 2: Migração automática

Adicionar código no `main.dart` ou no boot da aplicação para:

```dart
// Pseudocódigo
final oldPath = "${appData.path}\\com.example\\smart_core_tenant";
final newPath = "${appData.path}\\Smart Core\\Smart Core Tenant";

if (Directory(oldPath).existsSync() && !Directory(newPath).existsSync()) {
  // Copiar credenciais de oldPath para newPath
  // Limpar oldPath
}
```

Isso requer acesso ao filesystem e pode variar conforme a versão do flutter_secure_storage_windows.

### Opção 3: Manter compatibilidade

Reverter `Runner.rc` para nomes em minúsculas/sem espaços:
- CompanyName = "smartcore"
- ProductName = "smartcoretenantapp"

Caminho: `C:\Users\[User]\AppData\Roaming\smartcore\smartcoretenantapp\`

**Trade-off:** UI menos amigável ("Propriedades" do .exe fica com "smartcore" em vez de "Smart Core").

## Decisão Atual

**Status: Aceitar novo login (Opção 1)**

- Simples de implementar
- Sem risco de corrupção de dados
- Usuário não reclama de re-autenticação única

## E1 Status

- [x] Caminho documentado
- [x] Impacto explicado
- [x] Opções listadas
- [x] Decisão: Aceitar novo login
