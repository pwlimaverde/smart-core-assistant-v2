# Melos

- **Versão Recomendada:** 7.8.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Orquestração do monorepo Flutter em `clients/` (bootstrap, analyze, test e scripts unificados sobre os pacotes em `apps/**`, `modulos/**`, `packages/**`).
- **Documentação Oficial:** [https://melos.invertase.dev/](https://melos.invertase.dev/)

---

## 1. Mudança Estrutural (Melos 7.x — Pub Workspaces)

A partir do Melos **6.x/7.x**, o modelo de configuração mudou: o Melos passou a se
apoiar nos **Pub Workspaces** nativos do Dart (disponíveis a partir do Dart 3.6 e
recomendados em 3.9+). Consequências práticas para o projeto (Dart 3.12.2):

- **Não há mais `melos.yaml` standalone** como antigamente. A configuração do
  workspace e os scripts do Melos vivem no **`pubspec.yaml` raiz** do workspace.
- O `pubspec.yaml` raiz declara os membros do workspace no campo **`workspace:`**.
- **Cada pacote membro** deve declarar **`resolution: workspace`** no seu
  `pubspec.yaml` e ter `environment.sdk` compatível (`^3.9.0` ou superior; o
  projeto usa `^3.12.2`).
- O `pub get` passa a ser **único e compartilhado** para todo o workspace (um
  `.dart_tool/package_config.json` na raiz), eliminando o `pub get` por pacote.

> Compatibilidade: Melos 7.x exige Dart SDK `^3.9.0`. O monorepo usa Dart 3.12.2,
> então é compatível.

---

## 2. Configuração Mínima

### 2.1 `pubspec.yaml` raiz do workspace (`clients/pubspec.yaml`)

```yaml
name: smart_core_clients_workspace
publish_to: none

environment:
  sdk: ^3.12.2

# Membros do workspace (Pub Workspaces)
workspace:
  - apps/smart-core-admin
  - modulos/dependencies_module
  - modulos/design_system_module
  - modulos/core_module
  - modulos/presentation_module
  - modulos/navigation_module
  - modulos/initial_loading_module
  - packages/get_it_module
  - packages/app_config
  - packages/api_client
  - packages/domain_models

dev_dependencies:
  melos: ^7.0.0

# Configuração do Melos (substitui o antigo melos.yaml)
melos:
  scripts:
    analyze:
      run: melos exec --fail-fast -- dart analyze .
      description: Analisa todos os pacotes do workspace.
    test:
      run: melos exec --fail-fast -c 1 -- flutter test
      description: Roda os testes de todos os pacotes (sequencial).
    get:
      run: melos bootstrap
      description: Resolve dependências do workspace inteiro.
```

> Observação: globs como `apps/**` também são aceitos pelo `workspace:`/Melos,
> mas listar explicitamente os membros evita capturar pastas geradas.

### 2.2 `pubspec.yaml` de cada pacote membro

```yaml
name: <nome_do_pacote>

environment:
  sdk: ^3.12.2

resolution: workspace   # OBRIGATÓRIO em todos os membros

dependencies:
  # ...
```

---

## 3. Comandos Principais

| Comando | Uso |
| :-- | :-- |
| `melos bootstrap` (ou `melos bs`) | Resolve e sincroniza dependências de todo o workspace (`pub get` único). |
| `melos run <script>` | Executa um script definido na seção `melos.scripts` (ex.: `melos run analyze`). |
| `melos exec -- <cmd>` | Roda `<cmd>` em cada pacote do workspace. |
| `melos exec -c 1 -- <cmd>` | Limita a concorrência a 1 (execução sequencial). |
| `melos exec --fail-fast -- <cmd>` | Aborta na primeira falha. |
| `melos list` | Lista os pacotes do workspace. |

Ativação: `dart pub global activate melos` (ou usar como `dev_dependency` e
invocar via `dart run melos`).

---

## 4. Guia de Uso Rápido (fluxo do projeto)

```bash
cd clients
dart pub global activate melos      # uma vez por máquina (ou usar dev_dependency)
melos bootstrap                     # resolve tudo
melos run analyze                   # dart/flutter analyze em todos
melos run test                      # testes em todos
```

---

## Histórico de Atualizações

- **2026-06-14** — Criação do doc. Versão recomendada 7.0.0. Registrado o modelo
  atual baseado em **Pub Workspaces** (configuração no `pubspec.yaml` raiz com
  `workspace:` + seção `melos:`, e `resolution: workspace` por pacote), que
  substitui o antigo `melos.yaml` standalone. Motivo: adoção do Melos para
  orquestrar o monorepo frontend em `clients/`.
