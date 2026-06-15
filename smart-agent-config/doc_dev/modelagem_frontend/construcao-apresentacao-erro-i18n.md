# Especificação de Apresentação de Erro e Internacionalização (i18n)

Este documento padroniza, no monorepo `smart-core-assistant-v2`, **como erros são apresentados** ao usuário e **como o app é internacionalizado**. Resolve a pendência **G** ("Apresentação de erro + i18n") da §9 de [arquitetura-monorepo-frontend.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/arquitetura-monorepo-frontend.md).

Trabalha sobre o [presentation_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) (`ErrorState`/`AppError` no `ViewState`) e o `design_system_module` (componentes visuais de erro).

---

## 1. Princípios

1. **Toda falha chega como `AppError`** (do `return_success_or_error`), carregada no `ErrorState<T>` pelo `BaseController.execute()`. A UI **nunca** trata `Exception` cru.
2. **Mensagem de domínio ≠ mensagem de UI.** O `AppError.message` é técnico/diagnóstico; a UI mostra uma mensagem **amigável e localizada**, derivada do **tipo** do erro.
3. **A forma de exibição depende do contexto** (bloqueante vs. transitório), padronizada em três modos: **inline**, **snackbar** e **dialog**.

---

## 2. Mapeamento `AppError` → Mensagem Amigável Localizada

Um `ErrorMessageMapper` traduz o **tipo** do `AppError` para uma chave de i18n, resolvida pelo `AppLocalizations`. Vive no `presentation_module` (ou num `error_presentation` interno) para ser reutilizável por qualquer tela.

```dart
import 'package:flutter/widgets.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'l10n/app_localizations.dart';

/// Traduz um AppError técnico em uma mensagem amigável e localizada.
abstract final class ErrorMessageMapper {
  static String toMessage(BuildContext context, AppError error) {
    final l10n = AppLocalizations.of(context)!;
    return switch (error) {
      ErrorNetwork() => l10n.errorNetwork,        // "Sem conexão. Verifique sua internet."
      ErrorUnauthorized() => l10n.errorSession,   // "Sua sessão expirou. Entre novamente."
      ErrorValidation() => l10n.errorValidation,  // "Verifique os dados informados."
      _ => l10n.errorGeneric,                      // fallback amigável
    };
  }
}
```

> Os tipos concretos (`ErrorNetwork`, `ErrorUnauthorized`…) são os subtipos de `AppError` do `return_success_or_error`. Se um tipo ainda não existir, o `default (_)` cai na mensagem genérica — nunca se expõe stack/`message` técnico ao usuário.

---

## 3. Três Modos de Apresentação (convenção de UX)

| Modo | Quando usar | Como |
| :--- | :--- | :--- |
| **Inline** | A tela **inteira** depende do dado que falhou (lista não carregou). | `ErrorState` renderiza um corpo de erro com botão "Tentar de novo". É o **default** do `ModulePage.onError`. |
| **Snackbar** | Erro **transitório** numa ação pontual com a tela já preenchida (salvar/excluir falhou). | `BlocListener` observa `ErrorState` e dispara `SnackBar`; o corpo da tela permanece. |
| **Dialog** | Erro **bloqueante** que exige decisão (sessão expirou → ir ao login). | `BlocListener` abre `showDialog` com ação. |

### 3.1 Inline — default do `ModulePage.onError`

O `presentation_module` fornece um widget base `AppErrorView` (no `design_system_module`) usado pelo default:

```dart
// ModulePage.onError (override padrão recomendado nas features)
@override
Widget onError(BuildContext context, AppError error) => AppErrorView(
      message: ErrorMessageMapper.toMessage(context, error),
      onRetry: controller.loadTenants, // reexecuta a ação da tela
    );
```

### 3.2 Snackbar — ação pontual

```dart
BlocListener<TenantController, ViewState<List<Tenant>>>(
  bloc: inject<TenantController>(),
  listenWhen: (prev, curr) => curr is ErrorState,
  listener: (context, state) {
    if (state is ErrorState) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorMessageMapper.toMessage(context, state.error))),
      );
    }
  },
  child: /* corpo da tela */,
);
```

### 3.3 Dialog — erro bloqueante

```dart
listener: (context, state) {
  if (state is ErrorState && state.error is ErrorUnauthorized) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.sessionExpiredTitle),
        content: Text(ErrorMessageMapper.toMessage(context, state.error)),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(AppLocalizations.of(context)!.actionLogin),
          ),
        ],
      ),
    );
  }
}
```

---

## 4. Internacionalização (i18n / l10n)

Adota-se o **`flutter_localizations` + `gen-l10n`** (ARB), aproveitando o `intl` já presente nas dependências (§5.1 da arquitetura). Idioma base: **pt-BR**.

### 4.1 Configuração

```yaml
# pubspec.yaml do app (ou de um l10n_module compartilhado)
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true   # ativa o gen-l10n
```

```yaml
# l10n.yaml na raiz do app
arb-dir: lib/l10n
template-arb-file: app_pt.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
```

### 4.2 Arquivos ARB

```jsonc
// lib/l10n/app_pt.arb (base)
{
  "@@locale": "pt",
  "errorNetwork": "Sem conexão. Verifique sua internet.",
  "errorSession": "Sua sessão expirou. Entre novamente.",
  "errorValidation": "Verifique os dados informados.",
  "errorGeneric": "Algo deu errado. Tente novamente.",
  "sessionExpiredTitle": "Sessão expirada",
  "actionLogin": "Entrar"
}
```

```jsonc
// lib/l10n/app_en.arb (tradução)
{
  "@@locale": "en",
  "errorNetwork": "No connection. Check your internet.",
  "errorSession": "Your session expired. Sign in again.",
  "errorValidation": "Check the provided data.",
  "errorGeneric": "Something went wrong. Try again.",
  "sessionExpiredTitle": "Session expired",
  "actionLogin": "Sign in"
}
```

### 4.3 Registro no `MaterialApp.router`

```dart
MaterialApp.router(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'), // ou observável p/ troca de idioma
  theme: AppTheme.light,
  routerConfig: router,
);
```

> **Decisão de hospedagem:** os ARB e o `AppLocalizations` gerado vivem num **`l10n_module`** compartilhado (reexportado pelo `dependencies_module`) quando mais de um app precisa das mesmas strings; ou no próprio app quando exclusivas. O `ErrorMessageMapper` consome `AppLocalizations` por `BuildContext`.

---

## 5. Strings nas Features

- **Toda string visível ao usuário** vem do `AppLocalizations` — nunca literal espalhado na UI.
- **Mensagens de erro** sempre via `ErrorMessageMapper` (tipo do `AppError` → chave i18n).
- `intl` cuida de **datas, números e plurais** (`DateFormat`, `NumberFormat`, ICU plurals no ARB).

---

## 6. Resumo das Decisões de Design

- **Falha sempre como `AppError` no `ErrorState`** → UI nunca trata exceção crua.
- **`ErrorMessageMapper` (tipo → chave i18n)** → mensagem amigável e localizada, separada da técnica.
- **Três modos de UX (inline/snackbar/dialog)** → inline é default do `ModulePage`; snackbar/dialog via `BlocListener`.
- **`flutter_localizations` + `gen-l10n` (ARB), base pt-BR** → strings centralizadas; `intl` para datas/números/plurais.
- **Strings sempre do `AppLocalizations`** → zero literais de UI nas features.
