# Go Router (go_router)

- **Versão Recomendada:** 13.2.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Roteamento declarativo, navegação e passagem de parâmetros com suporte completo a URL deep-linking no Flutter (essencial para o port Web na Fase 2).
- **Documentação Oficial:** [https://pub.dev/packages/go_router](https://pub.dev/packages/go_router)

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
