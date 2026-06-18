# design_system_module

Fonte única da identidade visual do app (gold + stone, derivada do Smart Core).
Todos os outros módulos consomem cores, tipografia, espaçamento e componentes
**daqui** — nenhuma tela define cor/medida hardcoded.

## Princípio: camadas

Espelha a separação do design original (`workspace-tokens.css` → `workspace.css`):

| Camada | Onde | Papel | Quando editar |
|---|---|---|---|
| **Primitivos** | `tokens/app_palette.dart` (`AppPalette`) | Cores cruas das escalas `stone`/`gold`/feedback. Sem significado. | Quase nunca — só ao mudar a paleta de marca. |
| **Semânticos** | `theme/app_colors.dart` (`AppColors`) | Tokens com papel (`bg`, `fg`, `accent`, `danger`…) sensíveis ao tema claro/escuro. | Ao mapear um papel a uma cor primitiva diferente. |
| **Escalares** | `tokens/` (`AppSpacing`, `AppRadius`, `AppShadows`, `AppMotion`, `AppTypography`) | Medidas, raios, sombras, durações, tipografia. | Ao ajustar densidade/medidas globais. |
| **Tema** | `theme/app_theme.dart` (`AppTheme`) | Monta `ThemeData` (claro = padrão, escuro = opção), registra `AppColors` como `ThemeExtension` e estiliza inputs/botões/cards. | Ao mudar como um componente Material padrão se apresenta. |
| **Componentes** | `widgets/` | Widgets reutilizáveis (`PrimaryButton`, `AppTextField`, `AppCard`, `AppLogo`, `AppScaffold`, `AppErrorView`). | Ao criar/alterar um componente compartilhado. |

> **Tema escuro "de graça":** como tudo é token, basta `AppColors.dark`
> sobrescrevendo as cores — nenhum componente muda. Claro é o padrão.

## Como consumir (nas telas/módulos)

```dart
import 'package:dependencies_module/dependencies_module.dart'; // reexporta o DS

// Cores semânticas do tema ativo (claro/escuro):
final colors = context.colors;
Container(color: colors.card, ...);
Text('...', style: TextStyle(color: colors.fgMuted));

// Escalares:
const SizedBox(height: AppSpacing.md);
borderRadius: AppRadius.card;
boxShadow: AppShadows.sm;

// Componentes:
PrimaryButton(label: 'Entrar', onPressed: ...);
AppTextField(label: 'Senha', obscureText: true, obscureToggle: true);
```

Regras:
- **Nunca** use `AppPalette.*` direto em telas — use `context.colors.*`.
- **Nunca** hardcode `Color(0x..)`, `EdgeInsets` mágicos ou raios soltos.
- Cor de papel ainda sem token? Adicione um campo em `AppColors`
  (light + dark + `copyWith`/`lerp`) antes de usar.

## Próximos componentes (quando as telas existirem)

Os primitivos de chat (`AppPalette.chat*`) já estão reservados. Componentes de
workspace (kanban card, bolha de chat, info drawer, mini-bar, composer) entram
em `widgets/` conforme as telas que os consomem forem construídas.
