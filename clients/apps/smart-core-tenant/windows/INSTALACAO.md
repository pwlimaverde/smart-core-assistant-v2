# Instalação do Smart Core Tenant no Windows

## Caminho de Instalação

Por padrão, o Velopack instala a aplicação em:

```
%LOCALAPPDATA%\SmartCoreTenant\
```

Onde `%LOCALAPPDATA%` expande para:
- **Windows 11/10:** `C:\Users\[NomeDoUsuário]\AppData\Local\SmartCoreTenant\`

### Estrutura da Pasta

```
SmartCoreTenant/
├── app-[versão]/          # Binários da aplicação
│   ├── smart_core_tenant.exe
│   ├── flutter_windows.dll
│   └── ...
├── Update.exe             # Auto-updater do Velopack
└── [outros arquivos de controle]
```

## Flutter Secure Storage

A configuração `flutter_secure_storage_windows` armazena dados na pasta:

```
%APPDATA%\SmartCoreTenant\
```

Ou: `C:\Users\[NomeDoUsuário]\AppData\Roaming\SmartCoreTenant\`

Isso diferencia dados da aplicação (Local) de dados sensíveis (Roaming).

## Desinstalação

Desinstalar via Painel de Controle → Programas → Programas e Recursos.

O Velopack remove automaticamente a pasta de instalação em `%LOCALAPPDATA%`.

## D4 Status

- [x] Caminho documentado
- [x] Estrutura explicada
- [x] Flutter Secure Storage nota
