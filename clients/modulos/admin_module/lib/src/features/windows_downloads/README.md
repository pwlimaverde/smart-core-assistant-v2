# Feature: Windows Downloads (P11)

Tela segura de download do instalador Windows para administradores.

## Implementação

Esta feature implementa a interface E4 do plano PREVC (windows-releases-v01-beta):

- **Modelo de domínio**: `WindowsDownloadLink` com validação de expiração
- **Datasource**: Chama o RPC `GetWindowsDownloadLink` via gRPC
- **Página**: Exibe versão, tamanho, SHA-256 copiável e release notes em Markdown
- **Menu**: Item "Instalador Windows" aparece no drawer do admin

## Permissões

- A tela só é acessível para **superusuários** (claim `is_superuser` = true)
- Tentativas sem permissão resultam em erro `PERMISSION_DENIED`

## Dependência de regeneração de tipos gRPC

Os tipos `GetWindowsDownloadLinkRequest` e `GetWindowsDownloadLinkResponse` 
foram adicionados ao `server/crates/contracts/schemas/queries/admin.proto` (E3.1).

**Antes de compilar este código, é necessário regenerar os stubs Dart:**

```bash
# No CI, o protoc é executado automaticamente durante o build.
# Localmente (máquina dev), use:
cd clients/packages/api_client
protoc --dart_out=grpc:lib/ --proto_path=../../.. \
  ../../../server/crates/contracts/schemas/queries/admin.proto
```

Alternativamente, o build do Flutter web no CI dispara a regeneração automaticamente,
então este código ficará funcional após o merge na `dev`.

## Estrutura

```
windows_downloads/
├── domain/
│   ├── model/
│   │   └── windows_download_link.dart      # Modelo com helpers
│   ├── parameters/
│   │   └── windows_downloads_parameters.dart
│   ├── repositories/
│   │   └── windows_downloads_repository.dart  # Contrato
│   ├── errors/
│   │   └── windows_downloads_errors.dart
│   └── usecases/
│       └── windows_downloads_usecases.dart
├── data/
│   ├── datasources/
│   │   └── windows_downloads_datasources.dart  # Chama gRPC
│   └── repositories/
│       └── windows_downloads_repositories.dart
└── presentation/
    ├── pages/
    │   └── windows_downloads_page.dart        # UI
    ├── controllers/
    │   └── windows_downloads_controller.dart
    └── routes/
        └── windows_downloads_route.dart       # Integração
```

## Integração

1. ✓ Adicionada ao `admin_module.dart`:
   - Bindings de injeção (datasource → repository → usecase → controller)
   - Rota registrada (`/admin/windows-downloads`)

2. ✓ Menu item adicionado ao `admin_drawer.dart`:
   - Label: "Instalador Windows"
   - Ícone: `Icons.download`
   - Visível para todos (validação de permissão na página)

## Fluxo de uso

1. Admin acessa `/admin/windows-downloads`
2. Tela carrega automaticamente o link via `GetWindowsDownloadLink`
3. Exibe: versão, arquivo, tamanho, SHA-256, release notes
4. Admin clica "Baixar" → navegador abre link em nova aba
5. Link tem validade de 5 minutos (ticket HMAC validado pelo releases_server)

## Erros tratados

- `NotSuperuserError`: Não é administrador
- `InvalidChannelError`: Canal não existe (ex.: "stable" não suportado em beta)
- `ReleasesNotConfiguredError`: Serviço de downloads não configurado
- `NoReleaseFoundError`: Nenhuma release disponível no canal
- `GrpcError`: Erros de rede ou backend

Cada erro exibe mensagem amigável e oferece botão "Tentar Novamente".
