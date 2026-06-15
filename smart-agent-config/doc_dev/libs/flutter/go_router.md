# Go Router (go_router)

- **Versão Recomendada:** 17.3.0 (estável mais recente; compatível com Flutter 3.44.2/Dart 3.12.2 — exige Flutter ≥ 3.38 / Dart ≥ 3.10)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Roteamento declarativo, navegação e passagem de parâmetros com suporte completo a URL deep-linking no Flutter (essencial para o port Web na Fase 2).
- **Documentação Oficial:** [https://pub.dev/packages/go_router](https://pub.dev/packages/go_router)
- **Source (Context7):** `/websites/pub_dev_packages_go_router` | Reputation: High | Code Snippets: 132

---

## 1. Contexto e Uso no Projeto

O aplicativo do atendente no Smart Core Assistant v2 possui uma estrutura de telas aninhada:
- `/login`: Tela de autenticação.
- `/workspace`: Painel de seleção de inquilinos.
- `/workspace/:tenantId`: Dashboard principal de atendimento.
  - Aninhado: `/workspace/:tenantId/kanban` (Mesa de atendimento Kanban).
  - Aninhado: `/workspace/:tenantId/chat/:ticketId` (Conversa aberta em foco).

O **Go Router** permite gerenciar essa hierarquia de rotas declarativamente em um único objeto de configuração central, facilitando a sincronização da URL com o estado da aplicação na Fase Web.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Configuração Declarativa de Rotas
Declare a estrutura de rotas aninhando `GoRoute` e definindo os parâmetros dinâmicos na URL.

```dart
// lib/app/routes.dart
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/workspace',
      builder: (context, state) => const WorkspaceSelectionPage(),
      routes: [
        // Rota aninhada com parâmetro na URL: /workspace/f47ac10b
        GoRoute(
          path: ':tenantId',
          builder: (context, state) {
            final tenantId = state.pathParameters['tenantId']!;
            return DashboardLayout(tenantId: tenantId);
          },
          routes: [
            GoRoute(
              path: 'kanban',
              builder: (context, state) => const KanbanBoardPage(),
            ),
            GoRoute(
              path: 'chat/:ticketId',
              builder: (context, state) {
                final ticketId = state.pathParameters['ticketId']!;
                return ChatDetailPage(ticketId: ticketId);
              },
            ),
          ],
        ),
      ],
    ),
  ],
);
```

### 2.2 Navegação Tipada e Parâmetros
Para navegar, utilize a sintaxe declarativa `.go()` enviando os parâmetros obrigatórios no caminho. Evite `.push()` para navegação estruturada, pois o `.push()` não atualiza a URL do navegador no port Web de forma consistente com o histórico do navegador.

*   **Incorreto (Não Faça):**
    ```dart
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage()));
    ```
*   **Correto (Faça):**
    ```dart
    context.go('/workspace/$tenantId/chat/$ticketId');
    ```

### 2.3 Redirecionamento Global para Proteção de Rotas (Guarda de Rotas)
Use o parâmetro `redirect` do `GoRouter` para interceptar navegações e redirecionar o usuário para a tela de login caso ele não esteja autenticado ou não possua acesso ao tenant selecionado.

```dart
final GoRouter appRouter = GoRouter(
  redirect: (context, state) {
    final bool loggedIn = authService.isAuthenticated;
    final bool loggingIn = state.matchedLocation == '/login';

    if (!loggedIn) {
      return '/login';
    }

    if (loggedIn && loggingIn) {
      return '/workspace';
    }

    return null; // Mantém a rota de destino
  },
  // ...
);
```

---

## 3. Guia de Uso Rápido (v14.0.0+)

### 3.1 Construção Básica de GoRouter

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'home', // Identificador nomeado
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
    ),
    GoRoute(
      path: '/details/:id',
      name: 'details',
      builder: (BuildContext context, GoRouterState state) {
        final id = state.pathParameters['id']!;
        return DetailsScreen(id: id);
      },
    ),
  ],
);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: router);
  }
}
```

### 3.2 Redirect e Autenticação (Guards)

```dart
final GoRouter authenticatedRouter = GoRouter(
  redirect: (BuildContext context, GoRouterState state) {
    final isLoggedIn = authService.isAuthenticated;
    final isLoggingIn = state.matchedLocation == '/login';

    if (!isLoggedIn && !isLoggingIn) {
      return '/login'; // Redireciona se não autenticado
    }

    if (isLoggedIn && isLoggingIn) {
      return '/home'; // Redireciona se já logado tentando acessar login
    }

    return null; // Permite a navegação
  },
  routes: [
    // ... suas rotas
  ],
);
```

### 3.3 RefreshListenable para Reavaliar Redirect

Quando o estado de autenticação muda (ex: login/logout), reavalie automaticamente os redirects usando `ValueNotifier`:

```dart
class AuthNotifier extends ValueNotifier<bool> {
  AuthNotifier() : super(false);

