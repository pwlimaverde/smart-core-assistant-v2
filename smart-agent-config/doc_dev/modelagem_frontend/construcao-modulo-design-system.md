# Especificação de Construção do Módulo `design_system_module`

Este documento detalha a estrutura, dependências e implementação do módulo de infraestrutura **`design_system_module`**. Ele padroniza a **identidade visual** de todos os apps do monorepo `smart-core-assistant-v2`: tokens de design (cores, tipografia, espaçamento, raios), o `ThemeData` (claro/escuro) e os **widgets base** reutilizáveis.

Resolve a pendência **I** ("Aplicação de tema do Design System") da §9 de [arquitetura-monorepo-frontend.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/arquitetura-monorepo-frontend.md).

> Por expor widgets e usar o Flutter SDK, é um **módulo** (`clients/modulos/`), não um package Dart puro.

---

## 1. Responsabilidades

| Camada | Artefato | Papel |
| :--- | :--- | :--- |
| **Tokens** | `AppColors`, `AppTypography`, `AppSpacing`, `AppRadius` | Valores primitivos e semânticos, **fonte única** de design. Nenhum widget usa `Colors.x`/números mágicos. |
| **Tema** | `AppTheme.light` / `AppTheme.dark` | Monta o `ThemeData` a partir dos tokens. Consumido pelo `MaterialApp.router`. |
| **Widgets base** | `PrimaryButton`, `AppTextField`, `AppCard`, `AppScaffold`… | Componentes reutilizáveis já estilizados pelo tema. As features compõem com eles, não recriam estilos. |

**Regra de ouro:** nenhuma feature define cor, fonte, espaçamento ou raio "na mão". Tudo vem dos tokens via `Theme.of(context)` ou dos widgets base.

---

## 2. Estrutura de Diretórios

```text
clients/modulos/design_system_module/
├── pubspec.yaml
└── lib/
    ├── design_system_module.dart        # Exportação pública
    └── src/
        ├── tokens/
        │   ├── app_colors.dart          # paleta primitiva + cores semânticas
        │   ├── app_typography.dart      # escala tipográfica (TextTheme)
        │   ├── app_spacing.dart         # espaçamentos (4/8/12/16/24/32)
        │   └── app_radius.dart          # raios de borda
        ├── theme/
        │   └── app_theme.dart           # AppTheme.light / AppTheme.dark (ThemeData)
        └── widgets/
            ├── primary_button.dart
            ├── app_text_field.dart
            ├── app_card.dart
            └── app_scaffold.dart
```

---

## 3. Configuração de Dependências (`pubspec.yaml`)

```yaml
name: design_system_module
description: Design System comum (tokens, ThemeData claro/escuro e widgets base) do monorepo.
version: 1.0.0
publish_to: 'none'

environment:
  sdk: ^3.12.2
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter
```

> O `design_system_module` é **folha**: não depende de `get_it_module`, `api_client` nem de outros módulos. Só do Flutter SDK. Isso o mantém reutilizável e sem ciclos.

---

## 4. Código de Implementação

### 4.1 Tokens — cores (`lib/src/tokens/app_colors.dart`)

```dart
import 'package:flutter/material.dart';

/// Fonte única de cores. Primitivas (privadas) + semânticas (públicas).
abstract final class AppColors {
  // Primitivas — não usar direto na UI.
  static const _blue600 = Color(0xFF2563EB);
  static const _red600 = Color(0xFFDC2626);
  static const _slate900 = Color(0xFF0F172A);
  static const _slate50 = Color(0xFFF8FAFC);

  // Semânticas — a API que a UI consome.
  static const primary = _blue600;
  static const error = _red600;
  static const surfaceLight = _slate50;
  static const surfaceDark = _slate900;
}
```

### 4.2 Tokens — tipografia e espaçamento

```dart
// lib/src/tokens/app_typography.dart
import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const TextTheme textTheme = TextTheme(
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  );
}

// lib/src/tokens/app_spacing.dart
abstract final class AppSpacing {
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32;
}

// lib/src/tokens/app_radius.dart
import 'package:flutter/widgets.dart';
abstract final class AppRadius {
  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius md = BorderRadius.all(Radius.circular(12));
}
```

### 4.3 Tema (`lib/src/theme/app_theme.dart`)

```dart
import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';

/// Monta o ThemeData a partir dos tokens. Consumido pelo MaterialApp.router.
abstract final class AppTheme {
  static ThemeData get light => _base(Brightness.light, AppColors.surfaceLight);
  static ThemeData get dark => _base(Brightness.dark, AppColors.surfaceDark);

  static ThemeData _base(Brightness brightness, Color surface) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      error: AppColors.error,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme,
      scaffoldBackgroundColor: scheme.surface,
    );
  }
}
```

### 4.4 Widget base (`lib/src/widgets/primary_button.dart`)

```dart
import 'package:flutter/material.dart';

/// Botão primário padronizado. Estilo vem do tema (não hardcoded).
final class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}
```

### 4.5 Exportação Pública (`lib/design_system_module.dart`)

```dart
library design_system_module;

export 'src/tokens/app_colors.dart';
export 'src/tokens/app_typography.dart';
export 'src/tokens/app_spacing.dart';
export 'src/tokens/app_radius.dart';
export 'src/theme/app_theme.dart';
export 'src/widgets/primary_button.dart';
export 'src/widgets/app_text_field.dart';
export 'src/widgets/app_card.dart';
export 'src/widgets/app_scaffold.dart';
```

---

## 5. Aplicação do Tema no App (resolve a pendência I)

O `MaterialApp.router` consome o tema **direto do `design_system_module`** (reexportado pelo `dependencies_module`). O `themeMode` pode ser fixo ou observável.

```dart
import 'package:dependencies_module/dependencies_module.dart';

class SmartCoreAdminApp extends StatelessWidget {
  final GoRouter router;
  const SmartCoreAdminApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Smart Core Admin',
      theme: AppTheme.light,        // tema claro do design system
      darkTheme: AppTheme.dark,     // tema escuro do design system
      themeMode: ThemeMode.system,  // segue o SO (ou ValueListenable p/ toggle)
      routerConfig: router,
    );
  }
}
```

### 5.1 Tema observável (toggle de tema — opcional)

Quando houver troca de tema em runtime, expõe-se um `ThemeMode` observável como serviço global (`ThemeController`), e o `MaterialApp.router` é envolvido por um `ValueListenableBuilder`:

```dart
ValueListenableBuilder<ThemeMode>(
  valueListenable: inject<ThemeController>(),
  builder: (_, mode, __) => MaterialApp.router(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: mode,
    routerConfig: router,
  ),
);
```

---

## 6. Consumo nas Features

A feature **nunca** define estilos: usa o tema e os widgets base.

```dart
import 'package:dependencies_module/dependencies_module.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme; // cores do tema
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg), // token de espaçamento
      child: Column(
        children: [
          const AppTextField(label: 'E-mail'),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Entrar', onPressed: () {}), // widget base
        ],
      ),
    );
  }
}
```

---

## 7. Resumo das Decisões de Design

- **Tokens como fonte única** → cor/tipografia/espaçamento/raio nunca hardcoded nas features.
- **`AppTheme` monta o `ThemeData`** → consumido pelo `MaterialApp.router` via `theme`/`darkTheme`/`themeMode`.
- **Widgets base estilizados pelo tema** → consistência visual sem repetição.
- **Módulo folha (só Flutter SDK)** → reutilizável, sem ciclos, sem DI.
- **Tema observável opcional** → troca em runtime via `ThemeController` + `ValueListenableBuilder`.