  void login() {
    value = true;
  }

  void logout() {
    value = false;
  }
}

final authNotifier = AuthNotifier();

final GoRouter router = GoRouter(
  refreshListenable: authNotifier, // Reavaliar quando authNotifier.value muda
  redirect: (BuildContext context, GoRouterState state) {
    final isLoggedIn = authNotifier.value;
    final isLoggingIn = state.matchedLocation == '/login';

    if (!isLoggedIn && !isLoggingIn) {
      return '/login';
    }

    if (isLoggedIn && isLoggingIn) {
      return '/home';
    }

    return null;
  },
  routes: [
    // ...
  ],
);

// Ao fazer login
authNotifier.login(); // Triggers redirect reevaluation
```

### 3.4 Navegação: context.go() vs context.push()

```dart
// context.go() - SUBSTITUI a rota atual (recomendado para navegação estruturada)
context.go('/home');
context.go('/workspace/tenant123/chat/ticket456');

// context.push() - ADICIONA à pilha de navegação (para diálogos/modais)
context.push('/details/123'); // Cria uma entrada no histórico
```

### 3.5 Leitura de Parâmetros com GoRouterState

```dart
GoRoute(
  path: '/workspace/:tenantId/chat/:ticketId',
  builder: (BuildContext context, GoRouterState state) {
    final tenantId = state.pathParameters['tenantId']!;
    final ticketId = state.pathParameters['ticketId']!;
    
    // Acessar estado da rota
    final location = state.location; // Ex: /workspace/t123/chat/tk456
    final uri = state.uri; // Uri completa
    
    return ChatPage(tenantId: tenantId, ticketId: ticketId);
  },
)
```

### 3.6 InitialLocation

```dart
final GoRouter router = GoRouter(
  initialLocation: '/workspace', // Rota inicial ao abrir o app
  routes: [
    // ...
  ],
);
```

---

## 4. Breaking Changes e Migração

### v5.0.0 (2022)

- **Redesign de `redirect`**: suporte para async, passa `BuildContext`
- **Removidos**: `GoRouterRefreshStream`, `navigatorBuilder`, `urlPathStrategy`
- **Nova feature**: `GoRouter` implementa `RouterConfig` diretamente

### v6.0.0 (2022)

- `redirect` e `buildPage` agora recebem `BuildContext` e `GoRouterState`
- Rename: `replace()` → `pushReplacement()`, `replaceNamed()` → `pushReplacementNamed()`

### v13.2.0 → v14.0.0+

- **Compatibilidade**: Dart SDK 3.7+
- **Mudanças menores**: refinamentos em gerenciamento de estado e callbacks
- **Recomendação**: Usar v14.0.0+ para projeto novo ou com Flutter 3.44.2

### v17.2.3 (Atual Estável)

- **Compatibilidade**: Dart SDK 3.9+
- **Novo em v17.2.0**: Correção em `refreshListenable` callbacks durante re-entrada de rota
- **Novo**: Parâmetros `encoder`, `decoder`, `compare` em `TypedQueryParameter`
- **Nota**: Flutter 3.44.2 (Dart 3.12.2) é compatível

---

## 5. Histórico de Atualizações

| Versão | Data | Motivo |
| --- | --- | --- |
| 13.2.0 → 14.0.0 | 2026-06-14 | Alinhamento ao navigation_module do monorepo frontend; compatibilidade com Flutter 3.44.2/Dart 3.12.2 (fixação em ^14.0.0) |
| 14.0.0 → 17.2.3 | 2026-06-14 | Versão estável atual; considerar upgrade para futuras melhorias se Dart 3.9 for suportado |
